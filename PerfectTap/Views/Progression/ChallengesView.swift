import SwiftUI

// MARK: - Challenge model
struct Challenge: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let difficulty: String
    let rewardLabel: String
}

// MARK: - Challenge completion + reward parsing
extension Challenge {
    static func checkCompletion(
        challenge: Challenge,
        score: Int,
        maxCombo: Int,
        mode: GameMode,
        missCount: Int,
        perfectsInFirst20: Int,
        speedLevel: Int,
        elapsedSeconds: Double
    ) -> Bool {
        switch challenge.id {
        case "c1":  return score >= 500  && mode == .classic
        case "c2":  return score >= 1000 && mode == .classic
        case "c3":  return score >= 2000 && mode == .classic
        case "c4":  return score >= 5000 && mode == .classic
        case "c5":  return maxCombo >= 10
        case "c6":  return maxCombo >= 30
        case "c7":  return perfectsInFirst20 >= 10
        case "c8":  return score >= 1000 && missCount == 0
        case "c9":  return score >= 500 && speedLevel >= 10
        case "c10": return score >= 1000 && elapsedSeconds <= 30
        default:    return false
        }
    }

    struct ChallengeReward {
        var coins: Int = 0
        var theme: String? = nil
    }

    static func parseReward(_ label: String) -> ChallengeReward {
        if label.lowercased().contains("theme") {
            let name = label.replacingOccurrences(of: " Theme", with: "").lowercased()
            return ChallengeReward(coins: 0, theme: "theme_\(name)")
        }
        let digits = label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return ChallengeReward(coins: Int(digits) ?? 0)
    }
}

// MARK: - All challenges (ported from Challenges.jsx CHALLENGES array)
extension Challenge {
    static let all: [Challenge] = [
        Challenge(id: "c1",  title: "First Blood",     description: "Score 500 in Classic",             icon: "⭐", difficulty: "Easy",   rewardLabel: "50 🪙"),
        Challenge(id: "c2",  title: "Centurion",       description: "Score 1000 in Classic",            icon: "💯", difficulty: "Medium", rewardLabel: "100 🪙"),
        Challenge(id: "c3",  title: "Two Thousand",    description: "Score 2000 in Classic",            icon: "🌟", difficulty: "Medium", rewardLabel: "200 🪙"),
        Challenge(id: "c4",  title: "Godlike",         description: "Score 5000 in Classic",            icon: "🔱", difficulty: "Hard",   rewardLabel: "500 🪙"),
        Challenge(id: "c5",  title: "Chain Gang",      description: "Reach a 10× combo",               icon: "🔗", difficulty: "Easy",   rewardLabel: "75 🪙"),
        Challenge(id: "c6",  title: "Combo Deity",     description: "Reach a 30× combo",               icon: "⛓️", difficulty: "Hard",   rewardLabel: "300 🪙"),
        Challenge(id: "c7",  title: "Perfectionist",   description: "Hit 10 perfects in first 20 taps", icon: "🎯", difficulty: "Medium", rewardLabel: "150 🪙"),
        Challenge(id: "c8",  title: "Untouchable",     description: "Score 1000 without missing",       icon: "🛡️", difficulty: "Hard",   rewardLabel: "400 🪙"),
        Challenge(id: "c9",  title: "Speed Demon",     description: "Score 500 at Level 10+",           icon: "💨", difficulty: "Hard",   rewardLabel: "Fire Theme"),
        Challenge(id: "c10", title: "Speed Run",       description: "Score 1000 in 30 seconds",         icon: "⏱️", difficulty: "Hard",   rewardLabel: "250 🪙"),
    ]
}

// MARK: - ChallengesView
struct ChallengesView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar(title: "CHALLENGES") { router.pop() }

                Text("\(profile.stats.totalGames > 0 ? "Active" : "No") challenges. Play Classic to progress.")
                    .font(.system(size: 11)).tracking(2)
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Challenge.all) { challenge in
                            ChallengeRow(challenge: challenge,
                                         isDone: (profile.completedChallenges.contains(challenge.id)),
                                         isActive: profile.activeChallenge == challenge.id) {
                                activateChallenge(challenge)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func activateChallenge(_ c: Challenge) {
        profile = EconomyManager.shared.updateProfile { profile in
            profile.activeChallenge = c.id
        }
    }
}

private struct ChallengeRow: View {
    let challenge: Challenge
    let isDone: Bool
    let isActive: Bool
    let onActivate: () -> Void

    var diffColor: Color {
        switch challenge.difficulty {
        case "Easy":   return Color(red: 0.22, green: 0.82, blue: 0.49)
        case "Medium": return Color(red: 0.98, green: 0.73, blue: 0.26)
        default:       return Color(red: 0.95, green: 0.24, blue: 0.37)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(challenge.icon).font(.system(size: 24)).opacity(isDone ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title).font(.system(size: 14, weight: .bold))
                    .foregroundColor(isDone ? .white : .white.opacity(0.7))
                Text(challenge.description).font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                HStack(spacing: 6) {
                    Text(challenge.difficulty)
                        .font(.system(size: 9, weight: .black)).tracking(1)
                        .foregroundColor(diffColor)
                    Text("•").foregroundColor(.white.opacity(0.2))
                    Text(challenge.rewardLabel).font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                }
            }

            Spacer()

            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20)).foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
            } else if isActive {
                Text("ACTIVE").font(.system(size: 9, weight: .black)).tracking(1)
                    .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.98))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(red: 0.22, green: 0.82, blue: 0.98).opacity(0.15))
                    .overlay(Capsule().stroke(Color(red: 0.22, green: 0.82, blue: 0.98).opacity(0.3)))
                    .clipShape(Capsule())
            } else {
                Button("Start", action: onActivate)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.1))
                    .overlay(Capsule().stroke(Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.3)))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDone ? Color(red: 0.22, green: 0.82, blue: 0.49).opacity(0.05) : Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                    isDone ? Color(red: 0.22, green: 0.82, blue: 0.49).opacity(0.2) : Color.white.opacity(0.07)
                ))
        )
    }
}
