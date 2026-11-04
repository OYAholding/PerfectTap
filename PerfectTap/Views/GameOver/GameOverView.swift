import SwiftUI

@inline(__always)
private func gameOverAdFlowLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[GameOverAdFlow] \(message())")
    #endif
}

// MARK: - GameOverView (ported from GameOver.jsx)
struct GameOverView: View {
    let result: GameResult
    @EnvironmentObject var router: AppRouter

    @State private var xpBarProgress: Double = 0
    @State private var isWatchingAd = false
    @State private var didDoubleCoins = false

    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()

    @MainActor
    private func navigateWithPostGameInterstitial(_ navigation: @escaping () -> Void) {
        gameOverAdFlowLog(
            "navigateWithPostGameInterstitial called: mode=\(result.mode.rawValue), isDuelSession=\(result.isDuelSession)"
        )
        Task { @MainActor in
            let didShowInterstitial = await AdManager.shared.maybeShowPostGameInterstitial(isDuelSession: result.isDuelSession)
            gameOverAdFlowLog("maybeShowPostGameInterstitial returned didShow=\(didShowInterstitial). Executing navigation closure.")
            navigation()
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            // Background glow
            Circle()
                .fill(Color(red: 0.37, green: 0.14, blue: 0.75).opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(y: -100)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer(minLength: 40)

                    // Title
                    titleSection

                    // Score card
                    scoreCard

                    // XP bar
                    if result.xpEarned > 0 {
                        xpSection
                    }

                    // New achievements
                    if !result.newAchievements.isEmpty {
                        achievementsSection
                    }

                    // Buttons
                    actionButtons

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.4)) {
                xpBarProgress = profile.xp > 0 ? Double(profile.xp) / Double(GameConfig.xpForLevel(profile.level)) : 0
            }
        }
    }

    // MARK: - Title
    private var titleSection: some View {
        VStack(spacing: 8) {
            Text(titleText)
                .font(.system(size: 13, weight: .bold))
                .tracking(4)
                .foregroundColor(.white.opacity(0.4))

            if result.isNewBest {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 12))
                    Text("NEW BEST!")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundColor(.yellow)
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.yellow.opacity(0.1))
                .overlay(Capsule().stroke(Color.yellow.opacity(0.3)))
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Score card
    private var scoreCard: some View {
        VStack(spacing: 24) {
            if result.mode.trackScore {
                // Big score
                VStack(spacing: 4) {
                    Text("Your Score")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.4))

                    Text("\(result.score)")
                        .font(.system(size: 72, weight: .black, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.63, green: 0.45, blue: 0.98), Color(red: 0.22, green: 0.80, blue: 0.98)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Stats grid
                HStack(spacing: 12) {
                    statCard(icon: "trophy.fill", label: "BEST", value: "\(profile.bestScore(for: result.mode))", color: .yellow)
                    statCard(icon: "bolt.fill",  label: "COMBO", value: "×\(result.maxCombo)",                   color: Color(red: 0.22, green: 0.82, blue: 0.98))
                    if result.coinsEarned > 0 {
                        statCard(icon: "dollarsign.circle.fill", label: "EARNED", value: "+\(result.coinsEarned)", color: Color(red: 0.98, green: 0.73, blue: 0.26))
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Text("NO SCORE MODE")
                        .font(.system(size: 18, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.75))
                    Text("This mode is about consistency and focus, not points.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                    statCard(icon: "bolt.fill", label: "MAX COMBO", value: "×\(result.maxCombo)", color: Color(red: 0.22, green: 0.82, blue: 0.98))
                }
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.08)))
        )
    }

    private func statCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
    }

    // MARK: - XP section
    private var xpSection: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(Color(red: 0.63, green: 0.45, blue: 0.98))
                        .font(.system(size: 14))
                    Text("Level \(profile.level)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Text("+\(result.xpEarned) XP")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.63, green: 0.45, blue: 0.98))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05)).frame(height: 8)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * xpBarProgress, height: 8)
                        .animation(.easeOut(duration: 0.8).delay(0.4), value: xpBarProgress)
                }
            }
            .frame(height: 8)

            if let newLevel = result.leveledUp {
                Text("🎉 LEVEL UP! Level \(newLevel)!")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.yellow)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08)))
        )
    }

    // MARK: - Achievements
    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "medal.fill")
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                    .font(.system(size: 14))
                Text("NEW ACHIEVEMENT\(result.newAchievements.count > 1 ? "S" : "")!")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2)
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            }

            ForEach(result.newAchievements) { ach in
                HStack(spacing: 8) {
                    Text(ach.icon).font(.system(size: 18))
                    Text(ach.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("+\(ach.reward) 🪙")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.2)))
        )
    }

    // MARK: - Action buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Double Coins (watch ad)
            if result.coinsEarned > 0 && !didDoubleCoins {
                Button {
                    guard !isWatchingAd else { return }
                    isWatchingAd = true
                    Task {
                        let watched = await AdManager.shared.showRewardedAd(placement: .doubleCoins)
                        isWatchingAd = false
                        if watched {
                            didDoubleCoins = true
                            EconomyManager.shared.addCoins(result.coinsEarned, source: .gameplay)
                            profile = PlayerProfile.load() ?? PlayerProfile()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isWatchingAd {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 16))
                            Text("DOUBLE COINS (+\(result.coinsEarned))")
                                .font(.system(size: 15, weight: .black))
                                .tracking(1)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.98, green: 0.65, blue: 0.0), Color(red: 0.98, green: 0.45, blue: 0.0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color(red: 0.98, green: 0.55, blue: 0.0).opacity(0.3), radius: 12)
                }
                .disabled(isWatchingAd)
            } else if didDoubleCoins {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                    Text("COINS DOUBLED! +\(result.coinsEarned)")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2)))
                .cornerRadius(16)
            }

            // Share
            ShareLink(item: "I scored \(result.score) in PerfectTap \(result.mode.displayName) mode! Can you beat it? 🎯") {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                    Text("SHARE SCORE")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(1)
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
                .cornerRadius(16)
            }

            if result.isDuelSession {
                // Duel session: show results instead of play again
                Button {
                    gameOverAdFlowLog("Button tapped: SEE DUEL RESULTS")
                    navigateWithPostGameInterstitial {
                        gameOverAdFlowLog("Navigation start: SEE DUEL RESULTS")
                        router.popToRoot()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            router.push(.duelResults)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("SEE DUEL RESULTS")
                            .font(.system(size: 18, weight: .black))
                            .tracking(2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.98, green: 0.45, blue: 0.10)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.3), radius: 20)
                }
            } else {
                Button {
                    gameOverAdFlowLog("Button tapped: PLAY AGAIN")
                    navigateWithPostGameInterstitial {
                        gameOverAdFlowLog("Navigation start: PLAY AGAIN")
                        // Pop to root first, then push game — prevents unbounded nav stack growth
                        DuelContext.clear()
                        router.popToRoot()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            router.push(.game(result.mode))
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                        Text("PLAY AGAIN")
                            .font(.system(size: 18, weight: .black))
                            .tracking(2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.47, green: 0.18, blue: 0.85), Color(red: 0.20, green: 0.55, blue: 0.96)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color(red: 0.47, green: 0.18, blue: 0.85).opacity(0.3), radius: 20)
                }
            }

            Button {
                gameOverAdFlowLog("Button tapped: HOME")
                navigateWithPostGameInterstitial {
                    gameOverAdFlowLog("Navigation start: HOME")
                    DuelContext.clear()
                    router.popToRoot()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16))
                    Text("HOME")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Title text per mode
    private var titleText: String {
        switch result.mode {
        case .suddenDeath:   return "DEAD."
        case .comboFrenzy:   return "FRENZY OVER!"
        case .timed:         return "TIME'S UP!"
        case .endless:       return "ENDLESS RUN OVER"
        case .rush:          return "TIME'S UP!"
        case .precision:     return "PRECISION ENDED"
        case .hardcoreCombo: return "COMBO BROKEN!"
        case .mirror:        return "MIRRORED OUT"
        case .invisibleZone: return "REVEALED"
        case .chaos:         return "CHAOS ENDED"
        case .tinyWindow:    return "WINDOW CLOSED"
        case .focus:         return "FOCUS SESSION COMPLETE"
        case .zen:           return "SESSION COMPLETE"
        default:             return "GAME OVER"
        }
    }
}
