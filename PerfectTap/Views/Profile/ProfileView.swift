import SwiftUI

// MARK: - ProfileView (ported from Profile.jsx)
struct ProfileView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()

    private var avatarEmoji: String {
        ShopItem.avatars.first(where: { $0.id == profile.equippedAvatar })?.icon ?? "😊"
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "PROFILE") { router.pop() }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Avatar + name
                        VStack(spacing: 10) {
                            Circle()
                                .fill(LinearGradient(colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                                .overlay(Text(avatarEmoji).font(.system(size: 36)))
                            Text(profile.username).font(.system(size: 22, weight: .black)).foregroundColor(.white)
                            Text("Lv.\(profile.level)  •  \(profile.coins) 🪙")
                                .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                        }

                        // XP bar
                        VStack(spacing: 6) {
                            HStack {
                                Text("Level \(profile.level)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text("\(profile.xp) / \(GameConfig.xpForLevel(profile.level)) XP").font(.system(size: 12)).foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.05)).frame(height: 6)
                                    Capsule()
                                        .fill(LinearGradient(colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * Double(profile.xp) / Double(GameConfig.xpForLevel(profile.level)), height: 6)
                                }
                            }.frame(height: 6)
                        }

                        // Best scores grid
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BEST SCORES").font(.system(size: 10, weight: .black)).tracking(3).foregroundColor(.white.opacity(0.4))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                bestScoreCard("🎯", "Classic",     profile.bestClassic)
                                bestScoreCard("🔄", "Endless",     profile.bestEndless)
                                bestScoreCard("⏱️", "Timed",       profile.bestTimed)
                                bestScoreCard("💀", "Sudden Death",profile.bestSudden)
                                bestScoreCard("🔗", "Combo Frenzy",profile.bestComboFrenzy)
                            }
                        }

                        // Stats
                        VStack(alignment: .leading, spacing: 10) {
                            Text("STATS").font(.system(size: 10, weight: .black)).tracking(3).foregroundColor(.white.opacity(0.4))
                            statsRow("Games Played",     "\(profile.stats.totalGames)")
                            statsRow("Duel Wins",        "\(profile.stats.duelWins)")
                            statsRow("Perfect Taps",     "\(profile.stats.perfectTaps)")
                            statsRow("Highest Combo",    "×\(profile.stats.highestCombo)")
                            statsRow("Total Coins Earned","\(profile.stats.totalCoinsEarned)")
                        }

                        // Recent matches
                        if !profile.scoreHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("RECENT MATCHES").font(.system(size: 10, weight: .black)).tracking(3).foregroundColor(.white.opacity(0.4))
                                ForEach(profile.scoreHistory) { entry in
                                    HStack {
                                        Text(String(entry.date.prefix(10)))
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.4))
                                        Spacer()
                                        Text("\(entry.score)")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
                                }
                            }
                        }

                        // Friend code
                        VStack(spacing: 6) {
                            Text("FRIEND CODE").font(.system(size: 10, weight: .black)).tracking(3).foregroundColor(.white.opacity(0.4))
                            Text(profile.friendCode)
                                .font(.system(size: 24, weight: .black, design: .monospaced))
                                .tracking(6).foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func bestScoreCard(_ icon: String, _ label: String, _ score: Int) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 20))
            Text("\(score)").font(.system(size: 20, weight: .black, design: .monospaced)).foregroundColor(.white)
            Text(label).font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }

    private func statsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }
}
