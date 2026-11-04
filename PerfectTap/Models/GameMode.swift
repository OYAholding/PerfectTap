import Foundation

enum GameMode: String, CaseIterable, Codable, Hashable {
    case classic      = "classic"
    case endless      = "endless"
    case timed        = "timed"
    case suddenDeath  = "sudden_death"
    case comboFrenzy  = "combo_frenzy"
    case zen          = "zen"
    case duel         = "duel"
    // New modes
    case precision    = "precision"
    case chaos        = "chaos"
    case mirror       = "mirror"
    case invisibleZone = "invisible_zone"
    case rush         = "rush"
    case hardcoreCombo = "hardcore_combo"
    case tinyWindow   = "tiny_window"
    case focus        = "focus"

    var displayName: String {
        switch self {
        case .classic:       return "Classic"
        case .endless:       return "Endless"
        case .timed:         return "Timed"
        case .suddenDeath:   return "Sudden Death"
        case .comboFrenzy:   return "Combo Frenzy"
        case .zen:           return "Zen"
        case .duel:          return "Duel"
        case .precision:     return "Precision"
        case .chaos:         return "Chaos"
        case .mirror:        return "Mirror"
        case .invisibleZone: return "Invisible Zone"
        case .rush:          return "Rush"
        case .hardcoreCombo: return "Hardcore Combo"
        case .tinyWindow:    return "Tiny Window"
        case .focus:         return "Focus"
        }
    }

    var modeLabel: String { displayName.uppercased() }

    var description: String {
        switch self {
        case .classic:       return "Score as high as you can. 3 lives. Earn coins."
        case .endless:       return "Speed ramps to max pace, then holds. Survive."
        case .timed:         return "60-second sprint. Misses don't end your run."
        case .suddenDeath:   return "One miss and it's over. No revives."
        case .comboFrenzy:   return "Chase massive combos for huge multipliers."
        case .zen:           return "No score, no lives, no combo pressure. Just tap."
        case .duel:          return "Challenge another player head-to-head."
        case .precision:     return "Only PERFECTs count. Anything else is a miss."
        case .chaos:         return "Speed changes randomly every few taps."
        case .mirror:        return "Indicator reverses direction unpredictably."
        case .invisibleZone: return "Zone bands are hidden. Use the faint center marker."
        case .rush:          return "30 seconds. Insane speed. Pure reflex."
        case .hardcoreCombo: return "Break combo and you'll trigger a speed shock."
        case .tinyWindow:    return "PERFECT zone is half the normal size."
        case .focus:         return "No HUD. No score tracking. Just you and the bar."
        }
    }

    var emoji: String {
        switch self {
        case .classic:       return "🎯"
        case .endless:       return "🔄"
        case .timed:         return "⏱️"
        case .suddenDeath:   return "💀"
        case .comboFrenzy:   return "🔗"
        case .zen:           return "🍃"
        case .duel:          return "⚔️"
        case .precision:     return "🔬"
        case .chaos:         return "🌀"
        case .mirror:        return "🪞"
        case .invisibleZone: return "👁️"
        case .rush:          return "⚡"
        case .hardcoreCombo: return "🔥"
        case .tinyWindow:    return "🪡"
        case .focus:         return "🧘"
        }
    }

    var initialLives: Int? {
        switch self {
        case .zen, .timed:                    return nil
        case .suddenDeath:                    return 1
        case .precision, .tinyWindow:         return 2
        case .rush:                           return 5
        default:                              return 3
        }
    }

    var initialSpeed: Double {
        switch self {
        case .zen:           return GameConfig.zenSpeed
        case .timed:         return GameConfig.timedStartSpeed
        case .suddenDeath:   return GameConfig.suddenDeathStartSpeed
        case .rush:          return 0.55       // very fast from the start
        case .precision:     return 1.0        // moderate — demands accuracy not speed
        case .chaos:         return 1.2        // changes randomly in GameViewModel
        case .mirror:        return 1.0
        case .invisibleZone: return 1.1
        case .hardcoreCombo: return 1.0
        case .tinyWindow:    return 1.1
        case .focus:         return 1.1
        default:             return GameConfig.classicStartSpeed
        }
    }

