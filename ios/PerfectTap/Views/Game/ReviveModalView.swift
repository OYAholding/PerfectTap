import SwiftUI

// MARK: - ReviveModal (shown when player runs out of lives)
// Wired to AdManager:
// - if ad inventory is unavailable, no rewarded revive is granted
// - an ad closed before the reward does NOT revive (it used to)
// Duels never show this modal (GameViewModel disables revive for duel runs).
// Limit: 1 revive per game session (handled by GameViewModel.hasUsedReviveRef).
// Daily placement cap is checked against a server-verified day.
struct ReviveModalView: View {
    let mode: GameMode
    let onRevive: () -> Void
    let onDecline: () -> Void

    @State private var isLoadingAd = false
    @State private var adUnavailableMessage: String? = nil
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            VStack(spacing: 24) {
                Text("💀")
                    .font(.system(size: 64))

                VStack(spacing: 8) {
                    Text("CONTINUE?")
                        .font(.system(size: 24, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white)

                    Text(reviveDescription)
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    // Main revive button
                    Button {
                        attemptRevive()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingAd {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 16))
                                Text("WATCH OPTIONAL AD TO CONTINUE")
                                    .font(.system(size: 15, weight: .black))
                                    .tracking(1)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.18, green: 0.78, blue: 0.97)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .disabled(isLoadingAd)

                    if let message = adUnavailableMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.orange.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }

                    Button(action: onDecline) {
                        Text("Give Up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .disabled(isLoadingAd)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.08)))
            )
            .padding(32)
        }
    }

    private func attemptRevive() {
        isLoadingAd = true
        adUnavailableMessage = nil

        Task {
            let verification = await Backend.shared.authoritativeDayVerification(forceRefresh: true)
            guard let day = verification.dayKey else {
                isLoadingAd = false
                adUnavailableMessage = "Connect to verify today's optional reward limit."
                return
            }
            guard RewardClaimLimiter.shared.canClaim(.revive, day: day, userID: Backend.shared.currentUID) else {
                isLoadingAd = false
                adUnavailableMessage = "Today's revive rewards have been used."
                return
            }
            guard AdManager.shared.isAdReady(for: .reviveReward) else {
                isLoadingAd = false
                adUnavailableMessage = "No optional ad is available right now."
                return
            }
            let watched = await AdManager.shared.showRewardedAd(placement: .reviveReward)
            isLoadingAd = false

            if watched {
                if RewardClaimLimiter.shared.record(.revive, day: day, userID: Backend.shared.currentUID) {
                    onRevive()
                }
            } else {
                // Closed early or failed mid-flow: no reward. The modal stays so
                // the player can try again or give up.
                adUnavailableMessage = "The ad didn't finish, so no revive this time."
            }
        }
    }

    private var reviveDescription: String {
        switch mode {
        case .rush: return "Restore lives and keep rushing. No time bonus."
        default:
            let lives = mode.initialLives ?? 3
            return "Restore \(lives) lives and keep your score."
        }
    }
}
