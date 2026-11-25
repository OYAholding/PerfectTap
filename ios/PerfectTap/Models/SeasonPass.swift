import Foundation

// MARK: - Season Pass (Season 1: Neon Nights)
struct SeasonTier: Identifiable {
    let id: Int   // tier number 1–30
    let freeReward: SeasonReward?
    let premiumReward: SeasonReward?
}

struct SeasonReward {
    let type: RewardType
    let label: String
    let icon: String

    enum RewardType {
        case coins(Int)
        case avatar(String)
        case theme(String)
        case badge(String)
    }
}

// MARK: - Season 1 tier data
extension SeasonTier {
    static let season1Tiers: [SeasonTier] = {
        var tiers: [SeasonTier] = []
        for i in 1...30 {
            let free: SeasonReward?
            let premium: SeasonReward?

            let coins = EconomyConfig.current.seasonReward(tier: i)
            free = .init(type: .coins(coins), label: "\(coins) Coins", icon: "🪙")
            switch i {
            case 1:  premium = .init(type: .avatar("avatar_cool"), label: "Cool Avatar", icon: "😎")
            case 3:  premium = .init(type: .theme("neon"), label: "Neon Theme", icon: "🌈")
            case 5:  premium = .init(type: .avatar("avatar_robot"), label: "Robot Avatar", icon: "🤖")
            case 7:  premium = .init(type: .theme("fire"), label: "Fire Theme", icon: "🔥")
            case 10: premium = .init(type: .avatar("avatar_alien"), label: "Alien Avatar", icon: "👽")
            case 15: premium = .init(type: .theme("galaxy"), label: "Galaxy Theme", icon: "🌌")
            case 20: premium = .init(type: .avatar("avatar_dragon"), label: "Dragon Avatar", icon: "🐉")
            case 25: premium = .init(type: .badge("badge_neon"), label: "Neon Badge", icon: "⚡")
            case 30: premium = .init(type: .avatar("avatar_king"), label: "King Avatar", icon: "🤴")
            default: premium = nil
            }

            tiers.append(SeasonTier(id: i, freeReward: free, premiumReward: premium))
        }
        return tiers
    }()
}

// MARK: - Season schedule
//
// Season 1 ("Neon Nights") ran Mar 1 – May 31, 2026 and the header was
// hard-coded, so it showed an expired season. Seasons now repeat on a fixed
// three-month cycle anchored at Season 1 (UTC): Mar–May, Jun–Aug, Sep–Nov,
// Dec–Feb. Computing a new cycle never touches the player's earned tiers,
// claimed rewards or premium state.
struct SeasonSchedule: Equatable {
    let number: Int
    let startsAt: Date
    /// Exclusive end (first instant of the next season).
    let endsAt: Date
    /// Server season (`active_season`) covering this date, when configured.
    var configured: EconomyConfig.SeasonDefinition? = nil

    static let cycleMonths = 3
    private static let anchorYear = 2026
    private static let anchorMonth = 3

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    /// Identifier used in `season_tier` events: the server's `active_season.id`
    /// when it covers the date, else the computed cycle (`season_<n>`).
    var id: String { configured?.id ?? "season_\(number)" }

    var title: String {
        if let configured { return "Season \(number): \(configured.title)" }
        return number == 1 ? "Season 1: Neon Nights" : "Season \(number)"
    }

    var displayRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        let lastDay = endsAt.addingTimeInterval(-1)
        let year = Self.utc.component(.year, from: lastDay)
        return "\(formatter.string(from: startsAt)) – \(formatter.string(from: lastDay)), \(year)"
    }

    func contains(_ date: Date) -> Bool { date >= startsAt && date < endsAt }

    static func current(now: Date = Date(),
                        configuredSeasons: [EconomyConfig.SeasonDefinition] =
                            [EconomyConfig.balancedPremiumRC1.activeSeason].compactMap { $0 }) -> SeasonSchedule {
        if let season = configuredSeasons.first(where: { def in
            guard let start = def.startsAt, let end = def.endsAt else { return false }
            return now >= start && now < end
        }), let start = season.startsAt, let end = season.endsAt {
            var computed = cycle(containing: now)
            computed = SeasonSchedule(number: computed.number, startsAt: start, endsAt: end, configured: season)
            return computed
        }
        return cycle(containing: now)
    }

    private static func cycle(containing now: Date) -> SeasonSchedule {
        let calendar = utc
        let c = calendar.dateComponents([.year, .month], from: now)
        let monthsSinceAnchor = ((c.year ?? anchorYear) - anchorYear) * 12 + ((c.month ?? anchorMonth) - anchorMonth)
        // Floor division so dates before the anchor still map to a cycle.
        let index = monthsSinceAnchor >= 0
            ? monthsSinceAnchor / cycleMonths
            : -((-monthsSinceAnchor + cycleMonths - 1) / cycleMonths)
        let anchor = calendar.date(from: DateComponents(year: anchorYear, month: anchorMonth, day: 1)) ?? now
        let start = calendar.date(byAdding: .month, value: index * cycleMonths, to: anchor) ?? anchor
        let end = calendar.date(byAdding: .month, value: cycleMonths, to: start) ?? start
        return SeasonSchedule(number: max(1, index + 1), startsAt: start, endsAt: end)
    }
}
