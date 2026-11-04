import SwiftUI

// MARK: - LeaderboardView
struct LeaderboardView: View {
    @EnvironmentObject var router: AppRouter
    @State private var selectedMode: GameMode = .classic
    @State private var selectedTab: Int = 0  // 0 = Global, 1 = Friends
    @State private var entries: [(username: String, score: Int)] = []
    @State private var isLoading = false
    @State private var currentRequestID: UInt64 = 0
    @State private var activeLoadTask: Task<Void, Never>? = nil

    private let modes: [GameMode] = [.classic, .endless, .timed, .suddenDeath, .comboFrenzy]

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "LEADERBOARD") { router.pop() }

                // Global / Friends tabs
                HStack(spacing: 0) {
                    ForEach(["GLOBAL", "FRIENDS"], id: \.self) { tab in
                        let idx = tab == "GLOBAL" ? 0 : 1
                        Button {
                            selectedTab = idx
                            startBoardLoad()
                        } label: {
                            Text(tab)
                                .font(.system(size: 12, weight: .black)).tracking(2)
                                .foregroundColor(selectedTab == idx ? .white : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedTab == idx ? Color.white.opacity(0.08) : Color.clear)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Mode picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(modes, id: \.self) { mode in
                            Button {
                                selectedMode = mode
                                startBoardLoad()
                            } label: {
                                Text(mode.displayName)
                                    .font(.system(size: 12, weight: .bold)).tracking(1)
                                    .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.4))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(selectedMode == mode ? Color.white.opacity(0.12) : Color.clear)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)

                if isLoading {
                    ProgressView().tint(.white.opacity(0.5)).padding(.top, 40)
                } else if entries.isEmpty {
                    Text("No scores yet. Be the first!")
                        .font(.system(size: 13)).foregroundColor(.white.opacity(0.3)).padding(.top, 40)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { i, entry in
                                LeaderboardRow(rank: i + 1, username: entry.username, score: entry.score)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear { startBoardLoad() }
        .onDisappear { activeLoadTask?.cancel() }
    }

    private func startBoardLoad() {
        activeLoadTask?.cancel()
        currentRequestID &+= 1
        let requestID = currentRequestID
        let mode = selectedMode
        let tab = selectedTab

        isLoading = true
        activeLoadTask = Task {
            defer {
                if requestID == currentRequestID {
                    isLoading = false
                }
            }

            let loadedEntries: [(username: String, score: Int)]
            if tab == 0 {
                loadedEntries = await FirebaseService.shared.loadLeaderboard(mode: mode)
            } else {
                let profile = PlayerProfile.load() ?? PlayerProfile()
                loadedEntries = await FirebaseService.shared.loadFriendsLeaderboard(friendUIDs: profile.friends, mode: mode)
            }

            guard !Task.isCancelled else { return }
            guard requestID == currentRequestID, selectedMode == mode, selectedTab == tab else { return }
            entries = loadedEntries
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let username: String
    let score: Int

    var rankColor: Color {
        switch rank {
        case 1: return Color(red: 0.98, green: 0.73, blue: 0.26)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return Color.white.opacity(0.3)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(rank <= 3 ? ["🥇","🥈","🥉"][rank-1] : "#\(rank)")
                .font(.system(size: rank <= 3 ? 22 : 14, weight: .bold))
                .foregroundColor(rankColor)
                .frame(width: 36)

            Text(username)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text("\(score)")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(rank <= 3 ? rankColor.opacity(0.06) : Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(rank <= 3 ? rankColor.opacity(0.2) : Color.white.opacity(0.06)))
        )
    }
}
