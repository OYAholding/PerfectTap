import Foundation

// MARK: - Daily Quest (ported from DailyQuests.jsx logic)
struct DailyQuest: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let difficulty: Difficulty
    let goal: Int
    let metric: Metric
    let reward: Int   // coins

    var progress: Int = 0
    var completed: Bool = false
    var rewardClaimed: Bool = false

    enum Difficulty: String, Codable {
        case easy, medium, hard
    }

    enum Metric: String, Codable {
        case games, score, combo, coins, perfects, duels, suddenScore
    }

    var progressFraction: Double {
        guard goal > 0 else { return completed ? 1.0 : 0.0 }
        return min(1.0, Double(progress) / Double(goal))
    }
}

// MARK: - Quest generation (seeded by calendar day)
extension DailyQuest {
    static func generateForToday() -> [DailyQuest] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let seed = (components.year ?? 2024) * 10000 + (components.month ?? 1) * 100 + (components.day ?? 1)
        return generate(seed: seed)
    }

    static func generate(seed: Int) -> [DailyQuest] {
        // Deterministic quest pool based on seed
        let pool: [DailyQuest] = [
            DailyQuest(id: "q_games_3",   title: "Game Starter",    description: "Play 3 games",             icon: "🎮", difficulty: .easy,   goal: 3,    metric: .games,       reward: 40),
            DailyQuest(id: "q_games_5",   title: "Keep Playing",    description: "Play 5 games",             icon: "🕹️", difficulty: .easy,   goal: 5,    metric: .games,       reward: 50),
            DailyQuest(id: "q_score_500", title: "Score Runner",    description: "Score 500 in one game",    icon: "⭐", difficulty: .easy,   goal: 500,  metric: .score,       reward: 50),
            DailyQuest(id: "q_score_1000",title: "Score Hunter",    description: "Score 1000 in one game",   icon: "🌟", difficulty: .medium, goal: 1000, metric: .score,       reward: 80),
            DailyQuest(id: "q_score_2000",title: "High Scorer",     description: "Score 2000 in one game",   icon: "💫", difficulty: .hard,   goal: 2000, metric: .score,       reward: 150),
            DailyQuest(id: "q_combo_10",  title: "Chain Builder",   description: "Reach a 10x combo",        icon: "🔗", difficulty: .easy,   goal: 10,   metric: .combo,       reward: 40),
            DailyQuest(id: "q_combo_20",  title: "Combo King",      description: "Reach a 20x combo",        icon: "⛓️", difficulty: .medium, goal: 20,   metric: .combo,       reward: 100),
            DailyQuest(id: "q_combo_30",  title: "Combo Master",    description: "Reach a 30x combo",        icon: "💥", difficulty: .hard,   goal: 30,   metric: .combo,       reward: 200),
            DailyQuest(id: "q_coins_100", title: "Coin Farmer",     description: "Earn 100 coins today",     icon: "🪙", difficulty: .easy,   goal: 100,  metric: .coins,       reward: 50),
            DailyQuest(id: "q_perfect_20",title: "Perfect Touch",   description: "Hit 20 perfect taps",      icon: "🎯", difficulty: .medium, goal: 20,   metric: .perfects,    reward: 80),
            DailyQuest(id: "q_duel_1",    title: "Duel Starter",    description: "Complete 1 duel",          icon: "⚔️", difficulty: .medium, goal: 1,    metric: .duels,       reward: 100),
            DailyQuest(id: "q_sudden_300",title: "Death Defyer",    description: "Score 300 in Sudden Death",icon: "💀", difficulty: .hard,   goal: 300,  metric: .suddenScore, reward: 200),
        ]

        // Pick 3 quests based on seed (deterministic)
        var rng = seed
        var indices: [Int] = []
        while indices.count < 3 {
            rng = (rng &* 1664525 &+ 1013904223) & 0x7fffffff
            let idx = rng % pool.count
            if !indices.contains(idx) { indices.append(idx) }
        }

        return indices.map { pool[$0] }
    }

    // MARK: - Persistence (keyed by date so quests reset daily)
    private static var todayKey: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "perfecttap_quests_\(df.string(from: Date()))"
    }

    static func save(quests: [DailyQuest]) {
        if let data = try? JSONEncoder().encode(quests) {
            UserDefaults.standard.set(data, forKey: todayKey)
        }
    }

    static func loadSaved() -> [DailyQuest]? {
        guard let data = UserDefaults.standard.data(forKey: todayKey),
              let quests = try? JSONDecoder().decode([DailyQuest].self, from: data)
        else { return nil }
        return quests
    }

    // MARK: - Progress update after a game
    static func updateProgress(
        quests: inout [DailyQuest],
        score: Int,
        maxCombo: Int,
        mode: GameMode,
        coinsEarned: Int,
        perfects: Int
    ) {
        for i in quests.indices {
            guard !quests[i].completed else { continue }
            switch quests[i].metric {
            case .games:
                quests[i].progress += 1
            case .score:
                quests[i].progress = max(quests[i].progress, score)
            case .combo:
                quests[i].progress = max(quests[i].progress, maxCombo)
            case .coins:
                quests[i].progress += coinsEarned
            case .perfects:
                quests[i].progress += perfects
            case .duels:
                if mode == .duel { quests[i].progress += 1 }
            case .suddenScore:
                if mode == .suddenDeath {
                    quests[i].progress = max(quests[i].progress, score)
                }
            }
            if quests[i].progress >= quests[i].goal {
                quests[i].completed = true
            }
        }
    }
}
