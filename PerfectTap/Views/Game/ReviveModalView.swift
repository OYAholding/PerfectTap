import SwiftUI

// MARK: - ReviveModal (shown when player runs out of lives)
// Wired to AdManager with fail-open behavior:
// - no-ads users continue instantly
// - if ad inventory is unavailable, continue without blocking gameplay
// Limit: 1 revive per game session (handled by GameViewModel.hasUsedReviveRef).
// No daily limit — players can revive once per game, every game.
struct ReviveModalView: View {
    let mode: GameMode
    let onRevive: () -> Void
    let onDecline: () -> Void

    @State private var isLoadingAd = false
    /// Whether the user has purchased no-ads (gets free revives)
    private var hasNoAds: Bool {
        (PlayerProfile.load() ?? PlayerProfile()).noAds
    }

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
                                Image(systemName: hasNoAds ? "heart.fill" : "play.rectangle.fill")
                                    .font(.system(size: 16))
                                Text(hasNoAds ? "CONTINUE — FREE" : "WATCH AD TO CONTINUE")
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
        if hasNoAds {
            onRevive()
            return
        }
        if !AdManager.shared.isAdReady(for: .reviveReward) {
            // Fail-open policy: don't block continuation when ad inventory is unavailable.
            onRevive()
            return
        }
        isLoadingAd = true

        Task {
            let watched = await AdManager.shared.showRewardedAd(placement: .reviveReward)
            isLoadingAd = false

            if watched {
                onRevive()
            } else {
                // Ad failed mid-flow (dismissed/failed to present). Continue anyway.
                onRevive()
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
