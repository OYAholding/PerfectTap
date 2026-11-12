import SwiftUI

// MARK: - Game Constants (ported from Game.jsx + soundEngine.jsx)

enum GameConfig {

    // MARK: Accuracy zones (distance from center as fraction 0.0–0.5)
    static let perfectZone: Double = 0.04   // ±4%
    static let greatZone: Double   = 0.10   // ±10%
    static let goodZone: Double    = 0.20   // ±20%

    // MARK: Points per accuracy
    static let perfectPoints: Int = 100
    static let greatPoints: Int   = 70
    static let goodPoints: Int    = 40
    static let missPoints: Int    = 0

    // MARK: Combo multipliers (classic / most modes)
    static func comboMultiplier(combo: Int, isComboFrenzy: Bool) -> Double {
        if isComboFrenzy {
            if combo >= 20 { return 6 }
            if combo >= 15 { return 5 }
            if combo >= 10 { return 4 }
            if combo >= 5  { return 3 }
            if combo >= 3  { return 2 }
            return 1
        }
        if combo >= 5 { return 2 }
        if combo >= 3 { return 1.5 }
        return 1
    }

    // MARK: Initial speeds per mode (lower = faster)
    static let classicStartSpeed: Double     = 1.2
    static let endlessStartSpeed: Double     = 1.2
    static let timedStartSpeed: Double       = 1.0   // fixed speed
    static let suddenDeathStartSpeed: Double = 0.9
    static let zenSpeed: Double              = 1.6   // fixed, slow

    // MARK: Speed increase per taps (classic & sudden death)
    static let classicSpeedStep: Double      = 0.10   // every 4 taps (was 0.08/5)
    static let classicSpeedEvery: Int        = 4
    static let suddenSpeedStep: Double       = 0.12   // every 2 taps (was 0.10/3)
    static let suddenSpeedEvery: Int         = 2
    static let minSpeed: Double              = 0.15   // floor

    // MARK: Endless: time-based speed (newSpeed = max(0.2, 1.2 - elapsed * 0.005))
    static let endlessMinSpeed: Double       = 0.2

    // MARK: Lives per mode
    static let classicLives: Int     = 3
    static let timedLives: Int       = 3
    static let endlessLives: Int     = 3
    static let comboFrenzyLives: Int = 3
    static let suddenDeathLives: Int = 1
    // Zen: no lives

    // MARK: Timed mode duration
    static let timedDuration: Double = 60.0   // seconds
    static let reviveBonusSeconds: Double = 15.0

    // MARK: XP formula (from xpSystem.jsx)
    static func calcGameXP(score: Int, maxCombo: Int, mode: GameMode) -> Int {
        let base = score / 20
        let comboBonus = maxCombo / 2
        let modeBonus: Int
        switch mode {
        case .suddenDeath:  modeBonus = 15
        case .comboFrenzy:  modeBonus = 10
        case .duel:         modeBonus = 20
        default:            modeBonus = 5
        }
        return max(5, base + comboBonus + modeBonus)
    }

    static func xpForLevel(_ level: Int) -> Int {
        Int(100.0 * pow(1.15, Double(level - 1)))
    }

    // MARK: Season XP (from seasonSystem)
    static func calcSeasonXP(score: Int, maxCombo: Int, mode: GameMode) -> Int {
        let base = score / 25
        let comboBonus = maxCombo / 3
        let modeBonus: Int
        switch mode {
        case .duel:         modeBonus = 20
        case .suddenDeath:  modeBonus = 15
        case .comboFrenzy:  modeBonus = 10
        default:            modeBonus = 5
        }
        return max(3, base + comboBonus + modeBonus)
    }

    static let seasonXPPerTier: Int = 200
    static let seasonMaxTiers: Int  = 30

    // MARK: Coins — Classic & Duel earn coins
    static func calcGameCoins(score: Int, maxCombo: Int, mode: GameMode) -> Int {
        // Only Classic and Duel modes earn coins
        guard mode.earnCoins else { return 0 }
        let base = score / 50
        let comboBonus = maxCombo >= 20 ? 8 : maxCombo >= 10 ? 5 : maxCombo >= 5 ? 3 : 1
        let modeBonus: Int = mode == .duel ? 6 : 2
        return max(3, base + comboBonus + modeBonus)
    }

