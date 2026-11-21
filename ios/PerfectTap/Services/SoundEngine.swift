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
        engine.attach(musicPlayer)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
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
            audioQueue.async { self.bufferCache = cache }

            let loop = makeMusicLoopBuffer()
            audioQueue.async {
                self.musicLoopBuffer = loop
                if self.musicWanted { self.startMusicLocked() }
            }
        }
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
        let player = playerPool[nextPlayerIndex % poolSize]
        nextPlayerIndex += 1

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
