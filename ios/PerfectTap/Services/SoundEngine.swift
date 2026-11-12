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
// Uses a fixed pool of AVAudioPlayerNodes to avoid creating/destroying
// nodes every tap (which caused lag and audio graph bloat).
final class SoundEngine {

    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    // Cached settings — avoids UserDefaults I/O on every play() call
    private var isSoundEnabled: Bool
    private var isMusicEnabled: Bool

    // Fixed node pool — reuse instead of create/destroy
    private let poolSize = 8
    private var playerPool: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0

    // Background music
    private var musicTimer: Timer?
    /// Set synchronously by start/stop. Buffers are synthesized asynchronously,
    /// so `musicTimer` alone can't tell whether music is (about to be) playing —
    /// that let two quick starts double the loop and let stop be ignored.
    private var musicActive = false
    private var musicSession = 0
    private let musicPoolSize = 24
    private var musicPool: [AVAudioPlayerNode] = []
    private var nextMusicIndex = 0

    // Buffer cache — pre-generate common sounds to avoid main-thread synthesis
    private var bufferCache: [SoundType: [ScheduledTone]] = [:]
    private var pendingWarmups: Set<SoundType> = []

    // Audio synthesis queue (off main thread)
    private let synthQueue = DispatchQueue(label: "com.perfecttap.audio.synth", qos: .userInteractive)

