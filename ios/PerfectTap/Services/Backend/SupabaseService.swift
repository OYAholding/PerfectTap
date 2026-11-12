import Foundation
import Supabase
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// MARK: - SupabaseService
// GameBackend on Supabase (Postgres + Auth + Realtime + Edge Functions).
//
// * Every write is a Postgres RPC (supabase/migrations/*core_schema.sql) that
//   re-derives the caller from the JWT, validates and runs atomically. The app
//   cannot write tables directly (no INSERT/UPDATE grants, RLS on everything).
// * Gameplay stays local. Only session start, final scores and social state
//   touch the network, never the per-frame tap loop.
// * Realtime events are invalidation signals: on any change (and on every
//   (re)subscribe) the listener reloads the authoritative rows. Duplicate or
//   out-of-order events therefore can't corrupt UI state.
// * Only the publishable key ships in the app. Service-role/secret keys exist
//   only inside Edge Functions.
@MainActor
final class SupabaseService: GameBackend {

    static func makeShared() -> SupabaseService? {
        guard let config = SupabaseConfig.load() else { return nil }
        return SupabaseService(config: config)
    }

    let client: SupabaseClient
    private var profileSaveChain: Task<Void, Never>? = nil
    private var cachedDayKey: String? = nil
    private var dayFetchedAt: Date? = nil
    private static let lastKnownServerDayKey = "perfecttap_last_known_server_day"
    private static let legacyClaimDoneKeyPrefix = "perfecttap_legacy_claim_done_"