    var earnCoins: Bool    { self == .classic || self == .duel }
    var earnXP: Bool       { self != .zen }
    var trackScore: Bool   { self != .zen && self != .focus }
    var usesLives: Bool    { initialLives != nil }

    var hasQuitButton: Bool {
        switch self {
        case .endless, .comboFrenzy, .chaos, .hardcoreCombo, .focus: return true
        default: return false
        }
    }

    var hasTimer: Bool { self == .timed || self == .rush }

    /// Ranked on the server-verified leaderboard (must match MODES in
    /// functions/src/scoring.ts).
    var isRanked: Bool { trackScore && self != .duel }

    var isClassicLike: Bool { self == .classic || self == .duel }

    /// Duration for timer-based modes
    var timerDuration: Double {
        switch self {
        case .rush:  return 30.0
        case .timed: return GameConfig.timedDuration
        default:     return 0
        }
    }

    /// Whether this mode supports the revive-after-ad flow.
    /// Per-mode revive policy.
    var supportsRevive: Bool {
        switch self {
        case .zen, .timed, .suddenDeath:
            return false
        default:
            return usesLives
        }
    }

    /// Whether zones should be hidden on the TapBar
    var hidesZones: Bool { self == .invisibleZone }

    /// Whether the HUD is hidden (Focus mode)
    var hidesHUD: Bool { self == .focus }

    /// Perfect zone shrink factor (1.0 = normal, 0.5 = half)
    var perfectZoneScale: Double {
        self == .tinyWindow ? 0.5 : 1.0
    }

    /// Modes shown in the mode select screen (excludes duel — entered via lobby)
    static var selectableModes: [GameMode] {
        [.classic, .endless, .timed, .suddenDeath, .comboFrenzy, .zen,
         .precision, .chaos, .mirror, .invisibleZone, .rush, .hardcoreCombo, .tinyWindow, .focus]
    }

    var bestScoreKey: String {
        switch self {
        case .classic:       return "best_classic"
        case .endless:       return "best_endless"
        case .timed:         return "best_timed"
        case .suddenDeath:   return "best_sudden"
        case .comboFrenzy:   return "best_combofrenzy"
        case .precision:     return "best_precision"
        case .chaos:         return "best_chaos"
        case .mirror:        return "best_mirror"
        case .invisibleZone: return "best_invisiblezone"
        case .rush:          return "best_rush"
        case .hardcoreCombo: return "best_hardcorecombo"
        case .tinyWindow:    return "best_tinywindow"
        case .focus:         return "best_focus"
        default:             return ""
        }
    }

    /// Difficulty tag shown on mode card
    var difficultyTag: String? {
        switch self {
        case .suddenDeath, .precision, .tinyWindow, .hardcoreCombo: return "HARD"
        case .rush, .chaos:                                          return "INTENSE"
        case .invisibleZone, .mirror:                                return "TRICKY"
        default:                                                     return nil
        }
    }

    var difficultyColor: (String) -> Bool {
        { _ in false } // unused, see ModeCardView
    }

    /// Gameplay tip shown on mode card — explains the unique mechanic
    var tip: String? {
        switch self {
        case .classic:       return "Speed increases every 4 taps"
        case .endless:       return "Ramps to max pace, then stabilizes"
        case .timed:         return "Timer is the only fail condition"
        case .suddenDeath:   return "No revive. One miss ends the run"
        case .comboFrenzy:   return "Higher combo = faster speed"
        case .zen:           return "No score, no lives, no combo display"
        case .precision:     return "Visible PERFECT zone shrinks every 5 taps"
        case .chaos:         return "Speed randomizes every few taps"
        case .mirror:        return "Direction flips increase over time"
        case .invisibleZone: return "Bands hidden; only a faint center marker remains"
        case .rush:          return "Final 10s sprint. Revive restores lives only"
        case .hardcoreCombo: return "Combo break = speed shock + tighter PERFECT window"
        case .tinyWindow:    return "Visible PERFECT zone starts tiny and keeps shrinking"
        case .focus:         return "Minimal HUD and no score tracking"
        default:             return nil
        }
    }
}
