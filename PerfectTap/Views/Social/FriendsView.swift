import SwiftUI

// MARK: - FriendsView
struct FriendsView: View {
    @EnvironmentObject var router: AppRouter
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()

    // Friend list
    @State private var friendProfiles: [PlayerProfile] = []

    // Requests
    @State private var incomingRequests: [FriendRequest] = []
    @State private var outgoingRequests: [FriendRequest] = []

    // Duel invitations
    @State private var incomingDuelInvitesRaw: [DuelInvitation] = []
    @State private var outgoingDuelInvitesRaw: [DuelInvitation] = []
    @State private var activeIncomingDuelInvites: [DuelInvitation] = []
    @State private var activeOutgoingDuelInvites: [OutgoingDuelInviteItem] = []
    @State private var duelHistoryItems: [DuelHistoryItem] = []
    @State private var duelRefreshTask: Task<Void, Never>? = nil

    // Add friend
    @State private var addCode = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var successMsg: String? = nil

    // Action loading states
    @State private var processingRequestId: String? = nil
    @State private var processingInviteId: String? = nil

    // Listeners (scoped to view visibility)
    @State private var incomingReqListener: Any? = nil
    @State private var outgoingReqListener: Any? = nil
    @State private var incomingInviteListener: Any? = nil
    @State private var outgoingInviteListener: Any? = nil

    // Tabs
    @State private var selectedTab: Tab = .friends
    enum Tab: String, CaseIterable {
        case friends = "Friends"
        case requests = "Requests"
        case duels = "Duels"
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "FRIENDS") { router.pop() }

                // My friend code
                VStack(spacing: 6) {
                    Text("Your Friend Code")
                        .font(.system(size: 11)).tracking(2).foregroundColor(.white.opacity(0.4))
                    Text(profile.friendCode)
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .tracking(6).foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
                    Text("Share this with friends to connect")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                }
                .padding(.bottom, 16)

