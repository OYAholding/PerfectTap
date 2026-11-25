import Foundation

/// Versioned, reviewable economy configuration.
///
/// `balancedPremiumRC1` is an implementation candidate for TestFlight. It is
/// deliberately centralized so Product can tune rewards and prices without
/// changing reward call sites or StoreKit product identifiers.
struct EconomyConfig: Equatable {
    let version: String
    let dailyRewards: [Int]
    let wheelRewards: [Int]
    let questRewards: [DailyQuest.Difficulty: Int]
    let scoreCoinDivisor: Int
    let minimumGameCoins: Int
    let homeRewardedCoins: Int
    let seasonAdsRequired: Int
    let seasonCoinRewards: [Int]
    let shopPrices: [String: Int]
    /// Contract key `starter_items`: Common cosmetics a brand-new player may
    /// claim once (one item) when the authoritative economy is enabled.
    var starterItems: [String] = []
    /// Contract key `gameplay_daily_cap` (server enforced; 0 = none).
    var gameplayDailyCap: Int = 0
    /// Contract key `active_season` (server season the `season_tier` events name).
    var activeSeason: SeasonDefinition? = nil

    /// Contract key `combo_bonus`: `(minCombo, bonus)` evaluated highest first.
    static let comboBonusTable: [(minCombo: Int, bonus: Int)] = [(20, 8), (10, 5), (5, 3), (0, 1)]
    /// Contract key `mode_bonus`.
    static let modeBonus: [GameMode: Int] = [.classic: 2, .duel: 6]

    struct SeasonDefinition: Equatable {
        let id: String
        let title: String
        let startsAtISO: String
        let endsAtISO: String
        let tiers: Int
        let maxTiersPerDay: Int

        init(id: String, title: String, startsAt: String, endsAt: String, tiers: Int, maxTiersPerDay: Int) {
            self.id = id
            self.title = title
            self.startsAtISO = startsAt
            self.endsAtISO = endsAt
            self.tiers = tiers
            self.maxTiersPerDay = maxTiersPerDay
        }

        var startsAt: Date? { ISO8601DateFormatter().date(from: startsAtISO) }
        var endsAt: Date? { ISO8601DateFormatter().date(from: endsAtISO) }
    }

    /// Shipping behavior while owner approval and rollout remain off.
    static let legacy = EconomyConfig(
        version: "pre-authoritative",
        dailyRewards: [25, 35, 50, 75, 100, 125, 250],
        wheelRewards: [25, 50, 10, 100, 35, 5, 250, 75],
        questRewards: [:],
        scoreCoinDivisor: 50,
        minimumGameCoins: 3,
        homeRewardedCoins: 25,
        seasonAdsRequired: 50,
        seasonCoinRewards: [
            50, 100, 100, 150, 150, 75, 200, 125, 150, 300,
            75, 100, 125, 150, 400, 75, 100, 125, 150, 500,
            75, 100, 125, 150, 750, 75, 100, 125, 150, 1_000,
        ],
        shopPrices: [:]
    )

    static let balancedPremiumRC1 = EconomyConfig(
        version: "balanced-premium-rc1",
        dailyRewards: [10, 15, 20, 25, 30, 40, 60],
        wheelRewards: [5, 5, 10, 10, 15, 15, 20, 40],
        questRewards: [.easy: 25, .medium: 45, .hard: 75],
        scoreCoinDivisor: 80,
        minimumGameCoins: 4,
        homeRewardedCoins: 15,
        seasonAdsRequired: 20,
        seasonCoinRewards: Array(repeating: [25, 50, 75, 100, 125], count: 6).flatMap { $0 },
        shopPrices: [
            "theme_neon": 250, "theme_fire": 600, "theme_ice": 650,
            "theme_gold": 1_200, "theme_galaxy": 1_400,
            "theme_midnight": 700, "theme_sunset": 1_300,
            "theme_matrix": 2_500,
            "fx_ripple": 250, "fx_spark": 600, "fx_hearts": 550,
            "fx_stars": 1_200, "fx_confetti": 1_100, "fx_shatter": 2_500,
            "avatar_cool": 250, "avatar_ninja": 550,
            "avatar_robot": 600, "avatar_alien": 1_100,
            "avatar_wizard": 1_200, "avatar_king": 1_350,
            "avatar_devil": 1_250, "avatar_unicorn": 2_400,
            "avatar_dragon": 2_800,
        ],
        starterItems: ["theme_neon", "fx_ripple", "avatar_cool"],
        gameplayDailyCap: 1_500,
        // Placeholder pending the owner's season calendar (seeded by migration
        // 20261125200000_authoritative_economy_sources.sql).
        activeSeason: SeasonDefinition(id: "season_1_neon_nights", title: "Neon Nights",
                                       startsAt: "2026-12-01T00:00:00Z", endsAt: "2027-03-01T00:00:00Z",
                                       tiers: 30, maxTiersPerDay: 15)
    )

