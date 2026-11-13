import Foundation

// MARK: - GameBackend
// Single seam between the SwiftUI app and its backend. Views and view models
// talk to `Backend.shared` only, so Firebase and Supabase can coexist while the
// migration is verified, and the cutover is one build setting (PT_BACKEND).
//
// Contract (both implementations):
//  * Methods are called on the main actor; callbacks are delivered on it.
//  * Listener handles are opaque (`Any?`) and must be passed back to
//    `removeListener(_:)` / `removeDuelListener(_:)` exactly once.
//  * UIDs are lowercase strings (Supabase returns lowercase UUIDs).

enum AuthoritativeDaySource: String {
    case liveServer
    case inMemoryCache
    case persistedCache
}

enum AuthoritativeDayFailureReason: Equatable {
    case noInternet
    case firebaseNotConfigured   // "backend not configured"
    case authUnavailable
    case permissionDenied
    case serverTimestampMissing
    case unknown
}

struct AuthoritativeDayVerificationResult {
    let dayKey: String?
    let source: AuthoritativeDaySource?
    let failureReason: AuthoritativeDayFailureReason?
    let usedFallback: Bool
}

/// Result of a delete-account attempt.
enum BackendDeleteResult {
    case success          // Auth user + cloud data deleted
    case requiresReauth   // cloud data deleted, auth user needs re-authentication
    case noUser           // nobody signed in
}

/// User-facing backend errors. `errorDescription` is shown in the UI.
enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case notFound(String)
    case emailInUse
    case invalidCredentials
    case rateLimited
    case network
    case server(String)
    /// Email linking step 1 succeeded: a one-time code was sent to this address.
    case verificationCodeSent(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .notFound(let what): return what
        case .emailInUse: return "This email is already linked to another account. Use Sign In instead."
        case .invalidCredentials: return "Incorrect email or password."
        case .rateLimited: return "Too many attempts. Please wait a minute and try again."
        case .network: return "No connection. Check your internet and try again."
        case .server(let message): return message
        case .verificationCodeSent(let email): return "We sent a 6-digit code to \(email)."
        }
    }
}

@MainActor
protocol GameBackend: AnyObject {
    // Identity
    var currentUID: String? { get }
    var currentUserEmail: String? { get }
    var isLinkedToEmail: Bool { get }
    func signInAnonymously() async -> String?
    /// Links email/password to the current account. May throw
    /// `.verificationCodeSent`; then call `confirmEmailLink` with the emailed code.
    func linkAnonymousAccount(email: String, password: String) async throws -> String
    func confirmEmailLink(email: String, code: String, password: String) async throws -> String
    func signInWithEmail(email: String, password: String) async throws -> String
    func signOut() async
    func deleteCurrentAccount() async -> BackendDeleteResult
    func reauthenticateAndDelete(email: String, password: String) async -> Bool

    // Server time
    func authoritativeDayVerification(forceRefresh: Bool) async -> AuthoritativeDayVerificationResult

    // Profile
    func isUsernameAvailable(_ username: String) async -> Bool
    func loadProfile() async -> PlayerProfile?
    func saveProfile(_ profile: PlayerProfile) async
    func loadPlayerProfile(uid: String) async -> PlayerProfile?
    func loadFriendProfiles(uids: [String]) async -> [PlayerProfile]

    // Verified scores
    func startGameSession(mode: GameMode, duelId: String?) async -> String?
    func submitScore(mode: GameMode, score: Int, maxCombo: Int, taps: Int, perfects: Int, sessionId: String?) async
    func loadLeaderboard(mode: GameMode, limit: Int) async -> [(username: String, score: Int)]

    // Duels
    func createDuel(hostName: String, hostAvatar: String?, mode: GameMode) async throws -> (duelId: String, code: String)
    func joinDuel(code: String, guestName: String, guestAvatar: String?) async throws -> (duelId: String, hostName: String)
    func loadDuel(duelId: String) async -> Duel?
    func loadDuels(duelIds: [String]) async -> [String: Duel]
    func listenDuel(duelId: String, onChange: @escaping (Duel?) -> Void) -> Any?
    func removeDuelListener(_ listener: Any?)
    /// Returns true once the server has the score (including "already submitted").
    @discardableResult
    func submitDuelScore(duelId: String, role: String, score: Int, maxCombo: Int,
                         taps: Int, perfects: Int, sessionId: String?) async -> Bool

    // Friends
    func loadFriendUIDs() async -> [String]
    func sendFriendRequest(friendCode: String) async throws
    func loadIncomingFriendRequests() async -> [FriendRequest]
    func loadOutgoingFriendRequests() async -> [FriendRequest]
    func acceptFriendRequest(_ request: FriendRequest) async throws
    func rejectFriendRequest(_ request: FriendRequest) async throws
    func cancelFriendRequest(_ request: FriendRequest) async throws
    func listenIncomingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any?
    func listenOutgoingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any?

    // Duel invitations
    func sendDuelInvitation(toUID: String, toUsername: String, toAvatar: String, mode: GameMode) async throws -> DuelInvitation
    func loadIncomingDuelInvitations() async -> [DuelInvitation]
    func loadOutgoingDuelInvitations() async -> [DuelInvitation]
    func acceptDuelInvitation(_ invitation: DuelInvitation) async throws
    func markDuelInvitationInProgress(_ invitationId: String) async -> Bool
    func rejectDuelInvitation(_ invitation: DuelInvitation) async throws
    func cancelDuelInvitation(_ invitation: DuelInvitation) async throws
    func listenIncomingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any?
    func listenOutgoingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any?
    func listenOutgoingDuelInvitation(toUID: String, onChange: @escaping (DuelInvitation?) -> Void) -> Any?
    func loadDuelInvitation(id: String) async -> DuelInvitation?
    func hasPendingDuelInvite(withUID otherUID: String) async -> DuelInvitation?

