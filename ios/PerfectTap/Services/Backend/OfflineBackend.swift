import Foundation

// MARK: - OfflineBackend
// GameBackend that never touches the network. Used automatically when the app
// runs as an XCTest host, so unit tests can't create users or write data in the
// real Firebase / Supabase projects. Unit tests may also swap in their own
// expectations through `submitDuelScoreResult`.
@MainActor
final class OfflineBackend: GameBackend {
    static let shared = OfflineBackend()

    var uid: String? = "00000000-0000-4000-8000-000000000001"
    var submitDuelScoreResult = true
    private(set) var submittedDuelScores: [String] = []

    var currentUID: String? { uid }
    var currentUserEmail: String? { nil }
    var isLinkedToEmail: Bool { false }
    func signInAnonymously() async -> String? { uid }
    func linkAnonymousAccount(email: String, password: String) async throws -> String { throw BackendError.network }
    func confirmEmailLink(email: String, code: String, password: String) async throws -> String { throw BackendError.network }
    func signInWithEmail(email: String, password: String) async throws -> String { throw BackendError.network }
    func signOut() async {}
    func deleteCurrentAccount() async -> BackendDeleteResult { .noUser }
    func reauthenticateAndDelete(email: String, password: String) async -> Bool { false }
    func authoritativeDayVerification(forceRefresh: Bool) async -> AuthoritativeDayVerificationResult {
        .init(dayKey: nil, source: nil, failureReason: .noInternet, usedFallback: false)
    }
    func isUsernameAvailable(_ username: String) async -> Bool { true }
    func loadProfile() async -> PlayerProfile? { nil }
    func saveProfile(_ profile: PlayerProfile) async { profile.save() }
    func loadPlayerProfile(uid: String) async -> PlayerProfile? { nil }
    func loadFriendProfiles(uids: [String]) async -> [PlayerProfile] { [] }
    func startGameSession(mode: GameMode, duelId: String?) async -> String? { nil }
    func submitScore(mode: GameMode, score: Int, maxCombo: Int, taps: Int, perfects: Int, sessionId: String?) async {}
    func loadLeaderboard(mode: GameMode, limit: Int) async -> [(username: String, score: Int)] { [] }
    func createDuel(hostName: String, hostAvatar: String?, mode: GameMode) async throws -> (duelId: String, code: String) { throw BackendError.network }
    func joinDuel(code: String, guestName: String, guestAvatar: String?) async throws -> (duelId: String, hostName: String) { throw BackendError.network }
    func loadDuel(duelId: String) async -> Duel? { nil }
    func loadDuels(duelIds: [String]) async -> [String: Duel] { [:] }
    func listenDuel(duelId: String, onChange: @escaping (Duel?) -> Void) -> Any? { nil }
    func removeDuelListener(_ listener: Any?) {}
    func submitDuelScore(duelId: String, role: String, score: Int, maxCombo: Int,
                         taps: Int, perfects: Int, sessionId: String?) async -> Bool {
        submittedDuelScores.append(duelId)
        return submitDuelScoreResult
    }
    func loadFriendUIDs() async -> [String] { [] }
    func sendFriendRequest(friendCode: String) async throws { throw BackendError.network }
    func loadIncomingFriendRequests() async -> [FriendRequest] { [] }
    func loadOutgoingFriendRequests() async -> [FriendRequest] { [] }
    func acceptFriendRequest(_ request: FriendRequest) async throws { throw BackendError.network }
    func rejectFriendRequest(_ request: FriendRequest) async throws {}
    func cancelFriendRequest(_ request: FriendRequest) async throws {}
    func listenIncomingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any? { nil }
    func listenOutgoingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any? { nil }
    func sendDuelInvitation(toUID: String, toUsername: String, toAvatar: String, mode: GameMode) async throws -> DuelInvitation { throw BackendError.network }
    func loadIncomingDuelInvitations() async -> [DuelInvitation] { [] }
    func loadOutgoingDuelInvitations() async -> [DuelInvitation] { [] }
    func acceptDuelInvitation(_ invitation: DuelInvitation) async throws { throw BackendError.network }
    func markDuelInvitationInProgress(_ invitationId: String) async -> Bool { false }
    func rejectDuelInvitation(_ invitation: DuelInvitation) async throws {}
    func cancelDuelInvitation(_ invitation: DuelInvitation) async throws {}
    func listenIncomingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any? { nil }
    func listenOutgoingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any? { nil }
    func listenOutgoingDuelInvitation(toUID: String, onChange: @escaping (DuelInvitation?) -> Void) -> Any? { nil }
    func loadDuelInvitation(id: String) async -> DuelInvitation? { nil }
    func hasPendingDuelInvite(withUID otherUID: String) async -> DuelInvitation? { nil }
    func removeListener(_ listener: Any?) {}
}
