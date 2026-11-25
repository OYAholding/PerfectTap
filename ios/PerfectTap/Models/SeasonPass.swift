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
