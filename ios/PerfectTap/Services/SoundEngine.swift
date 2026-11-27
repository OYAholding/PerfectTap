import AVFoundation
import Foundation

// MARK: - Sound types (ported from soundEngine.jsx)
enum SoundType {
    case perfect, great, good, miss
    case comboBreak, comboMilestone
    case challengeComplete, dailyReward
    case countdown, countdownGo
}

// MARK: - SoundEngine using AVAudioEngine with reusable node pool
// Ports the Web Audio API procedural sounds from soundEngine.jsx.
//
// Threading (1.1.1): every AVAudioEngine / AVAudioPlayerNode call runs on one
// serial `audioQueue`, never on the main thread. `AVAudioPlayerNode.stop()`,
// `play()` and `scheduleBuffer` synchronise with the audio render thread and
// measured ~10 ms per call in the simulator: the old music loop called them 17×
// on the main thread every 10.7 s (~177 ms stall each time, docs/perf), and the
// first game paid ~330 ms of engine setup on the main thread. Ordering is kept
// by the serial queue (a sound requested before setup finishes simply plays
// once the graph is ready).
//
// Music is now one pre-rendered 16-beat buffer looped by a single node
// (`.loops`), so nothing is rescheduled during play.
//
// Cosmetic sound packs (Studio): themed packs are bundled CAF files decoded
// once into PCM buffers on `synthQueue` and cached on `audioQueue` (active pack
// + last previewed pack only). They play through the same 8-node pool, so a tap
// still only enqueues one block; nothing touches disk on the tap path. A
// separate preview node lets the Studio stop previews without cutting gameplay
// voices. Buffers are plain memory, so engine restarts (interruption, route or
// hardware change) keep them — nothing is rebuilt after a restart.
final class SoundEngine {

    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat

    // Main-thread state (settings cache — no UserDefaults I/O per play()).
    private var isSoundEnabled: Bool
    private var isMusicEnabled: Bool
    private var musicActive = false

    // audioQueue-owned state
    private let audioQueue = DispatchQueue(label: "com.perfecttap.audio", qos: .userInitiated)
    private let synthQueue = DispatchQueue(label: "com.perfecttap.audio.synth", qos: .utility)
    private let poolSize = 8
    private var playerPool: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private let musicPlayer = AVAudioPlayerNode()
    private var musicLoopBuffer: AVAudioPCMBuffer?
    private var musicWanted = false
    private var bufferCache: [SoundType: [ScheduledTone]] = [:]

    // Cosmetic packs. `activeSoundPackID` is main-thread state (read on every
    // tap without locking, like `isSoundEnabled`); everything below it is
    // audioQueue-owned.
    private(set) var activeSoundPackID: String = SoundPackCatalog.defaultPackID
    private let previewPlayer = AVAudioPlayerNode()
    private var packCache: [String: SoundPackBuffers] = [:]
    private var packsLoading: Set<String> = []
    private var packLoadWaiters: [String: [(SoundPackBuffers?) -> Void]] = [:]
    private var queueActivePackID: String = SoundPackCatalog.defaultPackID
    private var queuePreviewPackID: String?
    /// Bumped by `stopPreview()`; a preview whose pack finishes loading after
    /// the user left (or started another preview) is dropped.
    private var previewGeneration = 0
    private var variantCursor: [CosmeticEvent: Int] = [:]
    /// Per pool node: host time its current sound ends, and whether that sound
    /// is high priority (perfect / miss / life lost / game over).
    private var voiceEnds: [CFTimeInterval] = []
    private var voiceIsPriority: [Bool] = []
    /// Built-in tones pre-mixed into one buffer each, for the single preview node.
    private var defaultPreviewBuffers: [SoundType: AVAudioPCMBuffer] = [:]

