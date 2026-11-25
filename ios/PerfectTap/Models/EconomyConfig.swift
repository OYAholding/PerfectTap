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
        ]
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
        let comboBonus = maxCombo >= 20 ? 8 : maxCombo >= 10 ? 5 : maxCombo >= 5 ? 3 : 1
        let modeBonus = mode == .duel ? 6 : 2
        return max(minimumGameCoins, base + comboBonus + modeBonus)
    }
}

