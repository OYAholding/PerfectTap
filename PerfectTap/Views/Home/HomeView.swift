import SwiftUI

// MARK: - HomeView (ported from Home.jsx)
struct HomeView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var themeManager: ThemeManager
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var showTutorial = !UserDefaults.standard.bool(forKey: "perfecttap_tutorial_done")
    @State private var isWatchingAd = false
    @State private var showAdReward = false
    @State private var pendingFriendRequests = 0
    @State private var pendingDuelInvitations = 0
    @State private var incomingRequestsRaw: [FriendRequest] = []
    @State private var incomingDuelInvitesRaw: [DuelInvitation] = []
    @State private var outgoingDuelInvitesRaw: [DuelInvitation] = []
    @State private var incomingReqListener: Any? = nil
    @State private var incomingInviteListener: Any? = nil
    @State private var outgoingInviteListener: Any? = nil
    @State private var badgeRefreshTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()

            // Background glows
            Circle()
                .fill(Color(red: 0.37, green: 0.14, blue: 0.75).opacity(0.08))
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(x: 0, y: -200)
            Circle()
                .fill(Color(red: 0.14, green: 0.64, blue: 0.85).opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: 0, y: 200)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    // Logo
                    logoSection

                    // Stats badges
                    statsBadges
                        .padding(.bottom, 28)

                    // Quick action row: Daily, Wheel, Duel, Friends, Challenges
                    quickActions
                        .padding(.bottom, 16)

                    // PLAY button
                    playButton
                        .padding(.bottom, 16)

                    // Secondary: Quests + Achievements
                    secondaryRow(
                        left:  ("scroll.fill", "QUESTS",  { router.push(.quests) }),
                        right: ("medal.fill",  "ACHIEVE", { router.push(.achievements) })
                    )
                    .padding(.bottom, 10)

                    // Tertiary: Season + Settings
                    secondaryRow(
                        left:  ("crown.fill",  "SEASON",   { router.push(.seasonPass) }),
                        right: ("gearshape.fill","SETTINGS",{ router.push(.settings) })
                    )
                    .padding(.bottom, 10)

                    // Profile, Leaderboard, Shop
                    secondaryRow(
                        left:  ("person.fill",     "PROFILE",     { router.push(.profile) }),
                        right: ("chart.bar.fill",  "LEADERBOARD", { router.push(.leaderboard) })
                    )
                    .padding(.bottom, 10)

                    secondaryRow(
                        left:  ("cart.fill",  "SHOP", { router.push(.shop) }),
                        right: ("questionmark.circle.fill", "HOW TO PLAY", {
                            showTutorial = true
                        })
                    )

                    // Watch Ad for Coins
                    watchAdForCoinsButton
                        .padding(.bottom, 10)

                    // Tagline
                    Text("Test your precision")
                        .font(.system(size: 11))
                        .tracking(4)
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.top, 32)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView { showTutorial = false }
        }
        .navigationBarHidden(true)
        .onAppear {
            profile = PlayerProfile.load() ?? PlayerProfile()
            themeManager.current = AppTheme.named(profile.equippedTheme)
            startBadgeListeners()
            // Firebase refresh in background
            Task {
                if let updated = await FirebaseService.shared.loadProfile() {
                    profile = updated
                    themeManager.current = AppTheme.named(profile.equippedTheme)
                }
            }
        }
        .onDisappear {
            stopBadgeListeners()
        }
    }

    // MARK: - Logo section
    private var logoSection: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(colors: [Color(red: 0.59, green: 0.28, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 80, height: 80)
                .overlay(Text("🎯").font(.system(size: 36)))
                .shadow(color: Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.3), radius: 20)
                .padding(.bottom, 8)

            Text("PERFECT")
                .font(.system(size: 48, weight: .black))
                .foregroundColor(.white)
            Text("TAP")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.63, green: 0.45, blue: 0.98), Color(red: 0.22, green: 0.82, blue: 0.98)],
                                   startPoint: .leading, endPoint: .trailing)
                )

            if !profile.username.isEmpty {
                let avatarEmoji = ShopItem.avatars.first(where: { $0.id == profile.equippedAvatar })?.icon ?? "😊"
                Text("\(avatarEmoji) \(profile.username) • Lv.\(profile.level)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Stats badges
    private var statsBadges: some View {
        HStack(spacing: 12) {
            if profile.bestClassic > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundColor(.yellow)
                    Text("Best: ").foregroundColor(.white.opacity(0.6)) + Text("\(profile.bestClassic)").fontWeight(.bold).foregroundColor(.white)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .overlay(Capsule().stroke(Color.white.opacity(0.10)))
                .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: 12)).foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                Text("\(profile.coins)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.1))
            .overlay(Capsule().stroke(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.2)))
            .clipShape(Capsule())
        }
    }

    // MARK: - Quick action row (5 icons)
    private var quickActions: some View {
        HStack(spacing: 8) {
            quickActionButton(icon: "gift.fill",        label: "DAILY",     color: Color(red: 0.98, green: 0.45, blue: 0.0))    { router.push(.dailyRewards) }
            quickActionButton(icon: "circle.dotted",    label: "WHEEL",     color: Color(red: 0.98, green: 0.73, blue: 0.26))   { router.push(.wheel) }
            quickActionButton(icon: "bolt.fill",        label: "DUEL",      color: Color(red: 0.95, green: 0.24, blue: 0.37))   { router.push(.duelLobby) }
            quickActionBadgeButton(icon: "person.2.fill", label: "FRIENDS", color: Color(red: 0.22, green: 0.53, blue: 0.98), badge: pendingFriendRequests + pendingDuelInvitations) { router.push(.friends) }
            quickActionButton(icon: "flag.fill",        label: "CHALLENGE", color: Color(red: 0.22, green: 0.82, blue: 0.98))   { router.push(.challenges) }
        }
    }

    private func quickActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 8, weight: .black)).tracking(0.5)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.25)))
            .cornerRadius(14)
        }
    }

    // MARK: - PLAY button
    private var playButton: some View {
        Button { router.push(.modeSelect) } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.system(size: 22, weight: .bold))
                Text("PLAY")
                    .font(.system(size: 22, weight: .black))
                    .tracking(4)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.47, green: 0.18, blue: 0.85), Color(red: 0.18, green: 0.55, blue: 0.96)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(24)
            .shadow(color: Color(red: 0.47, green: 0.18, blue: 0.85).opacity(0.3), radius: 24)
        }
    }

    // MARK: - 2-column secondary row
    private func secondaryRow(left: (String, String, () -> Void), right: (String, String, () -> Void)) -> some View {
        HStack(spacing: 10) {
            secondaryButton(icon: left.0, label: left.1, action: left.2)
            secondaryButton(icon: right.0, label: right.1, action: right.2)
        }
    }

    // MARK: - Watch Ad for Coins
    private var watchAdForCoinsButton: some View {
        Button {
            guard !isWatchingAd else { return }
            isWatchingAd = true
            Task {
                let watched = await AdManager.shared.showRewardedAd(placement: .doubleCoins)
                isWatchingAd = false
                if watched {
                    let reward = 25
                    EconomyManager.shared.addCoins(reward, source: .dailyReward)
                    profile = PlayerProfile.load() ?? PlayerProfile()
                    showAdReward = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showAdReward = false
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                if isWatchingAd {
                    ProgressView().tint(Color(red: 0.98, green: 0.73, blue: 0.26))
                } else if showAdReward {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                    Text("+25 COINS!")
                        .font(.system(size: 14, weight: .black))
                        .tracking(1)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                    Text("WATCH AD — FREE COINS")
                        .font(.system(size: 14, weight: .black))
                        .tracking(1)
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.2)))
            .cornerRadius(16)
        }
        .disabled(isWatchingAd || showAdReward)
    }

    private func quickActionBadgeButton(icon: String, label: String, color: Color, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: icon).font(.system(size: 16))
                    Text(label).font(.system(size: 8, weight: .black)).tracking(0.5)
                }
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.25)))
                .cornerRadius(14)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(red: 0.95, green: 0.24, blue: 0.37))
                        .clipShape(Capsule())
                        .offset(x: -4, y: 4)
                }
            }
        }
    }

    private func secondaryButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 10, weight: .black)).tracking(1)
            }
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
            .cornerRadius(16)
        }
    }

    // MARK: - Home badge listeners
    private func startBadgeListeners() {
        stopBadgeListeners()
        recomputeActionableBadgeCount()

        incomingReqListener = FirebaseService.shared.listenIncomingFriendRequests { requests in
            incomingRequestsRaw = requests
            recomputeActionableBadgeCount()
        }
        incomingInviteListener = FirebaseService.shared.listenIncomingDuelInvitations { invites in
            incomingDuelInvitesRaw = invites
            recomputeActionableBadgeCount()
        }
        outgoingInviteListener = FirebaseService.shared.listenOutgoingDuelInvitations { invites in
            outgoingDuelInvitesRaw = invites
            recomputeActionableBadgeCount()
        }
    }

    private func stopBadgeListeners() {
        badgeRefreshTask?.cancel()
        badgeRefreshTask = nil

        FirebaseService.shared.removeListener(incomingReqListener)
        FirebaseService.shared.removeListener(incomingInviteListener)
        FirebaseService.shared.removeListener(outgoingInviteListener)
        incomingReqListener = nil
        incomingInviteListener = nil
        outgoingInviteListener = nil

        incomingRequestsRaw = []
        incomingDuelInvitesRaw = []
        outgoingDuelInvitesRaw = []
        pendingFriendRequests = 0
        pendingDuelInvitations = 0
    }

    private func recomputeActionableBadgeCount() {
        badgeRefreshTask?.cancel()
        let incomingRequests = incomingRequestsRaw
        let incomingDuels = incomingDuelInvitesRaw
        let outgoingDuels = outgoingDuelInvitesRaw

        badgeRefreshTask = Task {
            let counts = await FirebaseService.shared.loadActionablePendingCounts(
                incomingFriendRequests: incomingRequests,
                incomingDuelInvitations: incomingDuels,
                outgoingDuelInvitations: outgoingDuels
            )
            guard !Task.isCancelled else { return }
            pendingFriendRequests = counts.friendRequests
            pendingDuelInvitations = counts.duelInvitations
        }
    }
}