    // MARK: Score validation bounds (from submitScore.ts — prevent cheating)
    static func maxScoreForMode(_ mode: GameMode) -> Int {
        switch mode {
        case .classic:       return 50_000
        case .endless:       return 200_000
        case .timed:         return 20_000
        case .suddenDeath:   return 10_000
        case .comboFrenzy:   return 100_000
        case .duel:          return 50_000
        case .zen:           return 0
        case .precision:     return 30_000
        case .chaos:         return 80_000
        case .mirror:        return 40_000
        case .invisibleZone: return 30_000
        case .rush:          return 15_000
        case .hardcoreCombo: return 80_000
        case .tinyWindow:    return 25_000
        case .focus:         return 0
        }
    }

    // MARK: Rush mode duration
    static let rushDuration: Double = 30.0

    // MARK: Dynamic difficulty per mode

    // Timed: speed ramps as time runs out
    static let timedSpeedFloor: Double = 0.45
    static let timedSpeedRange: Double = 0.55  // how much faster it gets over full duration

    // Combo Frenzy: speed tied to combo
    static let comboFrenzySpeedPerCombo: Double = 0.03
    static let comboFrenzySpeedFloor: Double = 0.4

    // Precision: zone shrinks every N taps
    static let precisionShrinkEvery: Int = 5
    static let precisionShrinkStep: Double = 0.05
    static let precisionShrinkFloor: Double = 0.5
    static let precisionSpeedStep: Double = 0.06
    static let precisionSpeedEvery: Int = 8
    static let precisionSpeedFloor: Double = 0.5

    // Mirror: flip frequency + speed ramp over time
    static let mirrorBaseFlipChance: Double = 0.008
    static let mirrorFlipGrowth: Double = 0.001   // per second
    static let mirrorFlipCap: Double = 0.04
    static let mirrorSpeedRamp: Double = 0.003     // per second
    static let mirrorSpeedFloor: Double = 0.5

    // Invisible Zone: classic-like speed ramp
    static let invisibleSpeedStep: Double = 0.08
    static let invisibleSpeedEvery: Int = 4
    static let invisibleSpeedFloor: Double = 0.4

    // Rush: final sprint in last 10s
    static let rushSprintSeconds: Double = 10.0
    static let rushSprintAccel: Double = 0.025     // per second in last 10s
    static let rushSprintFloor: Double = 0.3

    // Hardcore Combo: speed from combo + base decay
    static let hardcoreSpeedPerCombo: Double = 0.025
    static let hardcoreSpeedFloor: Double = 0.45
    static let hardcoreBaseDecayStep: Double = 0.05
    static let hardcoreBaseDecayEvery: Int = 6
    static let hardcoreBreakThresholdCombo: Int = 5
    static let hardcoreBreakShockStep: Double = 0.15
    static let hardcoreBreakShockDecay: Double = 0.03
    static let hardcorePenaltyTaps: Int = 4
    static let hardcorePenaltyPerfectScale: Double = 0.70

    // Tiny Window: zone keeps shrinking + speed ramp
    static let tinyWindowShrinkEvery: Int = 6
    static let tinyWindowShrinkStep: Double = 0.03
    static let tinyWindowShrinkFloor: Double = 0.25
    static let tinyWindowSpeedStep: Double = 0.06
    static let tinyWindowSpeedEvery: Int = 5
    static let tinyWindowSpeedFloor: Double = 0.5

    // Focus: oscillating speed
    static let focusOscillationFreq: Double = 0.8
    static let focusOscillationAmp: Double = 0.3
    static let focusBaseDecay: Double = 0.002      // per second
    static let focusBaseFloor: Double = 0.5
}

// MARK: - Themes
struct AppTheme {
    let name: String
    let barGradient: (Color, Color)
    let indicatorColor: Color
    let targetColor: Color
    let glowColor: Color
    let backgroundColor: Color
    let accentColor: Color
}

extension AppTheme {
    static let `default` = AppTheme(name: "default",
        barGradient: (.purple, .cyan),
        indicatorColor: .white,
        targetColor: Color(red: 0.655, green: 0.545, blue: 0.980),
        glowColor: Color(red: 0.545, green: 0.361, blue: 0.961),
        backgroundColor: Color(red: 0.039, green: 0.039, blue: 0.059),
        accentColor: Color(red: 0.655, green: 0.545, blue: 0.980))