                // Add friend input
                HStack(spacing: 10) {
                    TextField("Enter friend's code", text: $addCode)
                        .autocapitalization(.allCharacters).autocorrectionDisabled()
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .tracking(3).foregroundColor(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10)))
                        .cornerRadius(12)
                        .onChange(of: addCode) { newValue in addCode = String(newValue.prefix(6)).uppercased() }

                    Button {
                        Task { await sendRequest() }
                    } label: {
                        if isLoading {
                            ProgressView().tint(.white).frame(width: 48, height: 48)
                        } else {
                            Image(systemName: "person.badge.plus").font(.system(size: 18)).foregroundColor(.white)
                                .frame(width: 48, height: 48)
                        }
                    }
                    .background(Color(red: 0.22, green: 0.53, blue: 0.98))
                    .cornerRadius(12)
                    .disabled(addCode.count < 6 || isLoading)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                if let err = errorMsg { Text(err).font(.system(size: 12)).foregroundColor(.red.opacity(0.8)).padding(.bottom, 6) }
                if let ok = successMsg { Text(ok).font(.system(size: 12)).foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49)).padding(.bottom, 6) }

                // Tab selector
                tabSelector
                    .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 8)

                Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 20).padding(.bottom, 8)

                // Tab content
                ScrollView(showsIndicators: false) {
                    switch selectedTab {
                    case .friends:   friendsListSection
                    case .requests:  requestsSection
                    case .duels:     duelInvitesSection
                    }
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            startListeners()
            startDuelRefreshTask()
            Task {
                await loadFriends()
                await refreshDuelLists()
            }
        }
        .onDisappear {
            stopDuelRefreshTask()
            stopListeners()
        }
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let count = badgeCount(for: tab)
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: selectedTab == tab ? .black : .medium))
                            .tracking(0.5)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color(red: 0.95, green: 0.24, blue: 0.37))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedTab == tab ? Color.white.opacity(0.08) : Color.clear)
                    .cornerRadius(10)
                }
            }
        }
    }

    private func badgeCount(for tab: Tab) -> Int {
        switch tab {
        case .friends: return 0
        case .requests: return incomingRequests.count
        case .duels:
            return activeIncomingDuelInvites.count + activeOutgoingDuelInvites.filter { $0.presentationState == .readyToPlay }.count
        }
    }

    // MARK: - Friends List
    private var friendsListSection: some View {
        VStack(spacing: 8) {
            if friendProfiles.isEmpty {
                Text("No friends yet. Send a request using their code!")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.3)).multilineTextAlignment(.center)
                    .padding(.horizontal, 40).padding(.top, 24)
            } else {
                ForEach(friendProfiles, id: \.uid) { fp in
                    Button {
                        router.push(.friendDetail(fp.uid))
                    } label: {
                        FriendRow(profile: fp)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Requests Section
    private var requestsSection: some View {
        VStack(spacing: 12) {
            if !incomingRequests.isEmpty {
                sectionHeader("INCOMING")
                ForEach(incomingRequests, id: \.id) { req in
                    IncomingRequestRow(
                        request: req,
                        isProcessing: processingRequestId == req.id,
                        onAccept: { Task { await acceptRequest(req) } },
                        onReject: { Task { await rejectRequest(req) } }
                    )
                }
            }

            if !outgoingRequests.isEmpty {
                sectionHeader("SENT")
                ForEach(outgoingRequests, id: \.id) { req in
                    OutgoingRequestRow(
                        request: req,
                        isProcessing: processingRequestId == req.id,
                        onCancel: { Task { await cancelRequest(req) } }
                    )
                }
            }

            if incomingRequests.isEmpty && outgoingRequests.isEmpty {
                Text("No pending requests")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.3))
                    .padding(.top, 24)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Duel Invites Section
    private var duelInvitesSection: some View {
        VStack(spacing: 12) {
            if !activeIncomingDuelInvites.isEmpty || !activeOutgoingDuelInvites.isEmpty {
                sectionHeader("ACTIVE DUELS")

                ForEach(activeIncomingDuelInvites, id: \.id) { invite in
                    IncomingDuelRow(
                        invitation: invite,
                        isProcessing: processingInviteId == invite.id,
                        onAccept: { Task { await acceptDuelInvite(invite) } },
                        onReject: { Task { await rejectDuelInvite(invite) } }
                    )
                }

                ForEach(activeOutgoingDuelInvites) { item in
                    OutgoingDuelRow(
                        invitation: item.invitation,
                        presentationState: item.presentationState,
                        isProcessing: processingInviteId == item.invitation.id,
                        onCancel: { Task { await cancelDuelInvite(item.invitation) } },
                        onReady: { Task { await launchOutgoingInvite(item.invitation) } }
                    )
                }
            }

            if !duelHistoryItems.isEmpty {
                sectionHeader("DUEL HISTORY")
                ForEach(duelHistoryItems) { item in
                    DuelHistoryRow(item: item)
                }
            }

            if activeIncomingDuelInvites.isEmpty && activeOutgoingDuelInvites.isEmpty && duelHistoryItems.isEmpty {
                Text("No duels yet")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.3))
                    .padding(.top, 24)
            }
        }
        .padding(.horizontal, 20)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .black)).tracking(2)
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func sendRequest() async {
        isLoading = true; errorMsg = nil; successMsg = nil
        do {
            try await Backend.shared.sendFriendRequest(friendCode: addCode)
            successMsg = "Friend request sent!"
            addCode = ""
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    private func acceptRequest(_ req: FriendRequest) async {
        processingRequestId = req.id
        do {
            try await Backend.shared.acceptFriendRequest(req)
            await loadFriends()
        } catch {
            errorMsg = error.localizedDescription
        }
        processingRequestId = nil
    }

    private func rejectRequest(_ req: FriendRequest) async {
        processingRequestId = req.id
        try? await Backend.shared.rejectFriendRequest(req)
        processingRequestId = nil
    }

    private func cancelRequest(_ req: FriendRequest) async {
        processingRequestId = req.id
        try? await Backend.shared.cancelFriendRequest(req)
        processingRequestId = nil
    }

    private func acceptDuelInvite(_ invite: DuelInvitation) async {
        processingInviteId = invite.id
        do {
            try await Backend.shared.acceptDuelInvitation(invite)
            // Save DuelContext and route directly to game — skip lobby
            DuelContext.save(duelId: invite.duelId, role: .guest, mode: invite.mode)
            router.push(.game(invite.mode))
        } catch {
            errorMsg = error.localizedDescription
        }
        processingInviteId = nil
    }

    private func rejectDuelInvite(_ invite: DuelInvitation) async {
        processingInviteId = invite.id
        try? await Backend.shared.rejectDuelInvitation(invite)
        processingInviteId = nil
    }

    private func cancelDuelInvite(_ invite: DuelInvitation) async {
        processingInviteId = invite.id
        try? await Backend.shared.cancelDuelInvitation(invite)
        await refreshDuelLists()
        processingInviteId = nil
    }

    private func launchOutgoingInvite(_ invite: DuelInvitation) async {
        processingInviteId = invite.id
        defer { processingInviteId = nil }

        let duel = await Backend.shared.loadDuel(duelId: invite.duelId)
        let state = invite.presentationState(
            currentUID: Backend.shared.currentUID,
            duel: duel,
            isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
        )
        guard state == .readyToPlay else {
            errorMsg = "This duel is no longer playable."
            await refreshDuelLists()
            return
        }

        DuelInviteLaunchReceiptStore.markHandled(inviteId: invite.id, duelId: invite.duelId)
        DuelContext.save(duelId: invite.duelId, role: .host, mode: invite.mode)
        _ = await Backend.shared.markDuelInvitationInProgress(invite.id)
        await refreshDuelLists()
        router.push(.game(invite.mode))
    }

    private func historyReason(for invite: DuelInvitation, duel: Duel?, isHandled: Bool) -> String {
        if isHandled { return "Handled" }
        if invite.isExpired || invite.status == .expired { return "Expired" }
        switch invite.status {
        case .cancelled:
            return "Cancelled"
        case .rejected:
            return "Rejected"
        case .accepted, .inProgress:
            if duel?.isComplete == true { return "Completed" }
            return "No longer active"
        case .pending:
            return "No longer active"
        case .expired:
            return "Expired"
        }
    }

    @MainActor
    private func refreshDuelLists() async {
        let incomingInvites = incomingDuelInvitesRaw
        let outgoingInvites = outgoingDuelInvitesRaw
        let outgoingDuelIds = outgoingInvites
            .filter { $0.status == .accepted || $0.status == .inProgress }
            .map(\.duelId)
        let duelsById = await Backend.shared.loadDuels(duelIds: outgoingDuelIds)
        let currentUID = Backend.shared.currentUID

        var nextIncoming: [DuelInvitation] = []
        var nextOutgoing: [OutgoingDuelInviteItem] = []
        var history: [DuelHistoryItem] = []

        for invite in incomingInvites {
            if invite.isExpired {
                history.append(DuelHistoryItem(invitation: invite, direction: .incoming, reason: "Expired"))
            } else {
                nextIncoming.append(invite)
            }
        }

        for invite in outgoingInvites {
            let duel = duelsById[invite.duelId]
            let handled = DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
            let state = invite.presentationState(currentUID: currentUID, duel: duel, isHandled: handled)
            if state == .history {
                history.append(DuelHistoryItem(invitation: invite, direction: .outgoing, reason: historyReason(for: invite, duel: duel, isHandled: handled)))
            } else {
                nextOutgoing.append(OutgoingDuelInviteItem(invitation: invite, presentationState: state))
            }
        }

        activeIncomingDuelInvites = nextIncoming
        activeOutgoingDuelInvites = nextOutgoing
        duelHistoryItems = history.sorted { $0.createdAt > $1.createdAt }
    }

    private func startDuelRefreshTask() {
        stopDuelRefreshTask()
        duelRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await refreshDuelLists()
            }
        }
    }

    private func stopDuelRefreshTask() {
        duelRefreshTask?.cancel()
        duelRefreshTask = nil
    }

    // MARK: - Data Loading

    private func loadFriends() async {
        profile = PlayerProfile.load() ?? PlayerProfile()
        let friendUIDs = await Backend.shared.loadFriendUIDs()
        friendProfiles = await Backend.shared.loadFriendProfiles(uids: friendUIDs)
    }

    // MARK: - Listeners (scoped to view visibility)

    private func startListeners() {
        incomingReqListener = Backend.shared.listenIncomingFriendRequests { requests in
            incomingRequests = requests
        }
        outgoingReqListener = Backend.shared.listenOutgoingFriendRequests { requests in
            outgoingRequests = requests
        }
        incomingInviteListener = Backend.shared.listenIncomingDuelInvitations { invites in
            incomingDuelInvitesRaw = invites
            Task { await refreshDuelLists() }
        }
        outgoingInviteListener = Backend.shared.listenOutgoingDuelInvitations { invites in
            outgoingDuelInvitesRaw = invites
            Task { await refreshDuelLists() }
        }
    }

    private func stopListeners() {
        Backend.shared.removeListener(incomingReqListener)
        Backend.shared.removeListener(outgoingReqListener)
        Backend.shared.removeListener(incomingInviteListener)
        Backend.shared.removeListener(outgoingInviteListener)
        incomingReqListener = nil
        outgoingReqListener = nil
        incomingInviteListener = nil
        outgoingInviteListener = nil
        incomingDuelInvitesRaw = []
        outgoingDuelInvitesRaw = []
        activeIncomingDuelInvites = []
        activeOutgoingDuelInvites = []
        duelHistoryItems = []
    }
}

