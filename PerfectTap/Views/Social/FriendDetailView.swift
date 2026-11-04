import SwiftUI

// MARK: - FriendDetailView
struct FriendDetailView: View {
    @EnvironmentObject var router: AppRouter
    let friendUID: String

    @State private var friendProfile: PlayerProfile? = nil
    @State private var isLoading = true
    @State private var errorMsg: String? = nil
    @State private var isInviting = false
    @State private var pendingInvite: DuelInvitation? = nil
    @State private var pendingInviteDuel: Duel? = nil
    @State private var pendingInviteState: DuelInvitePresentationState = .history
    @State private var inviteSent = false
    @State private var selectedDuelMode: GameMode = .duel
    @State private var inviteListener: Any? = nil

    private var avatarEmoji: String {
        guard let fp = friendProfile else { return "😊" }
        return ShopItem.avatars.first(where: { $0.id == fp.equippedAvatar })?.icon ?? "😊"
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: friendProfile?.username.uppercased() ?? "FRIEND") { router.pop() }

                if isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if let fp = friendProfile {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            profileHeader(fp)
                            statsSection(fp)
                            bestScoresSection(fp)
                            duelStatsSection(fp)
                            duelInviteButton(fp)

                            if let err = errorMsg {
                                Text(err).font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                } else {
                    Spacer()
                    Text("Could not load profile")
                        .font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            Task { await loadData() }
            startInviteListener()
        }
        .onDisappear {
            FirebaseService.shared.removeListener(inviteListener)
            inviteListener = nil
        }
    }

