import UIKit
import CoreHaptics

// MARK: - Haptics wrapper
final class HapticsEngine {

    static let shared = HapticsEngine()

    private var isHapticsEnabled: Bool {
        _hapticsEnabled
    }
    private var _hapticsEnabled: Bool = true

    // Pre-initialized generator pool — one per style, reused across taps
    private var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private var chEngine: CHHapticEngine?

    private init() {
        _hapticsEnabled = UserDefaults.standard.object(forKey: "perfecttap_haptics") as? Bool ?? true
        Perf.measure("haptics.setup") {
            setupGenerators()
        }
    }

    private func setupGenerators() {
        let styles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.light, .medium, .heavy, .rigid, .soft]
        for style in styles {
            let gen = UIImpactFeedbackGenerator(style: style)
            gen.prepare()
            generators[style] = gen
        }
    }

    /// Started lazily: the Core Haptics engine used to be created and kept
    /// running from the first game although nothing played a pattern.
    private func prepareHapticsIfNeeded() {
        guard chEngine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        chEngine = try? CHHapticEngine()
        try? chEngine?.start()
        chEngine?.resetHandler = { [weak self] in
            try? self?.chEngine?.start()
        }
        chEngine?.stoppedHandler = { _ in }
    }

    /// Call when user changes haptics setting
    /// Touch at app launch so generator setup happens before the first game.
    func warmUp() {}

    func refreshSettings() {
        _hapticsEnabled = UserDefaults.standard.object(forKey: "perfecttap_haptics") as? Bool ?? true
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isHapticsEnabled else { return }
        if let gen = generators[style] {
            gen.impactOccurred()
            gen.prepare()  // prepare for next use
        }
    }

    // Custom haptic for PERFECT hit — stronger, distinctive feel
    func perfectHit() {
        guard isHapticsEnabled else { return }
        prepareHapticsIfNeeded()
        guard let engine = chEngine,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            impact(.medium)
            return
        }
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []) {
            let player = try? engine.makePlayer(with: pattern)
            try? player?.start(atTime: 0)
        }
    }
}