    private init(config: SupabaseConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.publishableKey,
            options: SupabaseClientOptions(
                // Per-project Keychain key: the SDK default is shared by every
                // project, so a session from another project (e.g. the local
                // stack, or a previous backend) would be restored here.
                auth: .init(storageKey: Self.storageKey(for: config.url),
                            emitLocalSessionAsInitialSession: true)
            )
        )
    }

    static func storageKey(for url: URL) -> String {
        let host = url.host ?? "supabase"
        let ref = host.hasSuffix(".supabase.co") ? String(host.dropLast(".supabase.co".count)) : host
        let port = url.port.map { "-\($0)" } ?? ""
        return "sb-\(ref)\(port)-auth-token"
    }

    // MARK: - Identity

    var currentUID: String? { client.auth.currentUser?.id.uuidString.lowercased() }

    var currentUserEmail: String? {
        guard let user = client.auth.currentUser, !user.isAnonymous else { return nil }
        return user.email
    }

    var isLinkedToEmail: Bool {
        guard let user = client.auth.currentUser else { return false }
        return !user.isAnonymous && user.email != nil
    }

    /// Restores the Keychain session or creates an anonymous user, then (once)
    /// moves this device's Firebase-era progress onto it.
    func signInAnonymously() async -> String? {
        var uid = currentUID
        if uid != nil, await restoredSessionIsGone() {
            log("restored session no longer valid on the server; starting a fresh anonymous account")
            try? await client.auth.signOut(scope: .local)
            uid = nil
        }
        if uid == nil {
            do {
                let session = try await client.auth.signInAnonymously()
                uid = session.user.id.uuidString.lowercased()
            } catch {
                log("anonymous sign-in failed: \(error.localizedDescription)")
                return nil
            }
        }
        if let uid { await claimLegacyAccountIfNeeded(uid: uid) }
        return uid
    }

    /// Step 1 of "Cloud Backup": Supabase emails a one-time code to the address.
    /// The email is attached only after the player proves they can read it
    /// (`confirmEmailLink`). Needs working SMTP on the project.
    /// True only when the server positively says the cached user/session is
    /// invalid (deleted account, reset project). Offline keeps the session.
    private func restoredSessionIsGone() async -> Bool {
        do {
            _ = try await client.auth.user()
            return false
        } catch {
            if isNetworkError(error) { return false }
            if let authError = error as? AuthError {
                switch authError.errorCode {
                case .userNotFound, .badJWT, .sessionNotFound, .sessionExpired, .refreshTokenNotFound: return true
                default: break
                }
                if case .sessionMissing = authError { return true }
            }
            return false
        }
    }

    func linkAnonymousAccount(email: String, password: String) async throws -> String {
        guard let user = client.auth.currentUser else { throw BackendError.notSignedIn }
        if let existing = user.email, !existing.isEmpty, user.emailConfirmedAt != nil {
            return user.id.uuidString.lowercased()   // already linked and verified
        }
        guard password.count >= 6 else { throw BackendError.server("Password must be at least 6 characters.") }
        let normalized = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            _ = try await client.auth.update(user: UserAttributes(email: normalized))
        } catch {
            throw mapAuthError(error)
        }
        throw BackendError.verificationCodeSent(normalized)
    }

    /// Step 2: verify the emailed code, then set the password.
    func confirmEmailLink(email: String, code: String, password: String) async throws -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6, trimmed.allSatisfy(\.isNumber) else {
            throw BackendError.server("Enter the 6-digit code from the email.")
        }
        do {
            _ = try await client.auth.verifyOTP(email: email.lowercased(), token: trimmed, type: .emailChange)
            _ = try await client.auth.update(user: UserAttributes(password: password))
        } catch {
            throw mapAuthError(error)
        }
        guard let uid = currentUID else { throw BackendError.notSignedIn }
        return uid
    }

    private func mapAuthError(_ error: Error) -> Error {
        if isNetworkError(error) { return BackendError.network }
        guard let authError = error as? AuthError else {
            return BackendError.server("Something went wrong. Please try again.")
        }
        switch authError.errorCode {
        case .emailExists, .userAlreadyExists: return BackendError.emailInUse
        case .overEmailSendRateLimit, .overRequestRateLimit: return BackendError.rateLimited
        case .otpExpired: return BackendError.server("That code is invalid or expired. Request a new one.")
        case .emailAddressNotAuthorized:
            return BackendError.server("Email backup is temporarily unavailable. Please try again later.")
        case .weakPassword: return BackendError.server("Choose a stronger password (at least 6 characters).")
        default:
            if authError.errorCode.rawValue == "email_address_invalid" {
                return BackendError.server("Enter a valid email address you can receive mail at.")
            }
            return BackendError.server("Something went wrong. Please try again.")
        }
    }

    /// Supabase email sign-in, falling back to "lazy migration" from Firebase
    /// for email players who haven't opened the Supabase build before.
    func signInWithEmail(email: String, password: String) async throws -> String {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return session.user.id.uuidString.lowercased()
        } catch {
            if isNetworkError(error) { throw BackendError.network }
            #if canImport(FirebaseAuth)
            if let uid = try await migrateFirebaseEmailAccount(email: email, password: password) {
                return uid
            }
            #endif
            throw BackendError.invalidCredentials
        }
    }

    func signOut() async {
        do { try await client.auth.signOut() } catch {
            // Server unreachable: still drop the local session.
            try? await client.auth.signOut(scope: .local)
        }
    }

    func deleteCurrentAccount() async -> BackendDeleteResult {
        guard currentUID != nil else { return .noUser }
        do {
            try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(method: .post))
        } catch {
            log("delete-account failed: \(error.localizedDescription)")
            // Keep the session so the user can retry; nothing was deleted.
            return .requiresReauth
        }
        try? await client.auth.signOut(scope: .local)
        return .success
    }

    func reauthenticateAndDelete(email: String, password: String) async -> Bool {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            return false
        }
        return await deleteCurrentAccount() == .success
    }

    // MARK: - Legacy Firebase claim

    private func claimLegacyAccountIfNeeded(uid: String) async {
        #if canImport(FirebaseAuth)
        let doneKey = Self.legacyClaimDoneKeyPrefix + uid
        guard !UserDefaults.standard.bool(forKey: doneKey),
              let firebaseUser = Auth.auth().currentUser else { return }
        do {
            let token = try await firebaseUser.getIDToken()
            let reply = try await invokeClaim(firebaseToken: token, password: nil)
            log("legacy claim: \(reply.status)")
            if reply.status == "claimed" || reply.status == "already_claimed" {
                // Retry next launch (claim is idempotent) until local identity matches the server.
                guard await adoptServerIdentityAfterClaim() else { return }
            }
            // Terminal outcomes: never retry. Transient errors (thrown) retry next launch.
            UserDefaults.standard.set(true, forKey: doneKey)
        } catch {
            log("legacy claim deferred: \(error.localizedDescription)")
        }
        #endif
    }

    /// The claim drops a legacy username / friend code that another player already
    /// owns (e.g. two Firebase accounts both named "GG"). The device still holds the
    /// Firebase-era copy, and AuthViewModel re-saves it right after sign-in — with the
    /// old values every save_profile would then fail (username_taken /
    /// friend_code_taken) and progress would silently stop syncing. Make the local
    /// identity follow the server; an empty username sends the player to the picker.
    /// Returns false when the server profile could not be read (retry next launch).
    func adoptServerIdentityAfterClaim() async -> Bool {
        guard let server = await loadProfile() else { return false }
        guard var local = PlayerProfile.load() else { return true }   // bootstrap restores from server
        let adopted = Self.reconcileIdentity(local: local, server: server)
        if adopted.username != local.username || adopted.friendCode != local.friendCode {
            log("legacy claim: local identity adjusted to server (username changed: \(adopted.username != local.username))")
            local = adopted
            local.save()
        }
        return true
    }

    /// Pure helper (unit-tested): server owns username and friend code after a claim.
    nonisolated static func reconcileIdentity(local: PlayerProfile, server: PlayerProfile,
                                              newCode: () -> String = SupabaseService.generateFriendCode) -> PlayerProfile {
        var out = local
        out.username = server.username
        out.friendCode = server.friendCode.isEmpty ? newCode() : server.friendCode
        return out
    }

    nonisolated static func generateFriendCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement() ?? "A" })
    }

    private struct ClaimReply: Decodable {
        let status: String
        let email: String?
        let usernameConflict: Bool?
    }

    private func invokeClaim(firebaseToken: String, password: String?) async throws -> ClaimReply {
        struct Body: Encodable { let firebaseIdToken: String; let password: String? }
        do {
            return try await client.functions.invoke(
                "claim-legacy-account",
                options: FunctionInvokeOptions(body: Body(firebaseIdToken: firebaseToken, password: password)))
        } catch FunctionsError.httpError(let code, let data) where code != 409 {
            log("claim-legacy-account HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")")
            throw FunctionsError.httpError(code: code, data: data)
        } catch FunctionsError.httpError(let code, let data) where code == 409 {
            // Conflicts are terminal answers, not failures.
            return (try? JSONDecoder().decode(ClaimReply.self, from: data)) ?? ClaimReply(status: "conflict", email: nil, usernameConflict: nil)
        }
    }

    #if canImport(FirebaseAuth)
    private func migrateFirebaseEmailAccount(email: String, password: String) async throws -> String? {
        guard let fbResult = try? await Auth.auth().signIn(withEmail: email, password: password) else { return nil }
        if currentUID == nil { _ = try? await client.auth.signInAnonymously() }
        let token = try await fbResult.user.getIDToken()
        let reply = try await invokeClaim(firebaseToken: token, password: password)
        switch reply.status {
        case "sign_in_required":
            let session = try await client.auth.signIn(email: email, password: password)
            return session.user.id.uuidString.lowercased()
        case "claimed", "already_claimed", "no_legacy_data":
            _ = try? await client.auth.refreshSession()
            if let uid = currentUID { UserDefaults.standard.set(true, forKey: Self.legacyClaimDoneKeyPrefix + uid) }
            return currentUID
        default:
            return nil
        }
    }
    #endif

    // MARK: - Server day

    func authoritativeDayVerification(forceRefresh: Bool) async -> AuthoritativeDayVerificationResult {
        if !forceRefresh, let cached = cachedDayKey, let at = dayFetchedAt, Date().timeIntervalSince(at) < 60 {
            return .init(dayKey: cached, source: .inMemoryCache, failureReason: nil, usedFallback: false)
        }
        do {
            if currentUID == nil { _ = await signInAnonymously() }
            guard currentUID != nil else { throw BackendError.notSignedIn }
            let day: String = try await client.rpc("server_day").execute().value
            cachedDayKey = day
            dayFetchedAt = Date()
            UserDefaults.standard.set(day, forKey: Self.lastKnownServerDayKey)
            return .init(dayKey: day, source: .liveServer, failureReason: nil, usedFallback: false)
        } catch {
            let reason: AuthoritativeDayFailureReason =
                isNetworkError(error) ? .noInternet : (error as? BackendError == .notSignedIn ? .authUnavailable : .unknown)
            if let cached = cachedDayKey {
                return .init(dayKey: cached, source: .inMemoryCache, failureReason: reason, usedFallback: true)
            }
            if let persisted = UserDefaults.standard.string(forKey: Self.lastKnownServerDayKey), !persisted.isEmpty {
                cachedDayKey = persisted
                return .init(dayKey: persisted, source: .persistedCache, failureReason: reason, usedFallback: true)
            }
            return .init(dayKey: nil, source: nil, failureReason: reason, usedFallback: false)
        }
    }

    // MARK: - Profiles

    func isUsernameAvailable(_ username: String) async -> Bool {
        do {
            return try await client.rpc("is_username_available", params: ["p_username": username]).execute().value
        } catch {
            // Server-side unique index is the real guard; don't block onboarding offline.
            return true
        }
    }

    func loadProfile() async -> PlayerProfile? {
        guard currentUID != nil,
              let data = try? await client.rpc("get_my_profile").execute().data,
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return BackendCodec.decodeProfile(dict)
    }

    func saveProfile(_ profile: PlayerProfile) async {
        guard let uid = currentUID else { return }
        profile.save()   // local first, always
        let payload = BackendCodec.encodeProfile(profile)
        // Serialise writes so a stale snapshot can never overwrite a newer one.
        let previous = profileSaveChain
        profileSaveChain = Task { @MainActor in
            if let previous { await previous.value }
            guard self.currentUID == uid else { return }
            await self.withRetry("save_profile") {
                try await self.client.rpc("save_profile", params: ["p": JSONPayload(payload)]).execute()
            }
        }
    }

    func loadPlayerProfile(uid: String) async -> PlayerProfile? {
        await loadFriendProfiles(uids: [uid]).first
    }

    func loadFriendProfiles(uids: [String]) async -> [PlayerProfile] {
        let ids = Array(Set(uids.map { $0.lowercased() }.filter { UUID(uuidString: $0) != nil })).prefix(100)
        guard !ids.isEmpty, !Task.isCancelled,
              let data = try? await client.rpc("get_player_profiles", params: ["p_ids": Array(ids)]).execute().data,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        let byId = Dictionary(rows.compactMap { BackendCodec.decodeProfile($0) }.map { ($0.uid, $0) },
                              uniquingKeysWith: { a, _ in a })
        return uids.compactMap { byId[$0.lowercased()] }   // keep caller's order
    }

    // MARK: - Verified scores

    func startGameSession(mode: GameMode, duelId: String?) async -> String? {
        guard mode.isRanked || duelId != nil else { return nil }
        struct Params: Encodable { let p_mode: String; let p_duel_id: String? }
        // The game runs locally meanwhile; a few quick retries cover a flaky start.
        for attempt in 0..<3 {
            do {
                let id: String = try await client.rpc(
                    "start_game_session", params: Params(p_mode: mode.rawValue, p_duel_id: duelId)).execute().value
                return id
            } catch {
                guard isNetworkError(error), attempt < 2, !Task.isCancelled else { return nil }
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
            }
        }
        return nil
    }

    func submitScore(mode: GameMode, score: Int, maxCombo: Int, taps: Int, perfects: Int, sessionId: String?) async {
        guard mode.isRanked, let sessionId else { return }
        struct Params: Encodable {
            let p_session_id: String, p_mode: String, p_score: Int, p_max_combo: Int, p_taps: Int, p_perfects: Int
        }
        let params = Params(p_session_id: sessionId, p_mode: mode.rawValue, p_score: score,
                            p_max_combo: maxCombo, p_taps: taps, p_perfects: perfects)
        // Safe to retry: the session is single-use, so a replay is answered "session_used".
        await withRetry("submit_score") {
            try await self.client.rpc("submit_score", params: params).execute()
        }
    }

    func loadLeaderboard(mode: GameMode, limit: Int) async -> [(username: String, score: Int)] {
        struct Row: Decodable { let username: String; let score: Int }
        struct Params: Encodable { let p_mode: String; let p_limit: Int }
        guard !Task.isCancelled,
              let rows: [Row] = try? await client.rpc(
                  "get_leaderboard", params: Params(p_mode: mode.rawValue, p_limit: limit)).execute().value
        else { return [] }
        return rows.map { ($0.username, $0.score) }
    }

    // MARK: - Duels

    private struct DuelRef: Decodable { let duel_id: String; let code: String? ; let host_name: String? }

    func createDuel(hostName: String, hostAvatar: String?, mode: GameMode) async throws -> (duelId: String, code: String) {
        guard currentUID != nil else { throw BackendError.notSignedIn }
        do {
            let rows: [DuelRef] = try await client.rpc("create_duel", params: ["p_mode": mode.rawValue]).execute().value
            guard let row = rows.first, let code = row.code else { throw BackendError.server("Could not create duel") }
            return (row.duel_id.lowercased(), code)
        } catch { throw mapRPCError(error) }
    }

    func joinDuel(code: String, guestName: String, guestAvatar: String?) async throws -> (duelId: String, hostName: String) {
        guard currentUID != nil else { throw BackendError.notSignedIn }
        do {
            let rows: [DuelRef] = try await client.rpc("join_duel", params: ["p_code": code]).execute().value
            guard let row = rows.first else { throw BackendError.notFound("Duel not found") }
            return (row.duel_id.lowercased(), row.host_name ?? "Opponent")
        } catch { throw mapRPCError(error) }
    }

    func loadDuel(duelId: String) async -> Duel? {
        guard UUID(uuidString: duelId) != nil else { return nil }
        return await loadDuels(duelIds: [duelId])[duelId.lowercased()]
    }

    func loadDuels(duelIds: [String]) async -> [String: Duel] {
        let ids = Array(Set(duelIds.map { $0.lowercased() }.filter { UUID(uuidString: $0) != nil }))
        guard !ids.isEmpty else { return [:] }
        var result: [String: Duel] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
            guard let rows = await selectRows(client.from("duels").select().in("id", values: chunk)) else { continue }
            for row in rows {
                guard let id = (row["id"] as? String)?.lowercased() else { continue }
                result[id] = BackendCodec.decodeDuel(id: id, data: row)
            }
        }
        return result
    }

    func listenDuel(duelId: String, onChange: @escaping (Duel?) -> Void) -> Any? {
        let id = duelId.lowercased()
        guard UUID(uuidString: id) != nil else { return nil }
        return RealtimeQueryListener(
            client: client, topic: "duel-\(id)-\(UUID().uuidString.prefix(6))", table: "duels", filter: .eq("id", value: id),
            reload: { [weak self] in await self?.loadDuel(duelId: id) },
            deliver: onChange)
    }

    func removeDuelListener(_ listener: Any?) { removeListener(listener) }

    func submitDuelScore(duelId: String, role: String, score: Int, maxCombo: Int,
                         taps: Int, perfects: Int, sessionId: String?) async -> Bool {
        guard UUID(uuidString: duelId) != nil else { return false }
        struct Params: Encodable {
            let p_duel_id: String, p_session_id: String?, p_score: Int, p_max_combo: Int, p_taps: Int, p_perfects: Int
        }
        let params = Params(p_duel_id: duelId.lowercased(), p_session_id: sessionId, p_score: max(score, 0),
                            p_max_combo: max(maxCombo, 0), p_taps: max(taps, 0), p_perfects: max(perfects, 0))
        // Idempotent server-side (second call returns duplicate:true), so retries are safe.
        return await withRetry("submit_duel_score", attempts: 5) {
            try await self.client.rpc("submit_duel_score", params: params).execute()
        }
    }

    // MARK: - Friends

    func loadFriendUIDs() async -> [String] {
        guard let uid = currentUID,
              let rows = await selectRows(client.from("friendships").select("user_a,user_b"))
        else { return [] }
        return rows.compactMap { row in
            let a = (row["user_a"] as? String)?.lowercased(), b = (row["user_b"] as? String)?.lowercased()
            return a == uid ? b : a
        }
    }

    func sendFriendRequest(friendCode: String) async throws {
        guard currentUID != nil else { throw BackendError.notSignedIn }
        let id: String?
        do {
            id = try await client.rpc("send_friend_request", params: ["p_friend_code": friendCode]).execute().value
        } catch { throw mapRPCError(error) }
        if id == nil { throw BackendError.notFound("Player not found") }
    }

    func loadIncomingFriendRequests() async -> [FriendRequest] {
        guard let uid = currentUID else { return [] }
        return await friendRequests(column: "to_uid", uid: uid)
    }

    func loadOutgoingFriendRequests() async -> [FriendRequest] {
        guard let uid = currentUID else { return [] }
        return await friendRequests(column: "from_uid", uid: uid)
    }

    private func friendRequests(column: String, uid: String) async -> [FriendRequest] {
        let rows = await selectRows(client.from("friend_requests").select()
            .eq(column, value: uid).eq("status", value: "pending")
            .order("created_at", ascending: false)) ?? []
        return rows.compactMap { FriendRequest(id: ($0["id"] as? String ?? "").lowercased(), data: Self.lowercasedIDs($0)) }
    }

    func acceptFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = currentUID, uid == request.toUID else { throw BackendError.server("Not authorized") }
        struct Params: Encodable { let p_request_id: String; let p_accept: Bool }
        do {
            try await client.rpc("respond_friend_request", params: Params(p_request_id: request.id, p_accept: true)).execute()
        } catch { throw mapRPCError(error) }
        var profile = PlayerProfile.load() ?? PlayerProfile()
        if !profile.friends.contains(request.fromUID) {
            profile.friends.append(request.fromUID)
            profile.save()
        }
    }

    func rejectFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = currentUID, uid == request.toUID else { return }
        struct Params: Encodable { let p_request_id: String; let p_accept: Bool }
        do {
            try await client.rpc("respond_friend_request", params: Params(p_request_id: request.id, p_accept: false)).execute()
        } catch { throw mapRPCError(error) }
    }

    func cancelFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = currentUID, uid == request.fromUID else { return }
        do {
            try await client.rpc("cancel_friend_request", params: ["p_request_id": request.id]).execute()
        } catch { throw mapRPCError(error) }
    }

    func listenIncomingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        return RealtimeQueryListener(
            client: client, topic: "fr-in-\(uid)-\(UUID().uuidString.prefix(6))", table: "friend_requests", filter: .eq("to_uid", value: uid),
            reload: { [weak self] in await self?.loadIncomingFriendRequests() ?? [] }, deliver: onChange)
    }

    func listenOutgoingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        return RealtimeQueryListener(
            client: client, topic: "fr-out-\(uid)-\(UUID().uuidString.prefix(6))", table: "friend_requests", filter: .eq("from_uid", value: uid),
            reload: { [weak self] in await self?.loadOutgoingFriendRequests() ?? [] }, deliver: onChange)
    }

    // MARK: - Duel invitations

    private static let outgoingStatuses = ["pending", "accepted", "in_progress", "rejected", "cancelled", "expired"]

    func sendDuelInvitation(toUID: String, toUsername: String, toAvatar: String, mode: GameMode) async throws -> DuelInvitation {
        guard let uid = currentUID else { throw BackendError.notSignedIn }
        guard uid != toUID.lowercased() else { throw BackendError.server("Can't invite yourself") }
        struct Params: Encodable { let p_to_uid: String; let p_mode: String }
        do {
            let data = try await client.rpc("send_duel_invitation",
                                            params: Params(p_to_uid: toUID.lowercased(), p_mode: mode.rawValue)).execute().data
            guard let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let invite = DuelInvitation(id: (row["id"] as? String ?? "").lowercased(), data: Self.lowercasedIDs(row))
            else { throw BackendError.server("Could not send invite") }
            return invite
        } catch { throw mapRPCError(error) }
    }

    func loadIncomingDuelInvitations() async -> [DuelInvitation] {
        guard let uid = currentUID else { return [] }
        return await invitations(client.from("duel_invitations").select()
            .eq("to_uid", value: uid).eq("status", value: "pending")
            .order("created_at", ascending: false))
    }

    func loadOutgoingDuelInvitations() async -> [DuelInvitation] {
        guard let uid = currentUID else { return [] }
        return await invitations(client.from("duel_invitations").select()
            .eq("from_uid", value: uid).in("status", values: Self.outgoingStatuses)
            .order("created_at", ascending: false).limit(100))
    }

    private func invitations(_ query: PostgrestTransformBuilder) async -> [DuelInvitation] {
        let rows = await selectRows(query) ?? []
        return rows.compactMap { DuelInvitation(id: ($0["id"] as? String ?? "").lowercased(), data: Self.lowercasedIDs($0)) }
    }

    func acceptDuelInvitation(_ invitation: DuelInvitation) async throws {
        guard let uid = currentUID, uid == invitation.toUID else { return }
        if invitation.isExpired { throw BackendError.server("Invitation has expired") }
        do {
            try await client.rpc("accept_duel_invitation", params: ["p_invitation_id": invitation.id]).execute()
        } catch { throw mapRPCError(error) }
    }

    func markDuelInvitationInProgress(_ invitationId: String) async -> Bool {
        (try? await client.rpc("mark_duel_invitation_in_progress",
                               params: ["p_invitation_id": invitationId]).execute().value as Bool) ?? false
    }

    func rejectDuelInvitation(_ invitation: DuelInvitation) async throws {
        guard let uid = currentUID, uid == invitation.toUID else { return }
        do {
            try await client.rpc("reject_duel_invitation", params: ["p_invitation_id": invitation.id]).execute()
        } catch { throw mapRPCError(error) }
    }

    func cancelDuelInvitation(_ invitation: DuelInvitation) async throws {
        guard let uid = currentUID, uid == invitation.fromUID else { return }
        do {
            try await client.rpc("cancel_duel_invitation", params: ["p_invitation_id": invitation.id]).execute()
        } catch { throw mapRPCError(error) }
    }

    func listenIncomingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        return RealtimeQueryListener(
            client: client, topic: "inv-in-\(uid)-\(UUID().uuidString.prefix(6))", table: "duel_invitations", filter: .eq("to_uid", value: uid),
            reload: { [weak self] in await self?.loadIncomingDuelInvitations() ?? [] }, deliver: onChange)
    }

    func listenOutgoingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        return RealtimeQueryListener(
            client: client, topic: "inv-out-\(uid)-\(UUID().uuidString.prefix(6))", table: "duel_invitations",
            filter: .eq("from_uid", value: uid),
            reload: { [weak self] in await self?.loadOutgoingDuelInvitations() ?? [] }, deliver: onChange)
    }

    func listenOutgoingDuelInvitation(toUID: String, onChange: @escaping (DuelInvitation?) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        let target = toUID.lowercased()
        return RealtimeQueryListener(
            client: client, topic: "inv-to-\(target)-\(UUID().uuidString.prefix(6))", table: "duel_invitations",
            filter: .eq("from_uid", value: uid),
            reload: { [weak self] () async -> DuelInvitation? in
                guard let self else { return nil }
                return await self.invitations(self.client.from("duel_invitations").select()
                    .eq("from_uid", value: uid).eq("to_uid", value: target)
                    .in("status", values: Self.outgoingStatuses)
                    .order("created_at", ascending: false).limit(1)).first
            },
            deliver: onChange)
    }

    func loadDuelInvitation(id: String) async -> DuelInvitation? {
        guard UUID(uuidString: id) != nil else { return nil }
        return await invitations(client.from("duel_invitations").select().eq("id", value: id.lowercased()).limit(1)).first
    }

    func hasPendingDuelInvite(withUID otherUID: String) async -> DuelInvitation? {
        guard let uid = currentUID else { return nil }
        let other = otherUID.lowercased()
        guard UUID(uuidString: other) != nil else { return nil }
        return await invitations(client.from("duel_invitations").select()
            .eq("status", value: "pending")
            .or("and(from_uid.eq.\(uid),to_uid.eq.\(other)),and(from_uid.eq.\(other),to_uid.eq.\(uid))")
            .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
            .order("created_at", ascending: false).limit(1)).first
    }

    func removeListener(_ listener: Any?) {
        (listener as? RealtimeListenerHandle)?.cancel()
    }

    // MARK: - Helpers

    private func selectRows(_ query: PostgrestTransformBuilder) async -> [[String: Any]]? {
        guard let data = try? await query.execute().data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    /// Postgres UUIDs are lowercase already; normalise defensively for == checks.
    private static func lowercasedIDs(_ row: [String: Any]) -> [String: Any] {
        var r = row
        for key in ["from_uid", "to_uid", "duel_id"] {
            if let s = r[key] as? String { r[key] = s.lowercased() }
        }
        return r
    }

    /// Retries transient (network / 5xx) failures with backoff. Business-rule
    /// errors are final and only logged.
    @discardableResult
    private func withRetry(_ label: String, attempts: Int = 3, _ op: @escaping () async throws -> Void) async -> Bool {
        for attempt in 0..<attempts {
            do { try await op(); return true } catch {
                let transient = isNetworkError(error)
                log("\(label) failed (attempt \(attempt + 1), transient=\(transient)): \(error.localizedDescription)")
                guard transient, attempt < attempts - 1 else { return false }
                try? await Task.sleep(nanoseconds: UInt64(1 << attempt) * 1_000_000_000)
            }
        }
        return false
    }

    private func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return true
            default: return false
            }
        }
        if case FunctionsError.httpError(let code, _) = error { return code >= 500 }
        if case FunctionsError.relayError = error { return true }
        return false
    }

    /// Maps the stable error codes raised by private.fail() to UI copy.
    private func mapRPCError(_ error: Error) -> Error {
        if error is BackendError { return error }
        if isNetworkError(error) { return BackendError.network }
        let code = (error as? PostgrestError)?.message ?? ""
        return Self.backendError(forCode: code)
    }

    static func backendError(forCode code: String) -> BackendError {
        switch code {
        case "not_authenticated": return .notSignedIn
        case "rate_limited": return .rateLimited
        case "duel_not_found", "duel_unavailable", "duel_expired": return .notFound("Duel not found")
        case "cannot_join_own_duel": return .server("You can't join your own duel")
        case "username_required": return .server("Choose a username first")
        case "too_many_open_duels": return .server("You have too many open duels. Finish or wait for one to expire.")
        case "player_not_found": return .notFound("Player not found")
        case "cannot_add_self": return .server("You can't add yourself")
        case "already_friends": return .server("Already friends")
        case "request_pending": return .server("A pending request already exists")
        case "request_not_found", "request_not_pending": return .server("Request no longer pending")
        case "not_friends": return .server("You can only invite friends")
        case "invite_pending": return .server("A pending duel invite already exists")
        case "invitation_expired": return .server("Invitation has expired")
        case "invitation_not_found", "invitation_not_pending": return .server("Invitation is no longer available")
        case "cannot_invite_self": return .server("Can't invite yourself")
        case "username_taken": return .server("That username is already taken. Try another.")
        default: return .server("Something went wrong. Please try again.")
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[SupabaseService] \(message)")
        #endif
    }
}

