import SwiftUI

// MARK: - AchievementsView
struct AchievementsView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()

    private var unlocked: Set<String> { Set(profile.achievements) }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar(title: "ACHIEVEMENTS") { router.pop() }

                // Progress summary
                HStack {
                    Text("\(unlocked.count) / \(Achievement.all.count) Unlocked")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("🏅 \(totalRewardEarned) coins earned")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(Achievement.all) { ach in
                            AchievementRow(ach: ach, isUnlocked: unlocked.contains(ach.id))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var totalRewardEarned: Int {
        Achievement.all.filter { unlocked.contains($0.id) }.reduce(0) { $0 + $1.reward }
    }
}

private struct AchievementRow: View {
    let ach: Achievement
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(ach.icon)
                .font(.system(size: 28))
                .opacity(isUnlocked ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 4) {
                Text(ach.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isUnlocked ? .white : .white.opacity(0.4))
                Text(ach.desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(isUnlocked ? 0.5 : 0.25))
            }

            Spacer()

            if isUnlocked {
                Text("+\(ach.reward) 🪙")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isUnlocked ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                    isUnlocked ? Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.2) : Color.white.opacity(0.05)
                ))
        )
    }
}