// MARK: - Row Components

private struct OutgoingDuelInviteItem: Identifiable {
    let invitation: DuelInvitation
    let presentationState: DuelInvitePresentationState

    var id: String { invitation.id }
}

private struct DuelHistoryItem: Identifiable {
    enum Direction {
        case incoming
        case outgoing
    }

    let invitation: DuelInvitation
    let direction: Direction
    let reason: String

    var id: String {
        let prefix = direction == .incoming ? "in" : "out"
        return "\(prefix)_\(invitation.id)"
    }

    var createdAt: Date { invitation.createdAt }
}

private struct FriendRow: View {
    let profile: PlayerProfile
    private var avatarEmoji: String {
        ShopItem.avatars.first(where: { $0.id == profile.equippedAvatar })?.icon ?? "😊"
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(avatarEmoji).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.username).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text("Lv.\(profile.level)  •  Best: \(profile.bestClassic)")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.2))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }
}

private struct IncomingRequestRow: View {
    let request: FriendRequest
    let isProcessing: Bool
    let onAccept: () -> Void
    let onReject: () -> Void

    private var avatarEmoji: String {
        ShopItem.avatars.first(where: { $0.id == request.fromAvatar })?.icon ?? "😊"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(avatarEmoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromUsername).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Text("wants to be friends").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            if isProcessing {
                ProgressView().tint(.white)
            } else {
                Button(action: onReject) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.red.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.15)).cornerRadius(8)
                }
                Button(action: onAccept) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.green)
                        .frame(width: 32, height: 32)
                        .background(Color.green.opacity(0.15)).cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }
}