    static var current: EconomyConfig {
        FeatureFlags.authoritativeEconomyEnabled ? balancedPremiumRC1 : legacy
    }

    func shopPrice(itemID: String, fallback: Int) -> Int {
        shopPrices[itemID] ?? fallback
    }

    func questReward(_ difficulty: DailyQuest.Difficulty, fallback: Int) -> Int {
        questRewards[difficulty] ?? fallback
    }

    func seasonReward(tier: Int) -> Int {
        guard tier > 0, tier <= seasonCoinRewards.count else { return 0 }
        return seasonCoinRewards[tier - 1]
    }

    func gameCoins(score: Int, maxCombo: Int, mode: GameMode) -> Int {
        guard mode.earnCoins else { return 0 }
        let base = max(0, score) / scoreCoinDivisor
        let comboBonus = Self.comboBonusTable.first { maxCombo >= $0.minCombo }?.bonus ?? 1
        let modeBonus = Self.modeBonus[mode] ?? 2
        return max(minimumGameCoins, base + comboBonus + modeBonus)
    }

    func dailyReward(streak: Int) -> Int {
        guard !dailyRewards.isEmpty else { return 0 }
        return dailyRewards[max(0, streak) % dailyRewards.count]
    }

    /// Season coin cycle (`season_coin_cycle`): the repeating unit of the free track.
    var seasonCoinCycle: [Int] {
        guard version == Self.balancedPremiumRC1.version else { return seasonCoinRewards }
        return Array(seasonCoinRewards.prefix(5))
    }

    /// One-time rewards keyed by id (`achievement_rewards`). Today's catalog
    /// values are reused for every config version.
    static var achievementRewards: [String: Int] {
        Dictionary(uniqueKeysWithValues: Achievement.all.map { ($0.id, $0.reward) })
    }

    /// `challenge_rewards{id:{coins,item}}` derived from the challenge catalog.
    static var challengeRewards: [String: (coins: Int, item: String?)] {
        Dictionary(uniqueKeysWithValues: Challenge.all.map { challenge in
            let reward = Challenge.parseReward(challenge.rewardLabel)
            return (challenge.id, (reward.coins, reward.theme))
        })
    }

    /// The shared numbers in the contract's `economy_configs.config` key space.
    /// Pinned by a unit test so the Swift copy and the Supabase seed agree.
    var contractValues: [String: Any] {
        [
            "daily_rewards": dailyRewards,
            "wheel_rewards": wheelRewards,
            "quest_rewards": [
                "easy": questRewards[.easy] ?? 0,
                "medium": questRewards[.medium] ?? 0,
                "hard": questRewards[.hard] ?? 0,
            ],
            "score_coin_divisor": scoreCoinDivisor,
            "minimum_game_coins": minimumGameCoins,
            "home_rewarded_coins": homeRewardedCoins,
            "season_ads_required": seasonAdsRequired,
            "season_coin_cycle": seasonCoinCycle,
            "starter_items": starterItems,
            "gameplay_daily_cap": gameplayDailyCap,
            "active_season": activeSeason.map {
                ["id": $0.id, "starts_at": $0.startsAtISO, "ends_at": $0.endsAtISO,
                 "tiers": $0.tiers, "max_tiers_per_day": $0.maxTiersPerDay] as [String: Any]
            } ?? [:],
        ]
    }
}

