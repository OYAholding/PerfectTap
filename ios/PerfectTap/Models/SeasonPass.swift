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
// Season 1 ("Neon Nights") ran Mar 1 – May 31, 2026. Seasons repeat on the
// deterministic calendar rule `EconomyConfig.SeasonCalendarRule` (server
// config key `season_calendar`): a fixed three-month cycle anchored at
// 2026-03-01 UTC — Mar–May, Jun–Aug, Sep–Nov, Dec–Feb — with ids
// `season_<n>`. The server (`private.season_at` / `season_tier_verdict`)
// computes exactly the same ids and boundaries. Computing a new cycle never
// touches the player's earned tiers, claimed rewards or premium state.
struct SeasonSchedule: Equatable {
    let number: Int
    let startsAt: Date
    /// Exclusive end (first instant of the next season).
    let endsAt: Date
    /// Identifier used in `season_tier` events (`season_<n>`).
    let id: String

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    var title: String {
        number == 1 ? "Season 1: Neon Nights" : "Season \(number)"
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

    /// Season shown in the UI. Dates before the anchor (wrong device clock)
    /// display Season 1 rather than nothing.
    static func current(now: Date = Date(),
                        rule: EconomyConfig.SeasonCalendarRule = EconomyConfig.current.seasonCalendar) -> SeasonSchedule {
        if let season = season(at: now, rule: rule) { return season }
        if let anchor = anchorDate(rule), let first = season(at: anchor, rule: rule) { return first }
        // Malformed rule (never shipped): keep the screen working.
        return SeasonSchedule(number: 1, startsAt: now, endsAt: now.addingTimeInterval(90 * 86_400),
                              id: rule.seasonID(number: 1))
    }

    /// Server parity (`private.season_at`): the season containing `date` in
    /// UTC, or nil before the anchor / for a malformed rule.
    static func season(at date: Date,
                       rule: EconomyConfig.SeasonCalendarRule = EconomyConfig.current.seasonCalendar) -> SeasonSchedule? {
        guard let anchorYM = rule.anchorYearMonth, let anchor = anchorDate(rule), date >= anchor else { return nil }
        let calendar = utc
        let c = calendar.dateComponents([.year, .month], from: date)
        guard let year = c.year, let month = c.month else { return nil }
        let monthsSinceAnchor = (year - anchorYM.year) * 12 + (month - anchorYM.month)
        let index = monthsSinceAnchor / rule.lengthMonths      // >= 0
        guard let start = calendar.date(byAdding: .month, value: index * rule.lengthMonths, to: anchor),
              let end = calendar.date(byAdding: .month, value: rule.lengthMonths, to: start) else { return nil }
        return SeasonSchedule(number: index + 1, startsAt: start, endsAt: end, id: rule.seasonID(number: index + 1))
    }

    /// Server parity (`private.season_tier_verdict`): nil when a `season_tier`
    /// claim is acceptable at `now`, else the server error code
    /// (`invalid_payload` or `implausible_result`). Accepts the current season,
    /// or the previous season until its end + `graceHours`.
    static func claimVerdict(seasonID: String, tier: Int, now: Date,
                             rule: EconomyConfig.SeasonCalendarRule = EconomyConfig.current.seasonCalendar) -> String? {
        guard let current = season(at: now, rule: rule), tier >= 1 else { return "invalid_payload" }
        let start: Date
        if seasonID == current.id {
            start = current.startsAt
        } else if let previous = season(at: current.startsAt.addingTimeInterval(-1), rule: rule),
                  previous.id == seasonID,
                  now < previous.endsAt.addingTimeInterval(TimeInterval(rule.graceHours) * 3_600) {
            start = previous.startsAt
        } else {
            return "invalid_payload"
        }
        guard tier <= rule.tiers else { return "invalid_payload" }
        let days = Int(floor(now.timeIntervalSince(start) / 86_400)) + 1
        guard tier <= rule.maxTiersPerDay * days else { return "implausible_result" }
        return nil
    }

    /// True while a claim naming `seasonID` can still be accepted: the current
    /// season or the previous one inside the grace window (tier rules aside).
    static func isClaimable(seasonID: String, now: Date,
                            rule: EconomyConfig.SeasonCalendarRule = EconomyConfig.current.seasonCalendar) -> Bool {
        claimVerdict(seasonID: seasonID, tier: 1, now: now, rule: rule) == nil
    }

    private static func anchorDate(_ rule: EconomyConfig.SeasonCalendarRule) -> Date? {
        guard let ym = rule.anchorYearMonth else { return nil }
        return utc.date(from: DateComponents(year: ym.year, month: ym.month, day: 1))
    }
}