private struct OutgoingRequestRow: View {
    let request: FriendRequest
    let isProcessing: Bool
    let onCancel: () -> Void

    private var avatarEmoji: String {
        ShopItem.avatars.first(where: { $0.id == request.toAvatar })?.icon ?? "😊"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(avatarEmoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(request.toUsername).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Text("pending...").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            if isProcessing {
                ProgressView().tint(.white)
            } else {
                Button(action: onCancel) {
                    Text("CANCEL").font(.system(size: 10, weight: .black)).tracking(0.5)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08)).cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }
}

private struct IncomingDuelRow: View {
    let invitation: DuelInvitation
    let isProcessing: Bool
    let onAccept: () -> Void
    let onReject: () -> Void

    private var avatarEmoji: String {
        ShopItem.avatars.first(where: { $0.id == invitation.fromAvatar })?.icon ?? "😊"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(avatarEmoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.fromUsername).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                if invitation.isExpired {
                    Text("expired").font(.system(size: 11)).foregroundColor(.red.opacity(0.6))
                } else {
                    Text("challenges you to \(invitation.mode.displayName)!")
                        .font(.system(size: 11)).foregroundColor(Color(red: 0.95, green: 0.24, blue: 0.37).opacity(0.8))
                }
            }
            Spacer()
            if invitation.isExpired {
                Text("EXPIRED").font(.system(size: 10, weight: .black)).foregroundColor(.red.opacity(0.5))
            } else if isProcessing {
                ProgressView().tint(.white)
            } else {
                Button(action: onReject) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.red.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.15)).cornerRadius(8)
                }
                Button(action: onAccept) {
                    Text("FIGHT").font(.system(size: 10, weight: .black)).tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(red: 0.95, green: 0.24, blue: 0.37)).cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }
}

private struct OutgoingDuelRow: View {
    let invitation: DuelInvitation
    let presentationState: DuelInvitePresentationState
    let isProcessing: Bool
    let onCancel: () -> Void
    let onReady: () -> Void

    private var avatarEmoji: String {
        ShopItem.avatars.first(where: { $0.id == invitation.toAvatar })?.icon ?? "😊"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(avatarEmoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.toUsername).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                if presentationState == .readyToPlay {
                    Text("\(invitation.mode.displayName) — ready to play!").font(.system(size: 11)).foregroundColor(.green)
                } else if presentationState == .waitingForOpponent {
                    Text("\(invitation.mode.displayName) — you finished, waiting for opponent…")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                } else {
                    Text("\(invitation.mode.displayName) — waiting...").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer()
            if isProcessing {
                ProgressView().tint(.white)
            } else if presentationState == .readyToPlay {
                Button(action: onReady) {
                    Text("PLAY").font(.system(size: 10, weight: .black)).tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.green).cornerRadius(8)
                }
            } else if presentationState == .pending {
                Button(action: onCancel) {
                    Text("CANCEL").font(.system(size: 10, weight: .black)).tracking(0.5)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.08)).cornerRadius(8)
                }
            } else {
                Text("WAITING")
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
    }
}

private struct DuelHistoryRow: View {
    let item: DuelHistoryItem

    private var avatarEmoji: String {
        switch item.direction {
        case .incoming:
            return ShopItem.avatars.first(where: { $0.id == item.invitation.fromAvatar })?.icon ?? "😊"
        case .outgoing:
            return ShopItem.avatars.first(where: { $0.id == item.invitation.toAvatar })?.icon ?? "😊"
        }
    }

    private var title: String {
        switch item.direction {
        case .incoming:
            return item.invitation.fromUsername
        case .outgoing:
            return item.invitation.toUsername
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(avatarEmoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                Text("\(item.invitation.mode.displayName) — \(item.reason.lowercased())")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
            Text("HISTORY")
                .font(.system(size: 10, weight: .black))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.06)).cornerRadius(8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
    }
}
