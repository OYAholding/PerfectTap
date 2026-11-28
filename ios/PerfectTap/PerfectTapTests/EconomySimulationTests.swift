import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Re-runs the weekly-income model of docs/ECONOMY_1_2_0_EXECUTION.he.md
/// ("בדיקת התקדמות והעודף") from `EconomyConfig.balancedPremiumRC1`.
///
/// Weekly income = games × game reward + Daily + Wheel (EV) + Quests + home
/// rewarded. Excludes achievements, challenges, Season coins and IAP (as the doc).
final class EconomySimulationTests: XCTestCase {
    struct Profile {
        let name: String
        let activeDays: Int
        let gamesPerDay: Int
        let score: Int
        let maxCombo: Int
        let questsPerDay: [DailyQuest.Difficulty]
        let homeRewarded: Bool
        let documentedWeekly: Int
    }

    static let profiles: [Profile] = [
        Profile(name: "New", activeDays: 7, gamesPerDay: 2, score: 500, maxCombo: 5,
                questsPerDay: [], homeRewarded: false, documentedWeekly: 470),
        Profile(name: "Casual", activeDays: 5, gamesPerDay: 2, score: 500, maxCombo: 5,
                questsPerDay: [.easy], homeRewarded: false, documentedWeekly: 420),
        Profile(name: "Regular", activeDays: 7, gamesPerDay: 5, score: 1_000, maxCombo: 10,
                questsPerDay: [.easy, .medium], homeRewarded: true, documentedWeekly: 1_500),
        Profile(name: "Active", activeDays: 7, gamesPerDay: 10, score: 2_000, maxCombo: 10,
                questsPerDay: [.easy, .medium, .hard], homeRewarded: true, documentedWeekly: 3_560),
        Profile(name: "Highly skilled", activeDays: 7, gamesPerDay: 15, score: 5_000, maxCombo: 20,
                questsPerDay: [.easy, .medium, .hard], homeRewarded: true, documentedWeekly: 8_985),
    ]

    static func weeklyIncome(_ p: Profile, config: EconomyConfig = .balancedPremiumRC1) -> Int {
        let game = config.gameCoins(score: p.score, maxCombo: p.maxCombo, mode: .classic)
        let games = p.activeDays * p.gamesPerDay * game
        // Consecutive active days from a fresh streak.
        let daily = (0..<p.activeDays).reduce(0) { $0 + config.dailyReward(streak: $1) }
        let wheelEV = Double(config.wheelRewards.reduce(0, +)) / Double(config.wheelRewards.count)
        let wheel = Int((wheelEV * Double(p.activeDays)).rounded())
        let quests = p.activeDays * p.questsPerDay.reduce(0) { $0 + config.questReward($1, fallback: 0) }
        let home = p.homeRewarded ? p.activeDays * config.homeRewardedCoins : 0
        return games + daily + wheel + quests + home
    }

    func testWeeklyIncomeMatchesDocumentedModel() {
        let shopTotal = EconomyConfig.balancedPremiumRC1.shopPrices.values.reduce(0, +)
        XCTAssertEqual(shopTotal, 26_300)
        var report = "\nprofile | weekly (sim) | weekly (doc) | weeks to complete shop | days to first 250\n"
        for p in Self.profiles {
            let weekly = Self.weeklyIncome(p)
            let weeks = Double(shopTotal) / Double(weekly)
            let daysTo250 = 250.0 / (Double(weekly) / Double(p.activeDays))
            report += String(format: "%@ | %d | ~%d | %.1f | %.1f\n",
                             p.name, weekly, p.documentedWeekly, weeks, daysTo250)
            // Within 10 % of the documented figure.
            XCTAssertEqual(Double(weekly), Double(p.documentedWeekly),
                           accuracy: Double(p.documentedWeekly) * 0.10, p.name)
        }
        print(report)
        XCTAssertEqual(Self.weeklyIncome(Self.profiles[4]), 8_985, "skilled profile reproduces exactly")
    }
}