    // MARK: - Profile Header
    private func profileHeader(_ fp: PlayerProfile) -> some View {
        VStack(spacing: 10) {
            Text(avatarEmoji).font(.system(size: 56))

            Text(fp.username)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.white)

            Text("Level \(fp.level)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            // Equipped cosmetics display
            HStack(spacing: 12) {
                if !fp.equippedBadge.isEmpty {
                    let badgeEmoji = ShopItem.badges.first(where: { $0.id == fp.equippedBadge })?.icon ?? ""
                    if !badgeEmoji.isEmpty {
                        Text(badgeEmoji).font(.system(size: 18))
                    }
                }
                let themeItem = ShopItem.themes.first(where: { $0.id == fp.equippedTheme })
                if let theme = themeItem, theme.id != "default" {
                    Text(theme.icon).font(.system(size: 18))
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Stats
    private func statsSection(_ fp: PlayerProfile) -> some View {
        VStack(spacing: 8) {
            sectionTitle("STATS")
            HStack(spacing: 8) {
                statCard(label: "Games", value: "\(fp.stats.totalGames)", color: Color(red: 0.22, green: 0.53, blue: 0.98))
                statCard(label: "Perfect Taps", value: "\(fp.stats.perfectTaps)", color: Color(red: 0.59, green: 0.28, blue: 0.98))
                statCard(label: "Best Combo", value: "\(fp.stats.highestCombo)", color: Color(red: 0.98, green: 0.73, blue: 0.26))
            }
        }
    }

    private func bestScoresSection(_ fp: PlayerProfile) -> some View {
        VStack(spacing: 8) {
            sectionTitle("BEST SCORES")
            let scores: [(String, Int)] = [
                ("Classic", fp.bestClassic),
                ("Endless", fp.bestEndless),
                ("Timed", fp.bestTimed),
                ("Sudden Death", fp.bestSudden),
                ("Combo Frenzy", fp.bestComboFrenzy),
            ].filter { $0.1 > 0 }

            if scores.isEmpty {
                Text("No scores yet")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                    .padding(.vertical, 8)
            } else {
                ForEach(scores, id: \.0) { name, score in
                    HStack {
                        Text(name).font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text("\(score)").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(10)
                }
            }
        }
    }

    private func duelStatsSection(_ fp: PlayerProfile) -> some View {
        VStack(spacing: 8) {
            sectionTitle("DUEL RECORD")
            HStack(spacing: 8) {
                statCard(label: "Wins", value: "\(fp.stats.duelWins)", color: .green)
                statCard(label: "Losses", value: "\(fp.stats.duelLosses)", color: .red)
                statCard(label: "Ties", value: "\(fp.stats.duelTies)", color: .orange)
            }
        }
    }

    // MARK: - Duel Mode Picker
    /// All competitive modes except zen — available for duel invites
    private static let duelModes: [GameMode] = GameMode.allCases.filter { $0 != .zen }

    private var duelModePicker: some View {
        VStack(spacing: 8) {
            sectionTitle("DUEL MODE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.duelModes, id: \.self) { mode in
                        Button {
                            selectedDuelMode = mode
                        } label: {
                            HStack(spacing: 4) {
                                Text(mode.emoji).font(.system(size: 14))
                                Text(mode.displayName.uppercased())
                                    .font(.system(size: 10, weight: .black)).tracking(0.5)
                            }
                            .foregroundColor(selectedDuelMode == mode ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selectedDuelMode == mode ? Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.4) : Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedDuelMode == mode ? Color(red: 0.59, green: 0.28, blue: 0.98).opacity(0.6) : Color.white.opacity(0.08)))
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Duel Invite Button
    private func duelInviteButton(_ fp: PlayerProfile) -> some View {
        Group {
            if let existing = pendingInvite {
                if pendingInviteState == .readyToPlay {
                    Button {
                        Task { await launchPendingInviteIfActionable(existing) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill").foregroundColor(.white)
                            Text("READY TO PLAY!")
                                .font(.system(size: 14, weight: .black)).tracking(1)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(16)
                    }
                } else if pendingInviteState == .waitingForOpponent {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color(red: 0.95, green: 0.24, blue: 0.37))
                        Text("YOU FINISHED — WAITING FOR OPPONENT...")
                            .font(.system(size: 14, weight: .black)).tracking(1)
                            .foregroundColor(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.2)))
                    .cornerRadius(16)
                } else if pendingInviteState == .history {
                    duelModePicker
                    inviteButtonUI(fp)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color(red: 0.95, green: 0.24, blue: 0.37))
                        Text("DUEL INVITE PENDING...")
                            .font(.system(size: 14, weight: .black)).tracking(1)
                            .foregroundColor(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.2)))
                    .cornerRadius(16)
                }
            } else if inviteSent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("DUEL INVITE SENT!")
                        .font(.system(size: 14, weight: .black)).tracking(1)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.3)))
                .cornerRadius(16)
            } else {
                duelModePicker
                inviteButtonUI(fp)
            }
        }
        .padding(.top, 8)
    }

    private func inviteButtonUI(_ fp: PlayerProfile) -> some View {
        Button {
            Task { await sendInvite(fp) }
        } label: {
            HStack(spacing: 10) {
                if isInviting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "bolt.fill").font(.system(size: 18))
                    Text("CHALLENGE TO DUEL")
                        .font(.system(size: 14, weight: .black)).tracking(1)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.24, blue: 0.37), Color(red: 0.85, green: 0.14, blue: 0.27)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.3), radius: 12)
        }
        .disabled(isInviting)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .black)).tracking(2)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.15)))
        .cornerRadius(12)
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        friendProfile = await FirebaseService.shared.loadPlayerProfile(uid: friendUID)
        isLoading = false
    }

    private func startInviteListener() {
        inviteListener = FirebaseService.shared.listenOutgoingDuelInvitation(toUID: friendUID) { invite in
            Task { @MainActor in
                pendingInvite = invite
                await refreshPendingInviteState()
            }
        }
    }

    @MainActor
    private func refreshPendingInviteState() async {
        guard let invite = pendingInvite else {
            pendingInviteDuel = nil
            pendingInviteState = .history
            return
        }

        if invite.status == .accepted || invite.status == .inProgress {
            pendingInviteDuel = await FirebaseService.shared.loadDuel(duelId: invite.duelId)
        } else {
            pendingInviteDuel = nil
        }

        pendingInviteState = invite.presentationState(
            currentUID: FirebaseService.shared.currentUID,
            duel: pendingInviteDuel,
            isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
        )
    }

    private func launchPendingInviteIfActionable(_ invite: DuelInvitation) async {
        let duel = await FirebaseService.shared.loadDuel(duelId: invite.duelId)
        let state = invite.presentationState(
            currentUID: FirebaseService.shared.currentUID,
            duel: duel,
            isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
        )
        guard state == .readyToPlay else {
            errorMsg = "This duel is no longer playable."
            await refreshPendingInviteState()
            return
        }

        DuelInviteLaunchReceiptStore.markHandled(inviteId: invite.id, duelId: invite.duelId)
        DuelContext.save(duelId: invite.duelId, role: .host, mode: invite.mode)
        _ = await FirebaseService.shared.markDuelInvitationInProgress(invite.id)
        await refreshPendingInviteState()
        router.push(.game(invite.mode))
    }

    private func sendInvite(_ fp: PlayerProfile) async {
        isInviting = true; errorMsg = nil
        do {
            let invite = try await FirebaseService.shared.sendDuelInvitation(
                toUID: fp.uid, toUsername: fp.username, toAvatar: fp.avatar, mode: selectedDuelMode
            )
            pendingInvite = invite
            pendingInviteDuel = nil
            pendingInviteState = .pending
            inviteSent = true
        } catch {
            errorMsg = error.localizedDescription
        }
        isInviting = false
    }
}