    func removeListener(_ listener: Any?)
}

// MARK: - Shared behaviour (identical for both backends)
extension GameBackend {
    func authoritativeDayKey(forceRefresh: Bool = false) async -> String? {
        await authoritativeDayVerification(forceRefresh: forceRefresh).dayKey
    }

    func authoritativeDayVerification() async -> AuthoritativeDayVerificationResult {
        await authoritativeDayVerification(forceRefresh: false)
    }

    func startGameSession(mode: GameMode) async -> String? {
        await startGameSession(mode: mode, duelId: nil)
    }

    func createDuel(hostName: String, hostAvatar: String?) async throws -> (duelId: String, code: String) {
        try await createDuel(hostName: hostName, hostAvatar: hostAvatar, mode: .duel)
    }

    func sendDuelInvitation(toUID: String, toUsername: String, toAvatar: String) async throws -> DuelInvitation {
        try await sendDuelInvitation(toUID: toUID, toUsername: toUsername, toAvatar: toAvatar, mode: .duel)
    }

    func loadLeaderboard(mode: GameMode) async -> [(username: String, score: Int)] {
        await loadLeaderboard(mode: mode, limit: 20)
    }

    func loadFriendsLeaderboard(friendUIDs: [String], mode: GameMode) async -> [(username: String, score: Int)] {
        guard !friendUIDs.isEmpty, !Task.isCancelled else { return [] }
        let profiles = await loadFriendProfiles(uids: friendUIDs)
        guard !Task.isCancelled else { return [] }
        return profiles
            .map { (username: $0.username, score: $0.bestScore(for: mode)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
    }

    /// Shared classification for outgoing duel invites (Friends/FriendDetail/Home).
    func loadOutgoingDuelInvitePresentationStates(
        outgoingInvitations: [DuelInvitation]
    ) async -> [String: DuelInvitePresentationState] {
        let duelIDs = outgoingInvitations
            .filter { $0.status == .accepted || $0.status == .inProgress }
            .map(\.duelId)
        let duelsById = await loadDuels(duelIds: duelIDs)
        let uid = currentUID
        var states: [String: DuelInvitePresentationState] = [:]
        states.reserveCapacity(outgoingInvitations.count)
        for invite in outgoingInvitations {
            states[invite.id] = invite.presentationState(
                currentUID: uid,
                duel: duelsById[invite.duelId],
                isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
            )
        }
        return states
    }

    /// Actionable counts for Home/Friends badges.
    func loadActionablePendingCounts(
        incomingFriendRequests: [FriendRequest],
        incomingDuelInvitations: [DuelInvitation],
        outgoingDuelInvitations: [DuelInvitation]
    ) async -> (friendRequests: Int, duelInvitations: Int) {
        let incomingActionable = incomingDuelInvitations.filter {
            $0.presentationState(currentUID: nil, duel: nil, isHandled: false) != .history
        }.count
        let outgoingStates = await loadOutgoingDuelInvitePresentationStates(outgoingInvitations: outgoingDuelInvitations)
        let readyToPlay = outgoingStates.values.filter { $0 == .readyToPlay }.count
        return (incomingFriendRequests.count, incomingActionable + readyToPlay)
    }

    func loadPendingCounts() async -> (friendRequests: Int, duelInvitations: Int) {
        let incomingRequests = await loadIncomingFriendRequests()
        let incomingInvites = await loadIncomingDuelInvitations()
        let outgoingInvites = await loadOutgoingDuelInvitations()
        return await loadActionablePendingCounts(
            incomingFriendRequests: incomingRequests,
            incomingDuelInvitations: incomingInvites,
            outgoingDuelInvitations: outgoingInvites
        )
    }
}

// MARK: - Backend selection
/// `PT_BACKEND` (Info.plist, from the build setting of the same name):
/// "supabase" or "firebase". Unknown/missing → firebase, so a misconfigured
/// build keeps today's production behaviour instead of silently switching.
enum BackendKind: String {
    case firebase
    case supabase

    static var configured: BackendKind {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PT_BACKEND"],
           let kind = BackendKind(rawValue: override.lowercased()) {
            return kind
        }
        #endif
        let raw = (Bundle.main.object(forInfoDictionaryKey: "PT_BACKEND") as? String ?? "").lowercased()
        return BackendKind(rawValue: raw) ?? .firebase
    }
}

@MainActor
enum Backend {
    static let kind: BackendKind = BackendKind.configured

    /// Creating a Cloud Backup on Supabase requires a verified email (6-digit code).
    /// Until the project has working SMTP, `PT_EMAIL_OTP_ENABLED` stays NO and the
    /// sign-up path is disabled in the UI instead of bypassing verification.
    /// Firebase builds keep their existing flow.
    static var cloudBackupSignUpAvailable: Bool {
        if kind == .firebase { return true }
        let raw = (Bundle.main.object(forInfoDictionaryKey: "PT_EMAIL_OTP_ENABLED") as? String ?? "").uppercased()
        return raw == "YES" || raw == "TRUE" || raw == "1"
    }

    /// True when the app is the host process of a unit-test run.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static let shared: GameBackend = {
        // Unit tests must never create users or write data in real projects.
        if isRunningUnitTests { return OfflineBackend.shared }
        switch kind {
        case .supabase:
            if let service = SupabaseService.makeShared() { return service }
            #if DEBUG
            print("[Backend] ⚠️ PT_BACKEND=supabase but SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY are missing — falling back to Firebase")
            #endif
            return FirebaseService.shared
        case .firebase:
            return FirebaseService.shared
        }
    }()
}
