import SwiftUI

// MARK: - DuelResultsView
struct DuelResultsView: View {
    @EnvironmentObject var router: AppRouter
    @State private var duel: Duel? = nil
    @State private var listener: Any? = nil

    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var statsRecorded = false
    private var duelId: String { DuelContext.load()?.duelId ?? "" }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            VStack(spacing: 24) {
                navBar(title: "DUEL RESULTS") { router.popToRoot() }

                if let duel = duel, duel.isComplete {
                    resultContent(duel)
                } else {
                    // Waiting for opponent to finish
                    VStack(spacing: 16) {
                        ProgressView().tint(Color(red: 0.95, green: 0.24, blue: 0.37)).scaleEffect(1.5)
                        Text("Waiting for opponent to finish…")
                            .font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 60)
                }
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            guard !duelId.isEmpty else { return }
            listener = FirebaseService.shared.listenDuel(duelId: duelId) { d in
                duel = d
                recordDuelStatsIfNeeded(d)
            }
        }
        .onDisappear {
            FirebaseService.shared.removeDuelListener(listener)
            DuelContext.clear()
        }
    }

    /// Records win/loss/tie stats exactly once when duel completes.
    private func recordDuelStatsIfNeeded(_ duel: Duel?) {
        guard let duel = duel, duel.isComplete, !statsRecorded else { return }
        statsRecorded = true

        let result = duel.result(forUID: profile.uid)
        switch result {
        case .win:  profile.stats.duelWins += 1
        case .loss: profile.stats.duelLosses += 1
        case .tie:  profile.stats.duelTies += 1
        case .unknown: break
        }
        profile.save()
        Task { await FirebaseService.shared.saveProfile(profile) }
    }

    private func resultContent(_ duel: Duel) -> some View {
        VStack(spacing: 20) {
            let isHost = duel.hostId == profile.uid
            let myScore = isHost ? duel.hostScore : duel.guestScore
            let theirScore = isHost ? duel.guestScore : duel.hostScore
            let myName = isHost ? duel.hostName : (duel.guestName ?? "Opponent")
            let theirName = isHost ? (duel.guestName ?? "Opponent") : duel.hostName
            let myAvatar = isHost ? duel.hostAvatar : duel.guestAvatar
            let theirAvatar = isHost ? duel.guestAvatar : duel.hostAvatar
            let myResult = duel.result(forUID: profile.uid)

            // Result badge
            Group {
                switch myResult {
                case .win:
                    Text("🏆 YOU WIN!")
                        .font(.system(size: 32, weight: .black)).tracking(4)
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                case .loss:
                    Text("😔 You Lose")
                        .font(.system(size: 28, weight: .black)).tracking(3)
                        .foregroundColor(.white.opacity(0.6))
                case .tie:
                    Text("🤝 TIE!")
                        .font(.system(size: 28, weight: .black)).tracking(3)
                        .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.98))
                default:
                    EmptyView()
                }
            }

            // Score comparison
            HStack(spacing: 0) {
                scoreColumn(name: myName, avatar: myAvatar, score: myScore ?? 0, isMe: true, isWinner: myResult == .win)
                Text("VS").font(.system(size: 18, weight: .black)).foregroundColor(.white.opacity(0.3)).padding(.horizontal, 16)
                scoreColumn(name: theirName, avatar: theirAvatar, score: theirScore ?? 0, isMe: false, isWinner: myResult == .loss)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08))))
            .padding(.horizontal, 20)

            // Buttons
            VStack(spacing: 12) {
                Button { router.push(.duelLobby) } label: {
                    Text("REMATCH")
                        .font(.system(size: 16, weight: .black)).tracking(2)
                        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(LinearGradient(colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.98, green: 0.45, blue: 0.10)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(16)
                }
                Button { router.popToRoot() } label: {
                    Text("HOME")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func scoreColumn(name: String, avatar: String?, score: Int, isMe: Bool, isWinner: Bool) -> some View {
        VStack(spacing: 6) {
            let emoji = ShopItem.avatars.first(where: { $0.id == (avatar ?? "") })?.icon ?? "😊"
            Text(emoji).font(.system(size: 28))
            Text(isMe ? "You" : name)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isMe ? Color(red: 0.63, green: 0.45, blue: 0.98) : .white.opacity(0.5))
            Text("\(score)")
                .font(.system(size: 40, weight: .black, design: .monospaced))
                .foregroundColor(isWinner ? Color(red: 0.98, green: 0.73, blue: 0.26) : .white)
            if isWinner {
                Image(systemName: "trophy.fill").font(.system(size: 16)).foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
