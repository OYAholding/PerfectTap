import Foundation

// MARK: - Achievement (ported from achievementSystem.jsx — all 37 + extras)
struct Achievement: Identifiable {
    let id: String
    let title: String
    let desc: String
    let icon: String
    let reward: Int   // coins

    // Check if this achievement is unlocked given stats + last game data
    let check: (PlayerStats, GameData?, PlayerProfile?) -> Bool
}

struct GameData {
    var score: Int
    var maxCombo: Int
    var mode: GameMode
}

// MARK: - All achievements
extension Achievement {
    static let all: [Achievement] = [
        // Game count
        Achievement(id: "games_1",    title: "First Game",       desc: "Play your first game",   icon: "🎮", reward: 25,   check: { s, _, _ in s.totalGames >= 1 }),
        Achievement(id: "games_10",   title: "Getting Started",  desc: "Play 10 games",          icon: "🎮", reward: 50,   check: { s, _, _ in s.totalGames >= 10 }),
        Achievement(id: "games_50",   title: "Regular Player",   desc: "Play 50 games",          icon: "🕹️", reward: 150,  check: { s, _, _ in s.totalGames >= 50 }),
        Achievement(id: "games_100",  title: "Dedicated",        desc: "Play 100 games",         icon: "🏅", reward: 300,  check: { s, _, _ in s.totalGames >= 100 }),
        Achievement(id: "games_500",  title: "Veteran",          desc: "Play 500 games",         icon: "🎖️", reward: 1000, check: { s, _, _ in s.totalGames >= 500 }),
        Achievement(id: "games_1000", title: "Legend",           desc: "Play 1000 games",        icon: "👑", reward: 2500, check: { s, _, _ in s.totalGames >= 1000 }),

        // Score milestones (single game)
        Achievement(id: "score_500",  title: "Half Grand",       desc: "Score 500 in one game",  icon: "⭐", reward: 50,   check: { _, g, _ in (g?.score ?? 0) >= 500 }),
        Achievement(id: "score_1000", title: "Grand Master",     desc: "Score 1000 in one game", icon: "🌟", reward: 100,  check: { _, g, _ in (g?.score ?? 0) >= 1000 }),
        Achievement(id: "score_2000", title: "Unstoppable",      desc: "Score 2000 in one game", icon: "💫", reward: 250,  check: { _, g, _ in (g?.score ?? 0) >= 2000 }),
        Achievement(id: "score_5000", title: "Godlike",          desc: "Score 5000 in one game", icon: "🔱", reward: 500,  check: { _, g, _ in (g?.score ?? 0) >= 5000 }),

        // Combo milestones
        Achievement(id: "combo_10",   title: "Chain Starter",    desc: "Reach 10x combo",        icon: "🔗", reward: 50,   check: { s, g, _ in (g?.maxCombo ?? s.highestCombo) >= 10 }),
        Achievement(id: "combo_20",   title: "Combo Master",     desc: "Reach 20x combo",        icon: "⛓️", reward: 150,  check: { s, g, _ in (g?.maxCombo ?? s.highestCombo) >= 20 }),
        Achievement(id: "combo_50",   title: "Combo Legend",     desc: "Reach 50x combo",        icon: "💥", reward: 500,  check: { s, g, _ in (g?.maxCombo ?? s.highestCombo) >= 50 }),

        // Duel
        Achievement(id: "duel_1",     title: "Duelist",          desc: "Win your first duel",    icon: "⚔️", reward: 50,   check: { s, _, _ in s.duelWins >= 1 }),
        Achievement(id: "duel_10",    title: "Duel Champion",    desc: "Win 10 duels",           icon: "🏆", reward: 300,  check: { s, _, _ in s.duelWins >= 10 }),
        Achievement(id: "duel_50",    title: "Duel King",        desc: "Win 50 duels",           icon: "👊", reward: 1000, check: { s, _, _ in s.duelWins >= 50 }),

        // Coins
        Achievement(id: "coins_1000",  title: "Coin Collector",  desc: "Earn 1000 total coins",  icon: "🪙", reward: 100,  check: { s, _, _ in s.totalCoinsEarned >= 1000 }),
        Achievement(id: "coins_10000", title: "Rich Player",     desc: "Earn 10000 total coins", icon: "💰", reward: 500,  check: { s, _, _ in s.totalCoinsEarned >= 10000 }),

        // Accuracy
        Achievement(id: "perfect_100",  title: "Sharpshooter",   desc: "Hit 100 perfect taps",   icon: "🎯", reward: 100,  check: { s, _, _ in s.perfectTaps >= 100 }),
        Achievement(id: "perfect_1000", title: "Eagle Eye",      desc: "Hit 1000 perfect taps",  icon: "🦅", reward: 500,  check: { s, _, _ in s.perfectTaps >= 1000 }),

        // Streak
        Achievement(id: "streak_7",  title: "Weekly Warrior",    desc: "7-day login streak",     icon: "🔥", reward: 200,  check: { _, _, p in (p?.dailyRewardStreak ?? 0) >= 7 }),
        Achievement(id: "streak_30", title: "Monthly Warrior",   desc: "30-day login streak",    icon: "🔥", reward: 1000, check: { _, _, p in (p?.dailyRewardStreak ?? 0) >= 30 }),

        // Additional score tiers
        Achievement(id: "score_10000", title: "Legendary",       desc: "Score 10000 in one game", icon: "🏆", reward: 1000, check: { _, g, _ in (g?.score ?? 0) >= 10000 }),

        // Additional combo
        Achievement(id: "combo_100",   title: "Combo God",       desc: "Reach 100x combo",       icon: "💥", reward: 1000, check: { s, g, _ in (g?.maxCombo ?? s.highestCombo) >= 100 }),

        // Additional coins
        Achievement(id: "coins_50000",  title: "Wealthy",        desc: "Earn 50000 total coins",  icon: "💰", reward: 1000, check: { s, _, _ in s.totalCoinsEarned >= 50000 }),
        Achievement(id: "coins_100000", title: "Millionaire",    desc: "Earn 100000 total coins", icon: "🤑", reward: 2500, check: { s, _, _ in s.totalCoinsEarned >= 100000 }),

        // Additional accuracy
        Achievement(id: "perfect_5000",  title: "Sniper",        desc: "Hit 5000 perfect taps",   icon: "🎯", reward: 500,  check: { s, _, _ in s.perfectTaps >= 5000 }),
        Achievement(id: "perfect_10000", title: "Hawkeye",       desc: "Hit 10000 perfect taps",  icon: "🦅", reward: 1000, check: { s, _, _ in s.perfectTaps >= 10000 }),

        // Mode-specific
        Achievement(id: "sudden_500",   title: "Death Wish",      desc: "Score 500 in Sudden Death",   icon: "💀", reward: 300,  check: { _, g, _ in (g?.mode == .suddenDeath) && (g?.score ?? 0) >= 500 }),
        Achievement(id: "sudden_1000",  title: "Death Master",    desc: "Score 1000 in Sudden Death",  icon: "☠️", reward: 750,  check: { _, g, _ in (g?.mode == .suddenDeath) && (g?.score ?? 0) >= 1000 }),
        Achievement(id: "timed_3000",   title: "Speed Scorer",    desc: "Score 3000 in Timed mode",    icon: "⏱️", reward: 500,  check: { _, g, _ in (g?.mode == .timed) && (g?.score ?? 0) >= 3000 }),
        Achievement(id: "endless_5000", title: "Endurance King",  desc: "Score 5000 in Endless mode",  icon: "♾️", reward: 500,  check: { _, g, _ in (g?.mode == .endless) && (g?.score ?? 0) >= 5000 }),

        // Additional game milestones
        Achievement(id: "games_2500", title: "Addict",           desc: "Play 2500 games",         icon: "🎮", reward: 2000, check: { s, _, _ in s.totalGames >= 2500 }),
        Achievement(id: "games_5000", title: "No Life",          desc: "Play 5000 games",         icon: "👑", reward: 5000, check: { s, _, _ in s.totalGames >= 5000 }),

        // Additional duel
        Achievement(id: "duel_100",   title: "Duel God",         desc: "Win 100 duels",           icon: "⚔️", reward: 2000, check: { s, _, _ in s.duelWins >= 100 }),

        // First achievements
        Achievement(id: "first_combo_5", title: "First Combo",   desc: "Reach a 5x combo",        icon: "🔗", reward: 25,  check: { s, g, _ in (g?.maxCombo ?? s.highestCombo) >= 5 }),
    ]

    static func check(gameData: GameData, profile: PlayerProfile) -> [Achievement] {
        let unlocked = Set(profile.achievements)
        return all.filter { ach in
            !unlocked.contains(ach.id) &&
            ach.check(profile.stats, gameData, profile)
        }
    }
}