// MARK: - Configuration
/// Public client configuration only (URL + publishable key), injected through
/// build settings → Info.plist. Never put a secret/service-role key here.
struct SupabaseConfig {
    let url: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> SupabaseConfig? {
        var rawURL = (bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        var key = (bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        #if DEBUG
        // Simulator runs against the local stack: SIMCTL_CHILD_SUPABASE_URL=http://127.0.0.1:55621 …
        let env = ProcessInfo.processInfo.environment
        if let u = env["SUPABASE_URL"], !u.isEmpty { rawURL = u }
        if let k = env["SUPABASE_PUBLISHABLE_KEY"], !k.isEmpty { key = k }
        #endif
        guard let url = URL(string: rawURL), url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost",
              !key.isEmpty, !key.hasPrefix("sb_secret_") else { return nil }
        return SupabaseConfig(url: url, publishableKey: key)
    }
}

// MARK: - Realtime listener
@MainActor
protocol RealtimeListenerHandle: AnyObject {
    func cancel()
}

/// Subscribes to Postgres Changes for one filtered table and, on every event
/// and every (re)subscribe, reloads the authoritative query and delivers it.
/// While the channel is not subscribed (offline / reconnecting) it falls back
/// to a slow poll; a healthy subscription never polls.
@MainActor
final class RealtimeQueryListener<Value>: RealtimeListenerHandle {
    private var task: Task<Void, Never>?
    private var channel: RealtimeChannelV2?
    private let client: SupabaseClient
    private var isSubscribed = false

    private static var fallbackPollSeconds: UInt64 { 20 }

    init(client: SupabaseClient, topic: String, table: String, filter: RealtimePostgresFilter,
         reload: @escaping @MainActor () async -> Value, deliver: @escaping (Value) -> Void) {
        self.client = client
        let channel = client.channel(topic)
        self.channel = channel
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table, filter: filter)
        let statuses = channel.statusChange

        task = Task { @MainActor [weak self] in
            // Initial authoritative state.
            deliver(await reload())

            await withTaskGroup(of: Void.self) { group in
                // Change events → reload (coalesced: one reload in flight at a time).
                group.addTask { @MainActor in
                    for await _ in changes {
                        guard !Task.isCancelled else { return }
                        deliver(await reload())
                    }
                }
                // Every (re)subscribe → reload, covering events missed while disconnected.
                group.addTask { @MainActor in
                    var first = true
                    for await status in statuses {
                        guard !Task.isCancelled else { return }
                        self?.isSubscribed = status == .subscribed
                        guard status == .subscribed else { continue }
                        if first { first = false; continue }   // initial load already done
                        deliver(await reload())
                    }
                }
                // Safety net only while NOT subscribed (offline/reconnecting): slow poll.
                // A healthy subscription never polls.
                group.addTask { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: Self.fallbackPollSeconds * 1_000_000_000)
                        guard !Task.isCancelled, let self else { return }
                        if !self.isSubscribed { deliver(await reload()) }
                    }
                }
                group.addTask {
                    do { try await channel.subscribeWithError() } catch {
                        #if DEBUG
                        print("[RealtimeQueryListener] subscribe \(topic) failed: \(error.localizedDescription)")
                        #endif
                    }
                }
                await group.waitForAll()
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if let channel {
            self.channel = nil
            let client = self.client
            Task { await client.removeChannel(channel) }
        }
    }

    deinit {
        task?.cancel()
    }
}
