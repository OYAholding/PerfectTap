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

    // MARK: - Cosmetic haptic styles (Studio)

    /// Main-thread state, read on every tap.
    private(set) var activeHapticStyleID: String = CosmeticHapticPolicy.defaultStyleID

    /// Select the haptic style used in gameplay ("default", "bouncy", "soft",
    /// "punchy"). Unknown ids resolve to the default style. No preloading
    /// needed: every style reuses the pre-warmed generators.
    func setActiveHapticStyle(_ id: String) {
        activeHapticStyleID = CosmeticHapticPolicy.resolvedStyleID(id)
    }

    /// Called from the tap path after scoring (main thread). Default style is
    /// exactly the pre-Studio dispatch (`impact(_:)` with no intensity).
    func playTapOutcome(_ outcome: TapSoundOutcome) {
        guard isHapticsEnabled else { return }
        for pulse in CosmeticHapticPolicy.pulses(for: outcome, styleID: activeHapticStyleID) {
            if pulse.delay <= 0 {
                fire(pulse)
            } else {
                // Second beat of a two-beat style. Re-checks the setting at fire time.
                DispatchQueue.main.asyncAfter(deadline: .now() + pulse.delay) { [weak self] in
                    guard let self, self.isHapticsEnabled else { return }
                    self.fire(pulse)
                }
            }
        }
    }

    private func fire(_ pulse: HapticPulse) {
        guard let gen = generators[pulse.style] else { return }
        if let intensity = pulse.intensity {
            gen.impactOccurred(intensity: intensity)
        } else {
            gen.impactOccurred()
        }
        gen.prepare()  // prepare for next use
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

// MARK: - Cosmetic haptic policy (pure, testable without hardware)

/// One impact. `intensity == nil` means `impactOccurred()` with the system
/// default intensity — what the pre-Studio code used everywhere.
struct HapticPulse: Equatable {
    let style: UIImpactFeedbackGenerator.FeedbackStyle
    var intensity: CGFloat? = nil
    var delay: TimeInterval = 0
}

enum CosmeticHapticPolicy {
    static let defaultStyleID = "default"
    static let styleIDs = ["default", "bouncy", "soft", "punchy"]

    static func resolvedStyleID(_ id: String) -> String {
        styleIDs.contains(id) ? id : defaultStyleID
    }

    /// Precedence mirrors the sound policy. Themed styles are subtle variations:
    /// frequent events (good / great / perfect) only ever use the light, soft or
    /// rigid generators — never medium/heavy — so none is heavier than today's
    /// PERFECT (.light) by more than a crisp .rigid tick; heavy stays reserved
    /// for combo breaks / lost lives, as today. At most two pulses, ≤ 90 ms apart.
    static func pulses(for outcome: TapSoundOutcome, styleID: String) -> [HapticPulse] {
        switch resolvedStyleID(styleID) {
        case "bouncy": return bouncy(outcome)
        case "soft":   return soft(outcome)
        case "punchy": return punchy(outcome)
        default:       return [HapticPulse(style: defaultStyle(for: outcome))]
        }
    }

    /// Exactly the pre-Studio GameViewModel mapping (PERFECT used
    /// `impact(.light)`, not `perfectHit()`).
    static func defaultStyle(for outcome: TapSoundOutcome) -> UIImpactFeedbackGenerator.FeedbackStyle {
        if outcome.comboBroken { return .heavy }
        if outcome.accuracy == .miss { return .rigid }
        if outcome.milestone { return .medium }
        return outcome.accuracy == .perfect ? .light : .soft
    }

    private enum Moment { case lostLife, comboBroken, miss, milestone, perfect, great, good }

    private static func moment(_ o: TapSoundOutcome) -> Moment {
        if o.lostLife { return .lostLife }
        if o.comboBroken { return .comboBroken }
        if o.accuracy == .miss { return .miss }
        if o.milestone { return .milestone }
        switch o.accuracy {
        case .perfect: return .perfect
        case .great:   return .great
        default:       return .good
        }
    }

    /// Quack Attack: springy — a soft rebound after the main beat on big moments.
    private static func bouncy(_ o: TapSoundOutcome) -> [HapticPulse] {
        switch moment(o) {
        case .good:        return [HapticPulse(style: .soft, intensity: 0.7)]
        case .great:       return [HapticPulse(style: .soft, intensity: 1.0)]
        case .perfect:     return [HapticPulse(style: .light, intensity: 1.0),
                                   HapticPulse(style: .soft, intensity: 0.55, delay: 0.07)]
        case .milestone:   return [HapticPulse(style: .medium, intensity: 0.7),
                                   HapticPulse(style: .light, intensity: 0.6, delay: 0.07)]
        case .miss:        return [HapticPulse(style: .rigid, intensity: 0.6)]
        case .comboBroken: return [HapticPulse(style: .medium, intensity: 1.0),
                                   HapticPulse(style: .soft, intensity: 0.5, delay: 0.08)]
        case .lostLife:    return [HapticPulse(style: .medium, intensity: 1.0),
                                   HapticPulse(style: .soft, intensity: 0.6, delay: 0.09)]
        }
    }

    /// Purrfect Tap: cushioned — soft generator, lower intensities.
    private static func soft(_ o: TapSoundOutcome) -> [HapticPulse] {
        switch moment(o) {
        case .good:        return [HapticPulse(style: .soft, intensity: 0.5)]
        case .great:       return [HapticPulse(style: .soft, intensity: 0.75)]
        case .perfect:     return [HapticPulse(style: .soft, intensity: 1.0)]
        case .milestone:   return [HapticPulse(style: .soft, intensity: 1.0),
                                   HapticPulse(style: .soft, intensity: 0.6, delay: 0.08)]
        case .miss:        return [HapticPulse(style: .soft, intensity: 0.8)]
        case .comboBroken: return [HapticPulse(style: .medium, intensity: 0.8)]
        case .lostLife:    return [HapticPulse(style: .medium, intensity: 0.9)]
        }
    }

    /// Boom Mode: crisp — rigid ticks, heavy only where today is heavy.
    private static func punchy(_ o: TapSoundOutcome) -> [HapticPulse] {
        switch moment(o) {
        case .good:        return [HapticPulse(style: .rigid, intensity: 0.45)]
        case .great:       return [HapticPulse(style: .rigid, intensity: 0.65)]
        case .perfect:     return [HapticPulse(style: .rigid, intensity: 0.9)]
        case .milestone:   return [HapticPulse(style: .rigid, intensity: 1.0),
                                   HapticPulse(style: .medium, intensity: 0.7, delay: 0.06)]
        case .miss:        return [HapticPulse(style: .medium, intensity: 0.8)]
        case .comboBroken: return [HapticPulse(style: .heavy, intensity: 1.0)]
        case .lostLife:    return [HapticPulse(style: .heavy, intensity: 0.9)]
        }
    }
}