    private init() {
        isSoundEnabled = UserDefaults.standard.object(forKey: "perfecttap_sound") as? Bool ?? true
        isMusicEnabled = UserDefaults.standard.object(forKey: "perfecttap_music") as? Bool ?? true

        // 44100 Hz mono PCM float — guaranteed to succeed for standard parameters
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            fatalError("SoundEngine: Failed to create AVAudioFormat — this should never happen with standard parameters")
        }
        format = fmt
        audioQueue.async { [self] in
            Perf.measure("audio.graphSetup.offMain") { setupGraph() }
        }
        precacheBuffers()
        observeAudioSession()
    }

    /// Touch at app launch so engine setup happens long before the first game.
    func warmUp() {}

    /// Call when user changes sound/music settings
    func refreshSettings() {
        isSoundEnabled = UserDefaults.standard.object(forKey: "perfecttap_sound") as? Bool ?? true
        isMusicEnabled = UserDefaults.standard.object(forKey: "perfecttap_music") as? Bool ?? true
    }

    // MARK: - Setup (audioQueue)

    private func setupGraph() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playerPool.append(player)
        }
        voiceEnds = Array(repeating: 0, count: poolSize)
        voiceIsPriority = Array(repeating: false, count: poolSize)
        engine.attach(musicPlayer)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.attach(previewPlayer)
        engine.connect(previewPlayer, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    private func ensureRunning() {
        if !engine.isRunning { try? engine.start() }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .ended else { return }
            self.audioQueue.async {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.restartAfterEngineStop()
            }
        }
        // Route / hardware change (AirPods connect, Bluetooth, sample-rate change)
        // stops the engine. Restart here, off the tap path — previously the next
        // tap restarted it synchronously on the main thread.
        // No separate `routeChangeNotification` observer is needed for cosmetic
        // packs: a route change that alters the hardware format posts this
        // notification; one that doesn't leaves the engine running. Pack buffers
        // are in the player format (not the hardware format), so the mixer
        // converts to any new output rate without rebuilding them.
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.audioQueue.async { self.restartAfterEngineStop() }
        }
    }

    private func restartAfterEngineStop() {
        try? engine.start()
        if musicWanted {
            musicPlayer.stop()
            startMusicLocked()
        }
    }

    // MARK: - Pre-cached buffer generation

    private struct ScheduledTone {
        let buffer: AVAudioPCMBuffer
        let delaySeconds: Double
    }

    private func precacheBuffers() {
        synthQueue.async { [self] in
            var cache: [SoundType: [ScheduledTone]] = [:]
            for (type, configs) in soundConfigs {
                cache[type] = configs.compactMap { config -> ScheduledTone? in
                    guard let buffer = generateBuffer(config: config) else { return nil }
                    return ScheduledTone(buffer: buffer, delaySeconds: Double(config.delay))
                }
            }
            var previewMix: [SoundType: AVAudioPCMBuffer] = [:]
            for (type, tones) in cache {
                previewMix[type] = mixDown(tones)
            }
            audioQueue.async {
                self.bufferCache = cache
                self.defaultPreviewBuffers = previewMix
            }

            let loop = makeMusicLoopBuffer()
            audioQueue.async {
                self.musicLoopBuffer = loop
                if self.musicWanted { self.startMusicLocked() }
            }
        }
    }

    /// Sums a multi-tone sound (e.g. PERFECT = 880 Hz + 1100 Hz 60 ms later)
    /// into one buffer, so it can be previewed on the single preview node with
    /// the same timing the pool produces in gameplay.
    private func mixDown(_ tones: [ScheduledTone]) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let total = tones.map { AVAudioFrameCount($0.delaySeconds * sampleRate) + $0.buffer.frameLength }.max() ?? 0
        guard total > 0,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let dst = out.floatChannelData?[0] else { return nil }
        out.frameLength = total
        for i in 0..<Int(total) { dst[i] = 0 }
        for tone in tones {
            guard let src = tone.buffer.floatChannelData?[0] else { continue }
            let offset = Int(tone.delaySeconds * sampleRate)
            for i in 0..<Int(tone.buffer.frameLength) { dst[offset + i] += src[i] }
        }
        return out
    }

    private func generateBuffer(config: ToneConfig) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        let durSeconds = Double(config.duration)
        let frames = AVAudioFrameCount(durSeconds * sampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        let twoPiF = Float.pi * 2 * config.frequency

        for i in 0..<Int(frames) {
            let t = Float(i) / Float(sampleRate)
            let envelope = max(0, 1.0 - (t / Float(durSeconds)))
            let sample: Float
            switch config.waveType {
            case .sine:     sample = sin(twoPiF * t)
            case .sawtooth: sample = 2.0 * (t * config.frequency).truncatingRemainder(dividingBy: 1.0) - 1.0
            case .triangle: sample = 2.0 * abs(2.0 * (t * config.frequency).truncatingRemainder(dividingBy: 1.0) - 1.0) - 1.0
            }
            data[i] = sample * config.amplitude * envelope
        }
        return buffer
    }

    // MARK: - Tone configs (from soundEngine.jsx)

    struct ToneConfig {
        let frequency: Float
        let waveType: WaveType
        let duration: Float
        let delay: Float
        let amplitude: Float

        enum WaveType { case sine, sawtooth, triangle }

        init(freq: Float, wave: WaveType = .sine, dur: Float, delay: Float = 0, amp: Float = 0.18) {
            self.frequency = freq; self.waveType = wave
            self.duration = dur; self.delay = delay; self.amplitude = amp
        }
    }

    private let soundConfigs: [SoundType: [ToneConfig]] = [
        .perfect:           [ToneConfig(freq: 880,  dur: 0.18), ToneConfig(freq: 1100, dur: 0.12, delay: 0.06)],
        .great:             [ToneConfig(freq: 660,  dur: 0.15)],
        .good:              [ToneConfig(freq: 440,  dur: 0.12)],
        .miss:              [ToneConfig(freq: 180,  wave: .sawtooth, dur: 0.22)],
        .comboBreak:        [ToneConfig(freq: 220,  wave: .sawtooth, dur: 0.15), ToneConfig(freq: 150, wave: .sawtooth, dur: 0.2, delay: 0.08)],
        .comboMilestone:    [ToneConfig(freq: 660,  dur: 0.1), ToneConfig(freq: 880, dur: 0.1, delay: 0.1), ToneConfig(freq: 1100, dur: 0.15, delay: 0.2)],
        .challengeComplete: [ToneConfig(freq: 523,  dur: 0.12), ToneConfig(freq: 659, dur: 0.12, delay: 0.12), ToneConfig(freq: 784, dur: 0.12, delay: 0.24), ToneConfig(freq: 1047, dur: 0.3, delay: 0.36)],
        .dailyReward:       [ToneConfig(freq: 440,  dur: 0.1), ToneConfig(freq: 550, dur: 0.1, delay: 0.1), ToneConfig(freq: 660, dur: 0.1, delay: 0.2), ToneConfig(freq: 880, dur: 0.25, delay: 0.3)],
        .countdown:         [ToneConfig(freq: 330,  dur: 0.1)],
        .countdownGo:       [ToneConfig(freq: 880,  dur: 0.2)],
    ]

    // MARK: - Play SFX (main thread only reads a flag and enqueues)

    func play(_ type: SoundType) {
        guard isSoundEnabled else { return }
        let requestedAt = CACurrentMediaTime()
        audioQueue.async { [self] in
            guard let tones = bufferCache[type] else { return }  // still synthesising (first ~ms after launch)
            ensureRunning()
            for tone in tones {
                playOnPool(buffer: tone.buffer, at: requestedAt, delay: tone.delaySeconds)
            }
        }
    }

    /// audioQueue only.
    private func playOnPool(buffer: AVAudioPCMBuffer, at requestedAt: CFTimeInterval, delay: Double) {
        let index = nextPlayerIndex % poolSize
        let player = playerPool[index]
        nextPlayerIndex += 1
        // Bookkeeping for themed-pack voice allocation only: the node the
        // built-in tones use is unchanged (plain round-robin).
        markVoice(index, buffer: buffer, startingAt: requestedAt + delay, priority: false)

        // Stop any currently playing sound on this node
        player.stop()

        if delay > 0 {
            let scheduledTime = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: requestedAt + delay))
            player.scheduleBuffer(buffer, at: scheduledTime)
        } else {
            player.scheduleBuffer(buffer)
        }
        player.play()
    }

    /// audioQueue only.
    private func markVoice(_ index: Int, buffer: AVAudioPCMBuffer, startingAt start: CFTimeInterval, priority: Bool) {
        guard index < voiceEnds.count else { return }
        voiceEnds[index] = start + Double(buffer.frameLength) / buffer.format.sampleRate
        voiceIsPriority[index] = priority
    }

    // MARK: - Cosmetic sound packs
    //
    // Policy (which sound for which outcome) is the pure `CosmeticAudioPolicy`;
    // this section only schedules. Main-thread cost of every entry point is one
    // policy switch + one `audioQueue.async`.

    /// Called from the tap path after scoring. Only enqueues work.
    func playTapOutcome(_ outcome: TapSoundOutcome) {
        guard isSoundEnabled else { return }
        Perf.measure("audio.tapOutcome.main") {
            let packID = activeSoundPackID
            switch CosmeticAudioPolicy.cue(for: outcome, packID: packID) {
            case .tone(let type):
                play(type)   // default pack: the exact pre-Studio path
            case .pack(let event):
                enqueuePackEvent(event, packID: packID, fallback: CosmeticAudioPolicy.defaultTone(for: outcome))
            case .silent:
                break
            }
        }
    }

    /// Round ended (Game Over screen about to show). Default pack: silent.
    /// The active pack plays a sting at round end (themed packs; classic is silent).
    var activePackHasGameOverSound: Bool {
        CosmeticAudioPolicy.gameOverCue(packID: activeSoundPackID) != .silent
    }

    func playGameOverCosmetic() {
        guard isSoundEnabled else { return }
        let packID = activeSoundPackID
        guard case .pack(let event) = CosmeticAudioPolicy.gameOverCue(packID: packID) else { return }
        // No fallback: the classic game over has always been silent.
        enqueuePackEvent(event, packID: packID, fallback: nil)
    }

    /// Select and preload the pack used in gameplay. Call before a round starts
    /// (never on the tap path). Decoding runs on `synthQueue`; until it is done
    /// taps fall back to the default tones, so this never blocks or goes silent.
    /// Unknown ids resolve to the default pack. Also stops any preview.
    func setActiveSoundPack(_ packID: String) {
        let id = SoundPackCatalog.resolvedPackID(packID)
        stopPreview()
        activeSoundPackID = id
        audioQueue.async { [self] in
            if queueActivePackID != id { variantCursor = [:] }
            queueActivePackID = id
            evictUnusedPacks()
            loadPackIfNeeded(id, completion: nil)
        }
    }

    /// Preview Studio: play one event of any pack (owned or not) on the
    /// dedicated preview node. Loads the pack off-main if needed. Never changes
    /// the active gameplay pack. Respects the master sound setting.
    func previewSound(_ event: CosmeticEvent, packID: String) {
        guard isSoundEnabled else { return }
        let id = SoundPackCatalog.resolvedPackID(packID)
        audioQueue.async { [self] in
            let generation = previewGeneration
            guard let pack = SoundPackCatalog.pack(id: id) else { return }
            if pack.isBuiltIn {
                guard let tone = CosmeticAudioPolicy.defaultPreviewTone(for: event),
                      let buffer = defaultPreviewBuffers[tone] else { return }
                playPreviewBuffer(buffer)
                return
            }
            if queuePreviewPackID != id {
                queuePreviewPackID = id
                evictUnusedPacks()
            }
            loadPackIfNeeded(id) { [self] buffers in
                // Dropped if the user stopped previews / left while it loaded.
                guard generation == previewGeneration, let buffer = buffers?[event]?.first else { return }
                playPreviewBuffer(buffer)
            }
        }
    }

    /// Stops the preview voice (leaving the Studio / starting a round). Uses
    /// its own node, so gameplay voices are never cut.
    func stopPreview() {
        audioQueue.async { [self] in
            previewGeneration &+= 1
            previewPlayer.stop()
        }
    }

    /// Calls `completion` on the main queue once `packID`'s buffers are cached
    /// (true) — or immediately with false if it is neither cached nor loading.
    /// For the Studio's loading state and tests; gameplay never needs to wait.
    func whenSoundPackReady(_ packID: String, _ completion: @escaping (Bool) -> Void) {
        let id = SoundPackCatalog.resolvedPackID(packID)
        audioQueue.async { [self] in
            let reply: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }
            if SoundPackCatalog.pack(id: id)?.isBuiltIn == true || packCache[id] != nil {
                reply(true)
            } else if packsLoading.contains(id) {
                packLoadWaiters[id, default: []].append { reply($0 != nil) }
            } else {
                reply(false)
            }
        }
    }

    /// Tests / diagnostics only (blocks the caller on audioQueue — never call
    /// from gameplay code).
    func cachedSoundPackBuffers(_ packID: String) -> SoundPackBuffers? {
        audioQueue.sync { packCache[packID] }
    }

    /// Tests / diagnostics only: ids currently held in the pack cache.
    func cachedSoundPackIDs() -> Set<String> {
        audioQueue.sync { Set(packCache.keys) }
    }

    /// The engine's player format; pack buffers are decoded into it.
    var playerFormat: AVAudioFormat { format }

    private func enqueuePackEvent(_ event: CosmeticEvent, packID: String, fallback: SoundType?) {
        let requestedAt = CACurrentMediaTime()
        audioQueue.async { [self] in
            if let buffers = packCache[packID]?[event], !buffers.isEmpty {
                // Round-robin variants. All start at sample 0, so the choice
                // never moves the onset.
                let cursor = variantCursor[event, default: 0]
                variantCursor[event] = cursor &+ 1
                ensureRunning()
                playPackVoice(buffers[cursor % buffers.count],
                              priority: CosmeticAudioPolicy.isHighPriority(event))
            } else if let fallback, let tones = bufferCache[fallback] {
                // Pack still decoding (or a file failed): the default tone, never silence.
                ensureRunning()
                for tone in tones {
                    playOnPool(buffer: tone.buffer, at: requestedAt, delay: tone.delaySeconds)
                }
            }
        }
    }

    /// audioQueue only. Round-robin like `playOnPool`, but skips nodes that are
    /// still ringing a high-priority sound (perfect / miss / life lost / game
    /// over), so a burst of quick taps cannot cut them. If all 8 nodes are busy
    /// with priority sounds (not reachable with ≤ 900 ms sounds at human tap
    /// rates) the round-robin node is reused: voices stay bounded.
    private func playPackVoice(_ buffer: AVAudioPCMBuffer, priority: Bool) {
        let now = CACurrentMediaTime()
        var index = nextPlayerIndex % poolSize
        for offset in 0..<poolSize {
            let candidate = (nextPlayerIndex + offset) % poolSize
            if !(voiceIsPriority[candidate] && voiceEnds[candidate] > now) {
                index = candidate
                break
            }
        }
        nextPlayerIndex = index + 1
        markVoice(index, buffer: buffer, startingAt: now, priority: priority)
        let player = playerPool[index]
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }

    /// audioQueue only.
    private func playPreviewBuffer(_ buffer: AVAudioPCMBuffer) {
        ensureRunning()
        previewPlayer.stop()
        previewPlayer.scheduleBuffer(buffer)
        previewPlayer.play()
    }

    /// audioQueue only. Keeps at most the active pack and the last previewed
    /// pack in memory (each ≈ 0.6 MB of float PCM).
    private func evictUnusedPacks() {
        packCache = packCache.filter { $0.key == queueActivePackID || $0.key == queuePreviewPackID }
    }

    /// audioQueue only. Decodes on `synthQueue`, stores back on `audioQueue`.
    /// `completion` runs on audioQueue with the buffers (nil if the pack is
    /// built-in or was deselected while loading).
    private func loadPackIfNeeded(_ id: String, completion: ((SoundPackBuffers?) -> Void)?) {
        guard let pack = SoundPackCatalog.pack(id: id), !pack.isBuiltIn else {
            completion?(nil)
            return
        }
        if let cached = packCache[id] {
            completion?(cached)
            return
        }
        if let completion { packLoadWaiters[id, default: []].append(completion) }
        guard packsLoading.insert(id).inserted else { return }
        let format = self.format
        synthQueue.async { [self] in
            let buffers = Perf.measure("audio.packPreload.offMain") {
                SoundPackLoader.decode(pack, format: format)
            }
            audioQueue.async { [self] in
                packsLoading.remove(id)
                let wanted = id == queueActivePackID || id == queuePreviewPackID
                if wanted { packCache[id] = buffers }
                for waiter in packLoadWaiters.removeValue(forKey: id) ?? [] {
                    waiter(wanted ? buffers : nil)
                }
            }
        }
    }

    // MARK: - Background music (90 BPM ambient synth, looping)

    private static let beatDur: Double = 60.0 / 90.0

    func startBgMusic() {
        guard isMusicEnabled else { return }
        guard !musicActive else { return }
        musicActive = true
        Perf.measure("audio.musicStart.main") {
            audioQueue.async { [self] in
                musicWanted = true
                startMusicLocked()
            }
        }
    }

    func stopBgMusic() {
        guard musicActive else { return }
        musicActive = false
        Perf.measure("audio.stopMusic") {
            audioQueue.async { [self] in
                musicWanted = false
                musicPlayer.stop()
            }
        }
    }

    /// audioQueue only. No-op until the loop buffer has been rendered.
    private func startMusicLocked() {
        guard musicWanted, let loop = musicLoopBuffer, !musicPlayer.isPlaying else { return }
        ensureRunning()
        musicPlayer.scheduleBuffer(loop, at: nil, options: .loops)
        musicPlayer.play()
    }

    /// Renders the same notes the old per-loop scheduler played (bass + melody,
    /// 16 beats at 90 BPM) into one buffer that loops seamlessly.
    private func makeMusicLoopBuffer() -> AVAudioPCMBuffer? {
        let beat = Self.beatDur
        let sampleRate: Double = 44100
        let bassNotes: [(Double, Double)] = [
            (55, 0), (55, beat*2), (65, beat*4), (55, beat*6),
            (55, beat*8), (65, beat*10), (73, beat*12), (65, beat*14)
        ]
        let melodyFreqs: [Double] = [220, 0, 261, 0, 220, 246, 0, 220, 0, 261, 293, 0, 261, 246, 0, 0]
        let melodyNotes = melodyFreqs.enumerated().compactMap { i, f in f > 0 ? (f, Double(i) * beat) : nil }

        let frames = AVAudioFrameCount(16 * beat * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { data[i] = 0 }

        func add(freq: Double, start: Double, duration: Double, amp: Float) {
            let first = Int(start * sampleRate)
            let count = Int(duration * sampleRate)
            for n in 0..<count {
                let idx = (first + n) % Int(frames)   // wrap any tail into the loop start
                let t = Float(n) / Float(sampleRate)
                let env = max(0, 1.0 - t / Float(duration))
                data[idx] += sin(Float.pi * 2 * Float(freq) * t) * amp * env
            }
        }
        for (f, d) in bassNotes { add(freq: f, start: d, duration: beat * 1.8, amp: 0.05) }
        for (f, d) in melodyNotes { add(freq: f, start: d, duration: beat * 0.8, amp: 0.035) }
        return buffer
    }
}
