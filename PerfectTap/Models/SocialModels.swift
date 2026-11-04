import Foundation

// Firestore Timestamp → Date helper (avoids importing FirebaseFirestore in models)
private func dateFromFirestore(_ value: Any?) -> Date? {
    if let d = value as? Date { return d }
    // Firestore Timestamp has dateValue() — use dynamic dispatch
    if let obj = value as? NSObject, obj.responds(to: NSSelectorFromString("dateValue")),
       let d = obj.perform(NSSelectorFromString("dateValue"))?.takeUnretainedValue() as? Date {
        return d
    }
    return nil
}

// MARK: - Friend Request (Firestore: friend_requests/{requestId})
struct FriendRequest: Identifiable {
    var id: String = ""
    var fromUID: String = ""
    var toUID: String = ""
    var fromUsername: String = ""
    var fromAvatar: String = "default"
    var toUsername: String = ""
    var toAvatar: String = "default"
    var status: Status = .pending
    var createdAt: Date = Date()

    enum Status: String {
        case pending, accepted, rejected, cancelled
    }

    init() {}

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.fromUID = data["from_uid"] as? String ?? ""
        self.toUID = data["to_uid"] as? String ?? ""
        self.fromUsername = data["from_username"] as? String ?? ""
        self.fromAvatar = data["from_avatar"] as? String ?? "default"
        self.toUsername = data["to_username"] as? String ?? ""
        self.toAvatar = data["to_avatar"] as? String ?? "default"
        self.status = Status(rawValue: data["status"] as? String ?? "") ?? .pending
        if let ts = dateFromFirestore(data["created_at"]) {
            self.createdAt = ts
        }
    }
}

// MARK: - Friendship (Firestore: friendships/{minUid_maxUid})
struct Friendship: Identifiable {
    var id: String = ""          // pairId = min(uidA, uidB)_max(uidA, uidB)
    var userIDs: [String] = []   // exactly 2 UIDs
    var createdAt: Date = Date()

    static func pairId(_ uidA: String, _ uidB: String) -> String {
        let sorted = [uidA, uidB].sorted()
        return "\(sorted[0])_\(sorted[1])"
    }

    init() {}

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.userIDs = data["user_ids"] as? [String] ?? []
        if let ts = dateFromFirestore(data["created_at"]) {
            self.createdAt = ts
        }
    }
}

// MARK: - Duel Invitation (Firestore: duel_invitations/{invitationId})
struct DuelInvitation: Identifiable {
    var id: String = ""
    var fromUID: String = ""
    var toUID: String = ""
    var fromUsername: String = ""
    var fromAvatar: String = "default"
    var toUsername: String = ""
    var toAvatar: String = "default"
    var duelId: String = ""
    var duelCode: String = ""
    var mode: GameMode = .duel
    var status: Status = .pending
    var createdAt: Date = Date()
    var expiresAt: Date = Date()

    enum Status: String {
        case pending, accepted, inProgress = "in_progress", rejected, cancelled, expired
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    init() {}

    init?(id: String, data: [String: Any]) {
        self.id = id
        self.fromUID = data["from_uid"] as? String ?? ""
        self.toUID = data["to_uid"] as? String ?? ""
        self.fromUsername = data["from_username"] as? String ?? ""
        self.fromAvatar = data["from_avatar"] as? String ?? "default"
        self.toUsername = data["to_username"] as? String ?? ""
        self.toAvatar = data["to_avatar"] as? String ?? "default"
        self.duelId = data["duel_id"] as? String ?? ""
        self.duelCode = data["duel_code"] as? String ?? ""
        self.mode = GameMode(rawValue: data["mode"] as? String ?? "") ?? .duel
        self.status = Status(rawValue: data["status"] as? String ?? "") ?? .pending
        if let ts = dateFromFirestore(data["created_at"]) {
            self.createdAt = ts
        }
        if let ts = dateFromFirestore(data["expires_at"]) {
            self.expiresAt = ts
        }
    }
}

enum DuelInvitePresentationState {
    case pending
    case readyToPlay
    case waitingForOpponent
    case history
}

extension DuelInvitation {
    func presentationState(
        currentUID: String?,
        duel: Duel?,
        isHandled: Bool = false
    ) -> DuelInvitePresentationState {
        if isHandled || isExpired { return .history }
        switch status {
        case .pending:
            return .pending
        case .accepted, .inProgress:
            guard let uid = currentUID, let duel else { return .history }
            if duel.isActionableForPlay(forUID: uid) { return .readyToPlay }
            if duel.isAwaitingOpponent(forUID: uid) { return .waitingForOpponent }
            return .history
        case .rejected, .cancelled, .expired:
            return .history
        }
    }
}

// MARK: - Friend Request State (guard-only: friend_request_state/{pairId})
// Used as a transaction guard to prevent duplicate pending requests.
// Shape: { user_ids: [uidA, uidB], pending_request_id: "...", status: "pending" }

// MARK: - Duel Invite State (guard-only: duel_invite_state/{pairId})
// Used as a transaction guard to prevent duplicate pending duel invites.
// Shape: { user_ids: [uidA, uidB], pending_invitation_id: "...", status: "pending" }
