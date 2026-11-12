import SwiftUI

// MARK: - All navigable routes
enum AppRoute: Hashable {
    case home
    case modeSelect
    case game(GameMode)
    case gameOver(GameResult)
    case duelLobby
    case duelResults
    case achievements
    case challenges
    case quests
    case dailyRewards
    case wheel
    case seasonPass
    case profile
    case shop
    case friends
    case friendDetail(String)   // friend UID
    case leaderboard
    case settings
}

// Make GameResult hashable (used as nav value).
// Uses a unique ID so NavigationStack never confuses two different game results.
extension GameResult: Hashable {
    static func == (lhs: GameResult, rhs: GameResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - AppRouter
@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppRoute] = []

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        _ = path.popLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}

// MARK: - View for each route (used in navigationDestination)
extension AppRoute {
    @ViewBuilder
    func destinationView() -> some View {
        switch self {
        case .home:           HomeView()
        case .modeSelect:     ModeSelectView()
        case .game(let mode): GameView(mode: mode)
        case .gameOver(let r):GameOverView(result: r)
        case .duelLobby:      DuelLobbyView()
        case .duelResults:    DuelResultsView()
        case .achievements:   AchievementsView()
        case .challenges:     ChallengesView()
        case .quests:         DailyQuestsView()
        case .dailyRewards:   DailyRewardsView()
        case .wheel:          LuckyWheelView()
        case .seasonPass:     SeasonPassView()
        case .profile:        ProfileView()
        case .shop:           ShopView()
        case .friends:        FriendsView()
        case .friendDetail(let uid): FriendDetailView(friendUID: uid)
        case .leaderboard:    LeaderboardView()
        case .settings:       GameSettingsView()
        }
    }
}
