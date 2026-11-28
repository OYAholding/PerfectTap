import SwiftUI

// MARK: - Visual effects level
//
// One global setting that governs particles, glows, popup motion and the
// effects of premium cosmetics. iOS "Reduce Motion" caps it at `.reduced`.
// Changing it never changes scoring or zone visibility: zones, centre line and
// indicator are drawn identically at every level.

enum EffectsLevel: String, CaseIterable, Identifiable {
    case full, reduced, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full:    return "Full"
        case .reduced: return "Reduced"
        case .off:     return "Off"
        }
    }

    static let storageKey = "pt_effects_level"

    static var stored: EffectsLevel {
        EffectsLevel(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .full
    }

    /// The level actually applied: Reduce Motion lowers Full to Reduced.
    func effective(reduceMotion: Bool) -> EffectsLevel {
        (reduceMotion && self == .full) ? .reduced : self
    }

    var showsParticles: Bool { self == .full }
    var showsGlow: Bool { self != .off }
    var animatesFeedback: Bool { self == .full }
    /// Fraction of the cosmetic glow/shadow strength to draw.
    var glowStrength: Double {
        switch self {
        case .full:    return 1
        case .reduced: return 0.5
        case .off:     return 0
        }
    }
}

private struct EffectsLevelKey: EnvironmentKey {
    static let defaultValue: EffectsLevel = .full
}

extension EnvironmentValues {
    /// Effective level (setting + Reduce Motion), injected at the app root.
    var effectsLevel: EffectsLevel {
        get { self[EffectsLevelKey.self] }
        set { self[EffectsLevelKey.self] = newValue }
    }
}

/// Reads the stored setting and Reduce Motion, and publishes the effective
/// level into the environment.
struct EffectsLevelProvider: ViewModifier {
    @AppStorage(EffectsLevel.storageKey) private var stored: String = EffectsLevel.full.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let level = (EffectsLevel(rawValue: stored) ?? .full).effective(reduceMotion: reduceMotion)
        content.environment(\.effectsLevel, level)
    }
}

extension View {
    func providesEffectsLevel() -> some View { modifier(EffectsLevelProvider()) }
}
