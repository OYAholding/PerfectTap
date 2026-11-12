import SwiftUI

// MARK: - DailyQuestsView (ported from DailyQuests.jsx)
struct DailyQuestsView: View {
    @EnvironmentObject var router: AppRouter
    @State private var quests: [DailyQuest] = []

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar(title: "DAILY QUESTS") { router.pop() }

                Text("Refreshes at midnight")
                    .font(.system(size: 11))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(quests) { quest in
                            QuestCard(quest: quest)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear { quests = DailyQuest.loadSaved() ?? DailyQuest.generateForToday() }
    }
}

private struct QuestCard: View {
    let quest: DailyQuest

    var diffColor: Color {
        switch quest.difficulty {
        case .easy:   return Color(red: 0.22, green: 0.82, blue: 0.49)
        case .medium: return Color(red: 0.98, green: 0.73, blue: 0.26)
        case .hard:   return Color(red: 0.95, green: 0.24, blue: 0.37)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(quest.icon).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(quest.description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quest.difficulty.rawValue.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(1)
                        .foregroundColor(diffColor)
                    Text("+\(quest.reward) 🪙")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                    Capsule()
                        .fill(quest.completed ? Color(red: 0.22, green: 0.82, blue: 0.49) : diffColor)
                        .frame(width: geo.size.width * quest.progressFraction, height: 6)
                        .animation(.easeOut, value: quest.progressFraction)
                }
            }
            .frame(height: 6)

            HStack {
                Text(quest.completed ? "✓ Complete!" : "\(quest.progress) / \(quest.goal)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(quest.completed ? Color(red: 0.22, green: 0.82, blue: 0.49) : .white.opacity(0.4))
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(quest.completed ? Color(red: 0.22, green: 0.82, blue: 0.49).opacity(0.06) : Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(
                    quest.completed ? Color(red: 0.22, green: 0.82, blue: 0.49).opacity(0.25) : Color.white.opacity(0.08)
                ))
        )
    }
}