    private init() {
        // Cache settings from UserDefaults once
        isSoundEnabled = UserDefaults.standard.object(forKey: "perfecttap_sound") as? Bool ?? true
        isMusicEnabled = UserDefaults.standard.object(forKey: "perfecttap_music") as? Bool ?? true

        // 44100 Hz mono PCM float — guaranteed to succeed for standard parameters
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            fatalError("SoundEngine: Failed to create AVAudioFormat — this should never happen with standard parameters")
        }
        format = fmt
        setupAudioSession()
        setupNodePool()
        setupMusicPool()
        precacheBuffers()
        observeInterruptions()
    }

    /// Call when user changes sound/music settings
    func refreshSettings() {
        isSoundEnabled = UserDefaults.standard.object(forKey: "perfecttap_sound") as? Bool ?? true
        isMusicEnabled = UserDefaults.standard.object(forKey: "perfecttap_music") as? Bool ?? true
    }

    // MARK: - Setup

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupNodePool() {
        for _ in 0..<poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playerPool.append(player)
        }
        try? engine.start()
    }

    private func setupMusicPool() {
        for _ in 0..<musicPoolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            musicPool.append(player)
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let info = note.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? self?.engine.start()
            }
        }
    }

    // MARK: - Pre-cached buffer generation

    private struct ScheduledTone {
        let buffer: AVAudioPCMBuffer
        let delaySeconds: Double
    }

    private func precacheBuffers() {
        synthQueue.async { [self] in
            for (type, configs) in soundConfigs {
                let tones = configs.compactMap { config -> ScheduledTone? in
                    guard let buffer = generateBuffer(config: config) else { return nil }
                    return ScheduledTone(buffer: buffer, delaySeconds: Double(config.delay))
                }
                DispatchQueue.main.async {
                    self.bufferCache[type] = tones
                }
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

    // MARK: - Play SFX (fast, main-thread safe — uses pre-cached buffers + node pool)

    func play(_ type: SoundType) {
        guard isSoundEnabled else { return }

        // Use cached buffers (already generated off-thread)
        guard let tones = bufferCache[type] else {
            warmBufferIfNeeded(for: type)
            return
        }

        for tone in tones {
            playOnPool(buffer: tone.buffer, delay: tone.delaySeconds)
        }
    }

    private func warmBufferIfNeeded(for type: SoundType) {
        guard !pendingWarmups.contains(type) else { return }
        pendingWarmups.insert(type)

        synthQueue.async { [self] in
            guard let configs = soundConfigs[type] else {
                DispatchQueue.main.async {
                    self.pendingWarmups.remove(type)
                }
                return
            }

            let tones = configs.compactMap { config -> ScheduledTone? in
                guard let buffer = generateBuffer(config: config) else { return nil }
                return ScheduledTone(buffer: buffer, delaySeconds: Double(config.delay))
            }

            DispatchQueue.main.async {
                if !tones.isEmpty {
                    self.bufferCache[type] = tones
                }
                self.pendingWarmups.remove(type)
            }
        }
    }

    private func playOnPool(buffer: AVAudioPCMBuffer, delay: Double) {
        if !engine.isRunning { try? engine.start() }

        let player = playerPool[nextPlayerIndex % poolSize]
        nextPlayerIndex += 1

        // Stop any currently playing sound on this node
        player.stop()

        if delay > 0 {
            let scheduledTime = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: CACurrentMediaTime() + delay))
            player.scheduleBuffer(buffer, at: scheduledTime)
        } else {
            player.scheduleBuffer(buffer)
        }
        player.play()
    }

    // MARK: - Background music (90 BPM ambient synth, looping)

    func startBgMusic() {
        guard isMusicEnabled else { return }
        guard !musicActive else { return }
        musicActive = true
        musicSession += 1
        scheduleMusicLoop(session: musicSession)
    }

    private func scheduleMusicLoop(session: Int) {
        let beatDur: Double = 60.0 / 90.0

        // Bass notes (Hz) — same as web version
        let bassNotes: [(Double, Double)] = [
            (55, 0), (55, beatDur*2), (65, beatDur*4), (55, beatDur*6),
            (55, beatDur*8), (65, beatDur*10), (73, beatDur*12), (65, beatDur*14)
        ]
        // Melody — 0 = rest
        let melodyNotes: [(Double, Double)] = {
            let freqs: [Double] = [220, 0, 261, 0, 220, 246, 0, 220, 0, 261, 293, 0, 261, 246, 0, 0]
            return freqs.enumerated().compactMap { i, f in f > 0 ? (f, Double(i) * beatDur) : nil }
        }()

        let totalDur = 16 * beatDur

        // Generate music buffers off main thread, then schedule
        synthQueue.async { [self] in
            var musicTones: [(AVAudioPCMBuffer, Double)] = []

            for (freq, delay) in bassNotes {
                guard let buf = generateMusicBuffer(freq: freq, duration: beatDur * 1.8, amp: 0.05) else { continue }
                musicTones.append((buf, delay))
            }
            for (freq, delay) in melodyNotes {
                guard let buf = generateMusicBuffer(freq: freq, duration: beatDur * 0.8, amp: 0.035) else { continue }
                musicTones.append((buf, delay))
            }

            DispatchQueue.main.async { [self] in
                guard musicActive, session == musicSession, isMusicEnabled else { return }
                if !engine.isRunning { try? engine.start() }

                for (buffer, delay) in musicTones {
                    let player = musicPool[nextMusicIndex % musicPoolSize]
                    nextMusicIndex += 1
                    player.stop()
                    let scheduledTime = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: CACurrentMediaTime() + delay))
                    player.scheduleBuffer(buffer, at: scheduledTime)
                    player.play()
                }

                // Schedule next loop
                musicTimer = Timer.scheduledTimer(withTimeInterval: totalDur - 0.08, repeats: false) { [weak self] _ in
                    self?.musicTimer = nil
                    self?.scheduleMusicLoop(session: session)
                }
            }
        }
    }

    private func generateMusicBuffer(freq: Double, duration: Double, amp: Float) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Float(i) / Float(sampleRate)
            let env = max(0, 1.0 - t / Float(duration))
            data[i] = sin(Float.pi * 2 * Float(freq) * t) * amp * env
        }
        return buffer
    }

    func stopBgMusic() {
        musicActive = false
        musicSession += 1
        musicTimer?.invalidate()
        musicTimer = nil
        // Stop all music nodes immediately
        for player in musicPool {
            player.stop()
        }
        nextMusicIndex = 0
    }
}
