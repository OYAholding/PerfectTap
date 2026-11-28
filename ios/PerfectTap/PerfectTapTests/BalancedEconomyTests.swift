import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

@MainActor
final class BalancedEconomyTests: XCTestCase {
    func testRCConfigIsVersionedAndMatchesBalancedBudget() {
        let config = EconomyConfig.balancedPremiumRC1
        XCTAssertEqual(config.version, "balanced-premium-rc1")
        XCTAssertEqual(config.dailyRewards, [10, 15, 20, 25, 30, 40, 60])
        XCTAssertEqual(config.dailyRewards.reduce(0, +), 200)
        XCTAssertEqual(config.wheelRewards.reduce(0, +), 120)
        XCTAssertEqual(config.questReward(.easy, fallback: 0), 25)
        XCTAssertEqual(config.questReward(.medium, fallback: 0), 45)
        XCTAssertEqual(config.questReward(.hard, fallback: 0), 75)
        XCTAssertEqual(config.seasonCoinRewards.reduce(0, +), 2_250)
    }

    func testBalancedGameCoinFormula() {
        let config = EconomyConfig.balancedPremiumRC1
        XCTAssertEqual(config.gameCoins(score: 1_000, maxCombo: 10, mode: .classic), 19)
        XCTAssertEqual(config.gameCoins(score: 1_000, maxCombo: 10, mode: .duel), 23)
        XCTAssertEqual(config.gameCoins(score: 0, maxCombo: 0, mode: .classic), 4)
        XCTAssertEqual(config.gameCoins(score: 50_000, maxCombo: 20, mode: .classic), 635)
        XCTAssertEqual(config.gameCoins(score: 1_000, maxCombo: 10, mode: .practice), 0)
    }

    func testVisibleCoinCatalogUsesBalancedPrices() {
        let prices = EconomyConfig.balancedPremiumRC1.shopPrices
        XCTAssertEqual(prices.count, 23)
        XCTAssertEqual(prices.values.reduce(0, +), 26_300)
        XCTAssertEqual(prices["theme_neon"], 250)
        XCTAssertEqual(prices["avatar_dragon"], 2_800)
    }

    func testCandidateEconomyIsOffByDefault() {
        XCTAssertFalse(FeatureFlags.authoritativeEconomyEnabled)
        XCTAssertEqual(EconomyConfig.current.version, "pre-authoritative")
        XCTAssertEqual(ShopItem.item(id: "theme_neon")?.price, 75)
    }

    func testRewardPlacementCapsArePerAccountAndDay() {
        let defaults = UserDefaults(suiteName: "reward-limits-\(UUID().uuidString)")!
        let limiter = RewardClaimLimiter(defaults: defaults)

        XCTAssertTrue(limiter.record(.homeCoins, day: "2026-11-25", userID: "a"))
        XCTAssertFalse(limiter.record(.homeCoins, day: "2026-11-25", userID: "a"))
        XCTAssertTrue(limiter.canClaim(.homeCoins, day: "2026-11-26", userID: "a"))
        XCTAssertTrue(limiter.canClaim(.homeCoins, day: "2026-11-25", userID: "b"))

        XCTAssertTrue(limiter.record(.revive, day: "2026-11-25", userID: "a"))
        XCTAssertTrue(limiter.record(.revive, day: "2026-11-25", userID: "a"))
        XCTAssertTrue(limiter.record(.revive, day: "2026-11-25", userID: "a"))
        XCTAssertFalse(limiter.record(.revive, day: "2026-11-25", userID: "a"))
    }

    func testRemoveAdsDoesNotBypassRewardedInventory() async {
        let original = PlayerProfile.load()
        defer {
            if let original { original.save() } else { PlayerProfile.clearSaved() }
        }
        var profile = PlayerProfile()
        profile.noAds = true
        profile.save()

        XCTAssertFalse(AdManager.shared.isAdReady(for: .homeCoins))
        let rewarded = await AdManager.shared.showRewardedAd(placement: .homeCoins)
        XCTAssertFalse(rewarded)
    }
}