    static let neon = AppTheme(name: "neon",
        barGradient: (Color(red: 0.165, green: 0.886, blue: 0.341), Color(red: 0.498, green: 0.902, blue: 0.188)),
        indicatorColor: .white, targetColor: Color(red: 0.290, green: 0.855, blue: 0.502),
        glowColor: Color(red: 0.133, green: 0.773, blue: 0.369),
        backgroundColor: Color(red: 0.020, green: 0.055, blue: 0.025),
        accentColor: Color(red: 0.290, green: 0.855, blue: 0.502))

    static let fire = AppTheme(name: "fire",
        barGradient: (Color(red: 0.984, green: 0.396, blue: 0.0), Color(red: 0.937, green: 0.267, blue: 0.267)),
        indicatorColor: .white, targetColor: Color(red: 0.984, green: 0.573, blue: 0.188),
        glowColor: Color(red: 0.937, green: 0.267, blue: 0.267),
        backgroundColor: Color(red: 0.065, green: 0.025, blue: 0.020),
        accentColor: Color(red: 0.984, green: 0.573, blue: 0.188))

    static let ice = AppTheme(name: "ice",
        barGradient: (Color(red: 0.235, green: 0.745, blue: 0.973), Color(red: 0.188, green: 0.710, blue: 0.965)),
        indicatorColor: .white, targetColor: Color(red: 0.220, green: 0.745, blue: 0.973),
        glowColor: Color(red: 0.235, green: 0.745, blue: 0.973),
        backgroundColor: Color(red: 0.020, green: 0.035, blue: 0.065),
        accentColor: Color(red: 0.235, green: 0.745, blue: 0.973))

    static let gold = AppTheme(name: "gold",
        barGradient: (Color(red: 0.980, green: 0.749, blue: 0.141), Color(red: 0.984, green: 0.624, blue: 0.141)),
        indicatorColor: .white, targetColor: Color(red: 0.984, green: 0.749, blue: 0.141),
        glowColor: Color(red: 0.984, green: 0.749, blue: 0.141),
        backgroundColor: Color(red: 0.055, green: 0.045, blue: 0.015),
        accentColor: Color(red: 0.984, green: 0.749, blue: 0.141))

    static let galaxy = AppTheme(name: "galaxy",
        barGradient: (Color(red: 0.592, green: 0.125, blue: 0.941), Color(red: 0.941, green: 0.259, blue: 0.714)),
        indicatorColor: .white, targetColor: Color(red: 0.753, green: 0.251, blue: 0.957),
        glowColor: Color(red: 0.592, green: 0.125, blue: 0.941),
        backgroundColor: Color(red: 0.045, green: 0.020, blue: 0.065),
        accentColor: Color(red: 0.753, green: 0.251, blue: 0.957))

    static let midnight = AppTheme(name: "midnight",
        barGradient: (Color(red: 0.102, green: 0.110, blue: 0.282), Color(red: 0.259, green: 0.216, blue: 0.529)),
        indicatorColor: .white, targetColor: Color(red: 0.310, green: 0.267, blue: 0.596),
        glowColor: Color(red: 0.200, green: 0.180, blue: 0.470),
        backgroundColor: Color(red: 0.020, green: 0.022, blue: 0.055),
        accentColor: Color(red: 0.310, green: 0.267, blue: 0.596))

    static let sunset = AppTheme(name: "sunset",
        barGradient: (Color(red: 0.984, green: 0.420, blue: 0.200), Color(red: 0.949, green: 0.200, blue: 0.400)),
        indicatorColor: .white, targetColor: Color(red: 0.984, green: 0.506, blue: 0.349),
        glowColor: Color(red: 0.949, green: 0.263, blue: 0.373),
        backgroundColor: Color(red: 0.060, green: 0.025, blue: 0.030),
        accentColor: Color(red: 0.984, green: 0.506, blue: 0.349))

    static let matrix = AppTheme(name: "matrix",
        barGradient: (Color(red: 0.0, green: 0.898, blue: 0.102), Color(red: 0.0, green: 0.600, blue: 0.102)),
        indicatorColor: .white, targetColor: Color(red: 0.0, green: 0.800, blue: 0.102),
        glowColor: Color(red: 0.0, green: 0.702, blue: 0.102),
        backgroundColor: Color(red: 0.010, green: 0.035, blue: 0.010),
        accentColor: Color(red: 0.0, green: 0.800, blue: 0.102))

    static let all: [AppTheme] = [.default, .neon, .fire, .ice, .gold, .galaxy, .midnight, .sunset, .matrix]

    static func named(_ name: String) -> AppTheme {
        all.first { $0.name == name } ?? .default
    }
}
