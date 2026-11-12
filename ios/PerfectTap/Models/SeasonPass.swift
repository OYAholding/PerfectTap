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

            switch i {
            case 1:  free = .init(type: .coins(50),  label: "50 Coins",  icon: "🪙"); premium = .init(type: .avatar("avatar_cool"), label: "Neon Cat Avatar", icon: "😸")
            case 3:  free = .init(type: .coins(100), label: "100 Coins", icon: "🪙"); premium = .init(type: .theme("neon"),         label: "Neon Theme",      icon: "🌈")
            case 5:  free = .init(type: .coins(150), label: "150 Coins", icon: "🪙"); premium = .init(type: .avatar("avatar_robot"), label: "Robot Avatar",    icon: "🤖")
            case 7:  free = .init(type: .coins(200), label: "200 Coins", icon: "🪙"); premium = .init(type: .theme("fire"),         label: "Fire Theme",      icon: "🔥")
            case 10: free = .init(type: .coins(300), label: "300 Coins", icon: "🪙"); premium = .init(type: .avatar("avatar_alien"), label: "Ghost Avatar",    icon: "👻")
            case 15: free = .init(type: .coins(400), label: "400 Coins", icon: "🪙"); premium = .init(type: .theme("galaxy"),      label: "Galaxy Theme",    icon: "🌌")
            case 20: free = .init(type: .coins(500), label: "500 Coins", icon: "🪙"); premium = .init(type: .avatar("avatar_dragon"),label: "Dragon Avatar",   icon: "🐉")
            case 25: free = .init(type: .coins(750), label: "750 Coins", icon: "🪙"); premium = .init(type: .badge("badge_neon"),   label: "Neon Badge",      icon: "⚡")
            case 30: free = .init(type: .coins(1000),label: "1000 Coins",icon: "🪙"); premium = .init(type: .avatar("avatar_king"), label: "Crown Avatar",    icon: "👑")
            default:
                let coins = [50, 75, 100, 125, 150][i % 5]
                free = .init(type: .coins(coins), label: "\(coins) Coins", icon: "🪙")
                premium = nil
            }

            tiers.append(SeasonTier(id: i, freeReward: free, premiumReward: premium))
        }
        return tiers
    }()
}
