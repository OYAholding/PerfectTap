import Foundation

// MARK: - Player Profile (mirrors Firestore document + local UserDefaults cache)
struct PlayerProfile: Codable {
    var uid: String = ""
    var username: String = ""
    var avatar: String = "default"
    var coins: Int = 0
    var level: Int = 1
    var xp: Int = 0

    // Best scores per mode
    var bestClassic: Int = 0
    var bestEndless: Int = 0
    var bestTimed: Int = 0
    var bestSudden: Int = 0
    var bestComboFrenzy: Int = 0

    // Social
    var friendCode: String = ""
    var friends: [String] = []   // array of UIDs

    // Cosmetics
    var ownedItems: [String] = []
    var equippedTheme: String = "default"
    var equippedAvatar: String = "default"
    var equippedTapFX: String = "fx_default"
    var equippedTrail: String = "trail_none"
    var equippedBadge: String = ""

    // Season pass
    var seasonXP: Int = 0
    var seasonTier: Int = 0
    var seasonPremium: Bool = false
    var seasonAdProgress: Int = 0          // number of completed rewarded ads toward premium unlock
    var seasonClaimedTiers: [Int] = []     // tier IDs whose rewards have been granted

    // Daily rewards
    var dailyRewardStreak: Int = 0
    var dailyRewardLastClaim: String = ""   // ISO date string

    // Quests (stored as JSON string for Firestore flexibility)
    var questsJSON: String = "{}"

    // Achievements (array of achievement IDs)
    var achievements: [String] = []
    // Challenge completion state (separate from achievements)
    var completedChallenges: [String] = []

    // Stats
    var stats: PlayerStats = PlayerStats()

    // Score history (last 10 classic games)
    var scoreHistory: [ScoreEntry] = []

    // Active challenge
    var activeChallenge: String = ""

    // Score boost
    var boost: ScoreBoost? = nil

    // No-ads flag
    var noAds: Bool = false

    // Revive tracking: number of revives used today (anti-abuse)
    var revivesUsedToday: Int = 0
    var lastReviveDate: String = ""   // ISO date string "yyyy-MM-dd"

    // Generic best scores for new modes (keyed by GameMode.bestScoreKey)
    var bestScoresExtra: [String: Int] = [:]

    static func canonicalAvatarID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "default" { return "avatar_default" }
        return trimmed
    }

    var socialAvatarID: String {
        Self.canonicalAvatarID(equippedAvatar.isEmpty ? avatar : equippedAvatar)
    }

    private static let legacyChallengeIDs: Set<String> = Set((1...10).map { "c\($0)" })

    mutating func normalizeAndMigrate() {
        // Canonicalize avatar storage and keep legacy `avatar` in sync with equipped avatar.
        let canonical = Self.canonicalAvatarID(equippedAvatar.isEmpty ? avatar : equippedAvatar)
        equippedAvatar = canonical
        avatar = canonical

        // Migrate legacy challenge IDs that were previously mixed into achievements.
        let legacyCompletions = achievements.filter { Self.legacyChallengeIDs.contains($0) }
        if !legacyCompletions.isEmpty {
            var seen = Set(completedChallenges)
            for id in legacyCompletions where seen.insert(id).inserted {
                completedChallenges.append(id)
            }
            achievements.removeAll { Self.legacyChallengeIDs.contains($0) }
        }
    }

    func bestScore(for mode: GameMode) -> Int {
        switch mode {
        case .classic:     return bestClassic
        case .endless:     return bestEndless
        case .timed:       return bestTimed
        case .suddenDeath: return bestSudden
        case .comboFrenzy: return bestComboFrenzy
        default:
            let key = mode.bestScoreKey
            return key.isEmpty ? 0 : (bestScoresExtra[key] ?? 0)
        }
    }

    mutating func updateBestScore(_ score: Int, for mode: GameMode) {
        switch mode {
        case .classic:     if score > bestClassic     { bestClassic = score }
        case .endless:     if score > bestEndless     { bestEndless = score }
        case .timed:       if score > bestTimed       { bestTimed = score }
        case .suddenDeath: if score > bestSudden      { bestSudden = score }
        case .comboFrenzy: if score > bestComboFrenzy { bestComboFrenzy = score }
        default:
            let key = mode.bestScoreKey
            guard !key.isEmpty else { return }
            if score > (bestScoresExtra[key] ?? 0) { bestScoresExtra[key] = score }
        }
    }
}

struct PlayerStats: Codable {
    var totalGames: Int = 0
    var duelWins: Int = 0
    var duelLosses: Int = 0
    var duelTies: Int = 0
    var totalCoinsEarned: Int = 0
    var perfectTaps: Int = 0
    var highestCombo: Int = 0
}

struct ScoreEntry: Codable, Identifiable {
    var id: String = UUID().uuidString
    var score: Int
    var date: String   // ISO date
}

struct ScoreBoost: Codable {
    var value: Double   // e.g. 2.0 for 2×
    var used: Bool
    var games: Int
}

// MARK: - UserDefaults persistence
extension PlayerProfile {
    private static let key = "perfecttap_player_profile"

    static func load() -> PlayerProfile? {
        guard let data = UserDefaults.standard.data(forKey: key),
              var profile = try? JSONDecoder().decode(PlayerProfile.self, from: data)
        else { return nil }
        profile.normalizeAndMigrate()
        return profile
    }

    func save() {
        var normalized = self
        normalized.normalizeAndMigrate()
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: PlayerProfile.key)
        }
    }
}
