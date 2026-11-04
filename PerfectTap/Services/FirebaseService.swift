import Foundation

// MARK: - FirebaseService
// All Firestore + Firebase Auth calls live here.
// Uses Firebase Anonymous Auth so every user has a valid auth token
// for Firestore security rules (request.auth != null).

#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
#endif

@MainActor
final class FirebaseService {

    static let shared = FirebaseService()
    private init() {}
    private var profileSaveChain: Task<Void, Never>? = nil
    private var cachedAuthoritativeDayKey: String? = nil
    private var authoritativeDayFetchedAt: Date? = nil
    private static let lastKnownServerDayDefaultsKey = "perfecttap_last_known_server_day"
    private static let serverDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum AuthoritativeDaySource: String {
        case liveServer
        case inMemoryCache
        case persistedCache
    }

    enum AuthoritativeDayFailureReason: Equatable {
        case noInternet
        case firebaseNotConfigured
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

    // MARK: - Auth

    /// Signs in anonymously — gives every user a valid Firebase Auth token
    /// without requiring email/password. Called at app startup.
    func signInAnonymously() async -> String? {
        #if canImport(FirebaseAuth)
        // If already signed in (anonymous or email), reuse that session
        if let user = Auth.auth().currentUser {
            return user.uid
        }
        do {
            let result = try await Auth.auth().signInAnonymously()
            return result.user.uid
        } catch {
            #if DEBUG
            print("[FirebaseService] Anonymous sign-in failed: \(error.localizedDescription)")
            #endif
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Links the current anonymous account to an email/password credential.
    /// This upgrades the anonymous user to a permanent account while keeping the same UID.
    func linkAnonymousAccount(email: String, password: String) async throws -> String {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "PerfectTap", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No active session"])
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        if user.isAnonymous {
            // Link anonymous → email (keeps same UID, no data migration needed)
            let result = try await user.link(with: credential)
            return result.user.uid
        } else {
            // Already linked — just return current UID
            return user.uid
        }
        #else
        return UUID().uuidString
        #endif
    }

    /// Signs in with email/password. Used when user already has an account
    /// on another device and wants to restore their data.
    func signInWithEmail(email: String, password: String) async throws -> String {
        #if canImport(FirebaseAuth)
        // If currently anonymous, we need to delete the anonymous account first
        // to avoid orphaned data, then sign in with the real account
        let previousUID = Auth.auth().currentUser?.uid
        let wasAnonymous = Auth.auth().currentUser?.isAnonymous ?? false

        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        let newUID = result.user.uid

        // Clean up orphaned anonymous player document
        if wasAnonymous, let oldUID = previousUID, oldUID != newUID {
            let db = Firestore.firestore()
            try? await db.collection("players").document(oldUID).delete()
        }

        return newUID
        #else
        return UUID().uuidString
        #endif
    }

    func signOut() {
        #if canImport(FirebaseAuth)
        try? Auth.auth().signOut()
        #endif
    }

    /// Result of a delete-account attempt.
    enum DeleteResult {
        case success                 // Auth user + Firestore doc both deleted
        case requiresReauth          // Firestore doc deleted, but Auth user needs re-authentication
        case noUser                  // No Auth user was signed in
    }

    /// Deletes the current user's Firestore player document and Firebase Auth account.
    /// Only deletes `players/{authUID}` — the document whose ID matches the
    /// current Firebase Auth user. Firestore security rules enforce this:
    ///   allow delete: if request.auth.uid == userId;
    ///
    /// For linked email/password users, Firebase requires recent authentication
    /// before allowing `user.delete()`. If that requirement isn't met, this
    /// returns `.requiresReauth` so the caller can prompt for the password
    /// and call `reauthenticateAndDelete(email:password:)`.
    func deleteCurrentAccount() async -> DeleteResult {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            #if DEBUG
            print("[FirebaseService] deleteCurrentAccount: no Auth user — nothing to delete")
            #endif
            return .noUser
        }
        let authUID = user.uid
        #else
        return .noUser
        #endif

        // 1. Delete the player document for the current Auth user
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        do {
            try await db.collection("players").document(authUID).delete()
            #if DEBUG
            print("[FirebaseService] Deleted players/\(authUID)")
            #endif
        } catch {
            #if DEBUG
            print("[FirebaseService] Failed to delete players/\(authUID): \(error.localizedDescription)")
            #endif
        }
        #endif

        // 2. Delete Firebase Auth account
        #if canImport(FirebaseAuth)
        do {
            try await user.delete()
            #if DEBUG
            print("[FirebaseService] Deleted Auth user \(authUID)")
            #endif
            return .success
        } catch let error as NSError {
            #if DEBUG
            print("[FirebaseService] Auth deletion failed — domain: \(error.domain), code: \(error.code), message: \(error.localizedDescription)")
            #endif
            // Firebase error 17014 = requiresRecentLogin
            if error.code == 17014 {
                // Don't sign out yet — we need the user session for re-auth
                return .requiresReauth
            }
            // Other error — sign out so a fresh anonymous user can be created
            try? Auth.auth().signOut()
            return .success // Firestore doc was deleted; Auth cleanup is best-effort
        }
        #endif
    }

    /// Re-authenticates the current email/password user, then deletes their Auth account.
    /// Called after `deleteCurrentAccount()` returns `.requiresReauth`.
    func reauthenticateAndDelete(email: String, password: String) async -> Bool {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            #if DEBUG
            print("[FirebaseService] reauthenticateAndDelete: no Auth user")
            #endif
            return false
        }
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
            #if DEBUG
            print("[FirebaseService] Re-authenticated user \(user.uid)")
            #endif
            try await user.delete()
            #if DEBUG
            print("[FirebaseService] Deleted Auth user \(user.uid) after re-auth")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[FirebaseService] Re-auth + delete failed: \(error.localizedDescription)")
            #endif
            // Even if re-auth fails, sign out so user can start fresh
            try? Auth.auth().signOut()
            return false
        }
        #else
        return false
        #endif
    }

    /// Returns the email address of the current user, if linked to email/password.
    var currentUserEmail: String? {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return nil }
        return user.email
        #else
        return nil
        #endif
    }

    /// Whether the current user has linked an email (not anonymous)
    var isLinkedToEmail: Bool {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { return false }
        return !user.isAnonymous
        #else
        return false
        #endif
    }

    var currentUID: String? {
        #if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.uid
        #else
        return PlayerProfile.load()?.uid
        #endif
    }

    // MARK: - Authoritative day key (server-backed)

    /// Returns a UTC day key (`yyyy-MM-dd`) based on Firestore server time.
    /// Falls back to last known successful server day key when offline.
    func authoritativeDayKey(forceRefresh: Bool = false) async -> String? {
        let result = await authoritativeDayVerification(forceRefresh: forceRefresh)
        return result.dayKey
    }

    /// Returns authoritative UTC day key + source/failure classification for UI handling.
    func authoritativeDayVerification(forceRefresh: Bool = false) async -> AuthoritativeDayVerificationResult {
        if !forceRefresh,
           let cached = cachedAuthoritativeDayKey,
           let fetchedAt = authoritativeDayFetchedAt,
           Date().timeIntervalSince(fetchedAt) < 60 {
            #if DEBUG
            print("[FirebaseService][ServerDay] using in-memory cache day=\(cached)")
            #endif
            return AuthoritativeDayVerificationResult(
                dayKey: cached,
                source: .inMemoryCache,
                failureReason: nil,
                usedFallback: false
            )
        }

        let fetchResult = await fetchServerDayKey()
        switch fetchResult {
        case .success(let serverDay):
            cacheAuthoritativeDay(serverDay)
            #if DEBUG
            print("[FirebaseService][ServerDay] live server day success day=\(serverDay)")
            #endif
            return AuthoritativeDayVerificationResult(
                dayKey: serverDay,
                source: .liveServer,
                failureReason: nil,
                usedFallback: false
            )
        case .failure(let failure):
            if let cached = cachedAuthoritativeDayKey {
                #if DEBUG
                print("[FirebaseService][ServerDay] live fetch failed (\(failure.rawValue)); fallback=in-memory day=\(cached)")
                #endif
                return AuthoritativeDayVerificationResult(
                    dayKey: cached,
                    source: .inMemoryCache,
                    failureReason: failure.reason,
                    usedFallback: true
                )
            }

            if let persisted = UserDefaults.standard.string(forKey: Self.lastKnownServerDayDefaultsKey),
               !persisted.isEmpty {
                cachedAuthoritativeDayKey = persisted
                #if DEBUG
                print("[FirebaseService][ServerDay] live fetch failed (\(failure.rawValue)); fallback=persisted day=\(persisted)")
                #endif
                return AuthoritativeDayVerificationResult(
                    dayKey: persisted,
                    source: .persistedCache,
                    failureReason: failure.reason,
                    usedFallback: true
                )
            }

            #if DEBUG
            print("[FirebaseService][ServerDay] live fetch failed (\(failure.rawValue)); no fallback cache available")
            #endif
            return AuthoritativeDayVerificationResult(
                dayKey: nil,
                source: nil,
                failureReason: failure.reason,
                usedFallback: false
            )
        }
    }

    private func cacheAuthoritativeDay(_ dayKey: String) {
        cachedAuthoritativeDayKey = dayKey
        authoritativeDayFetchedAt = Date()
        UserDefaults.standard.set(dayKey, forKey: Self.lastKnownServerDayDefaultsKey)
    }

    private struct ServerDayFetchFailure: Error {
        let reason: AuthoritativeDayFailureReason
        let rawValue: String
    }

    private func fetchServerDayKey() async -> Result<String, ServerDayFetchFailure> {
        #if canImport(FirebaseFirestore)
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() != nil else {
            return .failure(
                ServerDayFetchFailure(
                    reason: .firebaseNotConfigured,
                    rawValue: "FirebaseApp not configured"
                )
            )
        }
        #endif

        _ = await signInAnonymously()
        guard let uid = currentUID, !uid.isEmpty else {
            return .failure(
                ServerDayFetchFailure(
                    reason: .authUnavailable,
                    rawValue: "Missing Firebase Auth UID after anonymous sign-in"
                )
            )
        }

        #if DEBUG
        print("[FirebaseService][ServerDay] firebaseConfigured=true uid=\(uid)")
        #endif
        let db = Firestore.firestore()
        let ref = db.collection("players").document(uid)
        let probeField = "server_day_probe_ts"
        do {
            try await ref.setData([probeField: FieldValue.serverTimestamp()], merge: true)
            let snap = try await ref.getDocument(source: .server)
            if let timestamp = snap.data()?[probeField] as? Timestamp {
                return .success(Self.serverDayFormatter.string(from: timestamp.dateValue()))
            }
            return .failure(
                ServerDayFetchFailure(
                    reason: .serverTimestampMissing,
                    rawValue: "Missing or invalid \(probeField) timestamp"
                )
            )
        } catch {
            let reason = classifyServerDayError(error)
            #if DEBUG
            let nsError = error as NSError
            print("[FirebaseService][ServerDay] fetch failed domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
            #endif
            return .failure(
                ServerDayFetchFailure(
                    reason: reason,
                    rawValue: (error as NSError).localizedDescription
                )
            )
        }
        #else
        return .failure(
            ServerDayFetchFailure(
                reason: .firebaseNotConfigured,
                rawValue: "Firebase Firestore SDK unavailable in build"
            )
        )
        #endif
    }

    private func classifyServerDayError(_ error: Error) -> AuthoritativeDayFailureReason {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorDataNotAllowed:
                return .noInternet
            default:
                break
            }
        }

        #if canImport(FirebaseFirestore)
        // gRPC status codes used by Firestore (permissionDenied=7, deadlineExceeded=4,
        // unavailable=14, unauthenticated=16).
        switch nsError.code {
        case 7:
            return .permissionDenied
        case 16:
            return .authUnavailable
        case 4, 14:
            return .noInternet
        default:
            break
        }
        #endif

        return .unknown
    }

    // MARK: - Username Uniqueness Check

    /// Checks if a username is available (case-insensitive).
    /// Queries the `username_lower` field which stores the lowercased version.
    /// Excludes the current user's own document so they don't block themselves.
    func isUsernameAvailable(_ username: String) async -> Bool {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let lower = username.lowercased()
        let snap = try? await db.collection("players")
            .whereField("username_lower", isEqualTo: lower)
            .limit(to: 1)
            .getDocuments()
        // If a document exists, check it's not the current user's own doc
        if let docs = snap?.documents, !docs.isEmpty {
            if let myUID = currentUID, docs.count == 1, docs[0].documentID == myUID {
                return true // it's our own document — username is "available" (unchanged)
            }
            return false
        }
        return true
        #else
        return true
        #endif
    }

    // MARK: - Player Profile (Firestore: players/{uid})

    func loadProfile() async -> PlayerProfile? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("players").document(uid).getDocument(),
              snap.exists,
              let data = snap.data()
        else { return nil }
        return decode(data)
        #else
        return PlayerProfile.load()
        #endif
    }

    func saveProfile(_ profile: PlayerProfile) async {
        guard let uid = currentUID else { return }
        profile.save()   // always write to UserDefaults first
        #if canImport(FirebaseFirestore)
        let data = encode(profile)
        // Serialize writes in-order so stale snapshots can't overwrite fresh state.
        let previous = profileSaveChain
        profileSaveChain = Task { @MainActor in
            if let previous { await previous.value }
            guard self.currentUID == uid else { return }
            let db = Firestore.firestore()
            try? await db.collection("players").document(uid).setData(data, merge: true)
        }
        #endif
    }

    // MARK: - Score submission (calls Cloud Function for server-side validation)
    func submitScore(mode: GameMode, score: Int, maxCombo: Int, profile: PlayerProfile) async {
        #if canImport(FirebaseFunctions)
        let functions = Functions.functions()
        let data: [String: Any] = [
            "mode": mode.rawValue,
            "score": score,
            "maxCombo": maxCombo
        ]
        _ = try? await functions.httpsCallable("submitScore").call(data)
        #endif
    }

    // MARK: - Duel operations (direct Firestore — no Cloud Functions needed)

    func createDuel(hostName: String, hostAvatar: String?, mode: GameMode = .duel) async throws -> (duelId: String, code: String) {
        #if canImport(FirebaseFirestore)
        guard let uid = currentUID else {
            throw NSError(domain: "PerfectTap", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let db = Firestore.firestore()
        let code = generateDuelCode()
        var duelData: [String: Any] = [
            "code": code,
            "host_id": uid,
            "host_name": hostName,
            "mode": mode.rawValue,
            "status": "waiting",
            "created_at": FieldValue.serverTimestamp()
        ]
        if let avatar = hostAvatar { duelData["host_avatar"] = avatar }
        let docRef = try await db.collection("duels").addDocument(data: duelData)
        return (docRef.documentID, code)
        #else
        return (UUID().uuidString, "TEST01")
        #endif
    }

    func joinDuel(code: String, guestName: String, guestAvatar: String?) async throws -> (duelId: String, hostName: String) {
        #if canImport(FirebaseFirestore)
        guard let uid = currentUID else {
            throw NSError(domain: "PerfectTap", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let db = Firestore.firestore()
        // Find candidate duel by code first; joining is finalized in a transaction.
        let snap = try await db.collection("duels")
            .whereField("code", isEqualTo: code.uppercased())
            .whereField("status", isEqualTo: "waiting")
            .limit(to: 1)
            .getDocuments()
        guard let docRef = snap.documents.first?.reference else {
            throw NSError(domain: "PerfectTap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Duel not found"])
        }
        let hostNameAny = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snap = try transaction.getDocument(docRef)
                let data = snap.data() ?? [:]
                let status = data["status"] as? String ?? ""
                let guestId = data["guest_id"] as? String ?? ""

                guard status == "waiting", guestId.isEmpty else {
                    errorPointer?.pointee = NSError(
                        domain: "PerfectTap",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Duel already joined"]
                    )
                    return nil
                }

                var guestData: [String: Any] = [
                    "guest_id": uid,
                    "guest_name": guestName,
                    "status": "in_progress"
                ]
                if let avatar = guestAvatar { guestData["guest_avatar"] = avatar }
                transaction.updateData(guestData, forDocument: docRef)
                return data["host_name"] as? String ?? "Opponent"
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }

        guard let hostName = hostNameAny as? String else {
            throw NSError(domain: "PerfectTap", code: 3, userInfo: [NSLocalizedDescriptionKey: "Duel already joined"])
        }

        return (docRef.documentID, hostName)
        #else
        return (UUID().uuidString, "Opponent")
        #endif
    }

    /// Generates a random 6-character duel code
    private func generateDuelCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement() ?? "A" })
    }

    private func normalizedDuelScore(_ raw: Any?) -> Int? {
        guard let score = intValue(raw), Duel.scoreCountsAsFinished(score) else { return nil }
        return score
    }

    private func decodeDuel(id: String, data: [String: Any]) -> Duel {
        var duel = Duel()
        duel.id = id
        duel.code = data["code"] as? String ?? ""
        duel.hostId = data["host_id"] as? String ?? ""
        duel.hostName = data["host_name"] as? String ?? ""
        duel.hostAvatar = data["host_avatar"] as? String
        duel.hostScore = normalizedDuelScore(data["host_score"])
        duel.hostCombo = intValue(data["host_combo"])
        duel.guestId = data["guest_id"] as? String
        duel.guestName = data["guest_name"] as? String
        duel.guestAvatar = data["guest_avatar"] as? String
        duel.guestScore = normalizedDuelScore(data["guest_score"])
        duel.guestCombo = intValue(data["guest_combo"])
        duel.mode = GameMode(rawValue: data["mode"] as? String ?? "") ?? .duel
        duel.status = Duel.DuelStatus(rawValue: data["status"] as? String ?? "waiting") ?? .waiting
        if let createdAt = dateValue(data["created_at"]) {
            duel.createdAt = createdAt
        }
        return duel
    }

    private func dateValue(_ raw: Any?) -> Date? {
        if let d = raw as? Date { return d }
        #if canImport(FirebaseFirestore)
        if let ts = raw as? Timestamp { return ts.dateValue() }
        #endif
        return nil
    }

    func loadDuel(duelId: String) async -> Duel? {
        guard !duelId.isEmpty else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("duels").document(duelId).getDocument(),
              let data = snap.data() else { return nil }
        return decodeDuel(id: duelId, data: data)
        #else
        return nil
        #endif
    }

    func loadDuels(duelIds: [String]) async -> [String: Duel] {
        let deduped = Array(Set(duelIds.filter { !$0.isEmpty }))
        guard !deduped.isEmpty else { return [:] }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        var result: [String: Duel] = [:]
        var index = 0
        while index < deduped.count {
            let upper = min(index + 10, deduped.count)
            let batch = Array(deduped[index..<upper])
            if let snap = try? await db.collection("duels")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments() {
                for doc in snap.documents {
                    result[doc.documentID] = decodeDuel(id: doc.documentID, data: doc.data())
                }
            }
            index = upper
        }
        return result
        #else
        return [:]
        #endif
    }

    func listenDuel(duelId: String, onChange: @escaping (Duel?) -> Void) -> Any? {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let listener = db.collection("duels").document(duelId).addSnapshotListener { snap, _ in
            guard let data = snap?.data() else { onChange(nil); return }
            onChange(self.decodeDuel(id: duelId, data: data))
        }
        return listener
        #else
        return nil
        #endif
    }

    func removeDuelListener(_ listener: Any?) {
        #if canImport(FirebaseFirestore)
        (listener as? ListenerRegistration)?.remove()
        #endif
    }

    func submitDuelScore(duelId: String, role: String, score: Int, maxCombo: Int) async {
        #if canImport(FirebaseFirestore)
        guard !duelId.isEmpty else { return }
        guard role == DuelContext.Role.host.rawValue || role == DuelContext.Role.guest.rawValue else { return }

        let db = Firestore.firestore()
        let duelRef = db.collection("duels").document(duelId)
        let submittedScore = max(score, 0)
        let submittedCombo = max(maxCombo, 0)

        _ = try? await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snap = try transaction.getDocument(duelRef)
                guard snap.exists, let data = snap.data() else { return nil }

                let hostScore = self.intValue(data["host_score"])
                let guestScore = self.intValue(data["guest_score"])
                let hostFinished = Duel.scoreCountsAsFinished(hostScore)
                let guestFinished = Duel.scoreCountsAsFinished(guestScore)
                var updates: [String: Any] = [:]

                if role == DuelContext.Role.host.rawValue {
                    if hostFinished { return nil } // already submitted; no overwrite
                    updates["host_score"] = submittedScore
                    updates["host_combo"] = submittedCombo
                    if guestFinished {
                        updates["status"] = Duel.DuelStatus.completed.rawValue
                    }
                } else {
                    if guestFinished { return nil } // already submitted; no overwrite
                    updates["guest_score"] = submittedScore
                    updates["guest_combo"] = submittedCombo
                    if hostFinished {
                        updates["status"] = Duel.DuelStatus.completed.rawValue
                    }
                }

                guard !updates.isEmpty else { return nil }
                transaction.updateData(updates, forDocument: duelRef)
                return nil
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }
        #endif
    }

    // MARK: - Leaderboard
    func loadLeaderboard(mode: GameMode, limit: Int = 20) async -> [(username: String, score: Int)] {
        #if canImport(FirebaseFirestore)
        guard !Task.isCancelled else { return [] }
        let db = Firestore.firestore()
        let field = mode.bestScoreKey
        guard !field.isEmpty else { return [] }
        guard let snap = try? await db.collection("players")
            .order(by: field, descending: true)
            .limit(to: limit)
            .getDocuments()
        else { return [] }
        guard !Task.isCancelled else { return [] }
        return snap.documents.compactMap { doc in
            let data = doc.data()
            guard let username = data["username"] as? String,
                  let score = data[field] as? Int else { return nil }
            return (username, score)
        }
        #else
        return []
        #endif
    }

    func loadFriendsLeaderboard(friendUIDs: [String], mode: GameMode) async -> [(username: String, score: Int)] {
        guard !friendUIDs.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }
        let profiles = await loadFriendProfiles(uids: friendUIDs)
        guard !Task.isCancelled else { return [] }
        return profiles
            .map { (username: $0.username, score: $0.bestScore(for: mode)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
    }

    // MARK: - Friends (canonical: friendships collection)

    func loadFriendProfiles(uids: [String]) async -> [PlayerProfile] {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        var profiles: [PlayerProfile] = []
        for uid in uids {
            guard !Task.isCancelled else { return profiles }
            if let snap = try? await db.collection("players").document(uid).getDocument(),
               let data = snap.data(), let p = decode(data) {
                profiles.append(p)
            }
        }
        return profiles
        #else
        return []
        #endif
    }

    /// Loads a single player profile by UID
    func loadPlayerProfile(uid: String) async -> PlayerProfile? {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("players").document(uid).getDocument(),
              let data = snap.data() else { return nil }
        return decode(data)
        #else
        return nil
        #endif
    }

    /// Returns all canonical friend UIDs from the friendships collection
    func loadFriendUIDs() async -> [String] {
        guard let uid = currentUID else { return [] }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        // Query friendships where current user is a participant
        guard let snap = try? await db.collection("friendships")
            .whereField("user_ids", arrayContains: uid)
            .getDocuments()
        else { return [] }
        var friendUIDs: [String] = []
        for doc in snap.documents {
            let userIDs = doc.data()["user_ids"] as? [String] ?? []
            if let friendUID = userIDs.first(where: { $0 != uid }) {
                friendUIDs.append(friendUID)
            }
        }
        return friendUIDs
        #else
        return []
        #endif
    }

    // MARK: - Friend Requests

    /// Send a friend request by friend code. Uses transaction guard to prevent duplicates.
    func sendFriendRequest(friendCode: String) async throws {
        guard let uid = currentUID else {
            throw NSError(domain: "PerfectTap", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        // Look up friend by code
        let snap = try await db.collection("players")
            .whereField("friend_code", isEqualTo: friendCode)
            .limit(to: 1)
            .getDocuments()
        guard let friendDoc = snap.documents.first else {
            throw NSError(domain: "PerfectTap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Player not found"])
        }
        let friendUID = friendDoc.documentID
        guard friendUID != uid else {
            throw NSError(domain: "PerfectTap", code: 3, userInfo: [NSLocalizedDescriptionKey: "You can't add yourself"])
        }

        // Check if friendship already exists (query instead of direct doc read to avoid permission error on non-existent docs)
        let pairId = Friendship.pairId(uid, friendUID)
        let existingFriendships = try await db.collection("friendships")
            .whereField("user_ids", arrayContains: uid)
            .getDocuments()
        let alreadyFriends = existingFriendships.documents.contains { doc in
            guard let userIds = doc.data()["user_ids"] as? [String] else { return false }
            return userIds.contains(friendUID)
        }
        if alreadyFriends {
            throw NSError(domain: "PerfectTap", code: 4, userInfo: [NSLocalizedDescriptionKey: "Already friends"])
        }

        // Transaction: check guard state + create request
        let myProfile = PlayerProfile.load() ?? PlayerProfile()
        let friendData = friendDoc.data()
        let friendUsername = friendData["username"] as? String ?? ""
        let friendAvatar = PlayerProfile.canonicalAvatarID(friendData["equipped_avatar"] as? String ?? (friendData["avatar"] as? String ?? "default"))

        let stateRef = db.collection("friend_request_state").document(pairId)
        let requestRef = db.collection("friend_requests").document()

        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            // Check guard state
            if let stateSnap = try? transaction.getDocument(stateRef),
               stateSnap.exists,
               let stateData = stateSnap.data(),
               stateData["status"] as? String == "pending" {
                errorPointer?.pointee = NSError(domain: "PerfectTap", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "A pending request already exists"])
                return nil
            }

            // Create the friend request
            let requestData: [String: Any] = [
                "from_uid": uid,
                "to_uid": friendUID,
                "from_username": myProfile.username,
                "from_avatar": myProfile.socialAvatarID,
                "to_username": friendUsername,
                "to_avatar": friendAvatar,
                "status": "pending",
                "created_at": FieldValue.serverTimestamp()
            ]
            transaction.setData(requestData, forDocument: requestRef)

            // Set guard state
            let stateData: [String: Any] = [
                "user_ids": [uid, friendUID],
                "pending_request_id": requestRef.documentID,
                "status": "pending"
            ]
            transaction.setData(stateData, forDocument: stateRef)

            return nil
        }
        #endif
    }

    /// Load incoming friend requests (where I am the receiver)
    func loadIncomingFriendRequests() async -> [FriendRequest] {
        guard let uid = currentUID else { return [] }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("friend_requests")
            .whereField("to_uid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "created_at", descending: true)
            .getDocuments()
        else { return [] }
        return snap.documents.compactMap { FriendRequest(id: $0.documentID, data: $0.data()) }
        #else
        return []
        #endif
    }

    /// Load outgoing friend requests (where I am the sender)
    func loadOutgoingFriendRequests() async -> [FriendRequest] {
        guard let uid = currentUID else { return [] }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("friend_requests")
            .whereField("from_uid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "created_at", descending: true)
            .getDocuments()
        else { return [] }
        return snap.documents.compactMap { FriendRequest(id: $0.documentID, data: $0.data()) }
        #else
        return []
        #endif
    }

    /// Accept a friend request — creates canonical friendship + compatibility mirror
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = currentUID, uid == request.toUID else {
            throw NSError(domain: "PerfectTap", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not authorized"])
        }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let pairId = Friendship.pairId(request.fromUID, request.toUID)
        let requestRef = db.collection("friend_requests").document(request.id)
        let friendshipRef = db.collection("friendships").document(pairId)
        let stateRef = db.collection("friend_request_state").document(pairId)

        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            // Verify request is still pending
            guard let reqSnap = try? transaction.getDocument(requestRef),
                  reqSnap.exists,
                  let reqData = reqSnap.data(),
                  reqData["status"] as? String == "pending" else {
                errorPointer?.pointee = NSError(domain: "PerfectTap", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Request no longer pending"])
                return nil
            }

            // Check friendship doesn't already exist (race guard)
            if let fsSnap = try? transaction.getDocument(friendshipRef), fsSnap.exists {
                // Already friends — just mark request accepted
                transaction.updateData(["status": "accepted"], forDocument: requestRef)
                transaction.deleteDocument(stateRef)
                return nil
            }

            // Update request status
            transaction.updateData(["status": "accepted"], forDocument: requestRef)

            // Create canonical friendship
            let friendshipData: [String: Any] = [
                "user_ids": [request.fromUID, request.toUID],
                "created_at": FieldValue.serverTimestamp()
            ]
            transaction.setData(friendshipData, forDocument: friendshipRef)

            // Clear guard state
            transaction.deleteDocument(stateRef)

            return nil
        }

        // Compatibility mirror: write to players.friends arrays (best-effort)
        try? await db.collection("players").document(request.fromUID).updateData([
            "friends": FieldValue.arrayUnion([request.toUID])
        ])
        try? await db.collection("players").document(request.toUID).updateData([
            "friends": FieldValue.arrayUnion([request.fromUID])
        ])

        // Update local profile cache
        var profile = PlayerProfile.load() ?? PlayerProfile()
        if !profile.friends.contains(request.fromUID) {
            profile.friends.append(request.fromUID)
            profile.save()
        }
        #endif
    }

    /// Reject a friend request
    func rejectFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = currentUID, uid == request.toUID else { return }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let pairId = Friendship.pairId(request.fromUID, request.toUID)
        try await db.collection("friend_requests").document(request.id).updateData([
            "status": "rejected"
        ])
        // Clear guard state so a new request can be sent later
        try? await db.collection("friend_request_state").document(pairId).delete()
        #endif
    }

    /// Cancel an outgoing friend request (sender only)
    func cancelFriendRequest(_ request: FriendRequest) async throws {
        guard let uid = currentUID, uid == request.fromUID else { return }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let pairId = Friendship.pairId(request.fromUID, request.toUID)
        try await db.collection("friend_requests").document(request.id).updateData([
            "status": "cancelled"
        ])
        try? await db.collection("friend_request_state").document(pairId).delete()
        #endif
    }

    /// Listen for incoming friend requests (scoped to view visibility)
    func listenIncomingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let listener = db.collection("friend_requests")
            .whereField("to_uid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "created_at", descending: true)
            .addSnapshotListener { snap, _ in
                let requests = snap?.documents.compactMap { FriendRequest(id: $0.documentID, data: $0.data()) } ?? []
                onChange(requests)
            }
        return listener
        #else
        return nil
        #endif
    }

    /// Listen for outgoing friend requests
    func listenOutgoingFriendRequests(onChange: @escaping ([FriendRequest]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let listener = db.collection("friend_requests")
            .whereField("from_uid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "created_at", descending: true)
            .addSnapshotListener { snap, _ in
                let requests = snap?.documents.compactMap { FriendRequest(id: $0.documentID, data: $0.data()) } ?? []
                onChange(requests)
            }
        return listener
        #else
        return nil
        #endif
    }

    // MARK: - Duel Invitations

    /// Send a duel invitation to a friend. Creates a real duel + invitation with 10-min expiry.
    func sendDuelInvitation(toUID: String, toUsername: String, toAvatar: String, mode: GameMode = .duel) async throws -> DuelInvitation {
        guard let uid = currentUID else {
            throw NSError(domain: "PerfectTap", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard uid != toUID else {
            throw NSError(domain: "PerfectTap", code: 3, userInfo: [NSLocalizedDescriptionKey: "Can't invite yourself"])
        }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let myProfile = PlayerProfile.load() ?? PlayerProfile()

        // Create the duel first (with selected mode)
        let (duelId, duelCode) = try await createDuel(hostName: myProfile.username, hostAvatar: myProfile.socialAvatarID, mode: mode)

        let pairId = Friendship.pairId(uid, toUID)
        let stateRef = db.collection("duel_invite_state").document(pairId)
        let inviteRef = db.collection("duel_invitations").document()

        let now = Date()
        let expiresAt = now.addingTimeInterval(600) // 10 minutes

        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            // Check guard state for existing pending invite
            if let stateSnap = try? transaction.getDocument(stateRef),
               stateSnap.exists,
               let stateData = stateSnap.data(),
               stateData["status"] as? String == "pending" {
                // Check if the existing invite has expired
                if let existingExpiry = (stateData["expires_at"] as? Timestamp)?.dateValue(),
                   Date() < existingExpiry {
                    errorPointer?.pointee = NSError(domain: "PerfectTap", code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "A pending duel invite already exists"])
                    return nil
                }
            }

            let inviteData: [String: Any] = [
                "from_uid": uid,
                "to_uid": toUID,
                "from_username": myProfile.username,
                "from_avatar": myProfile.socialAvatarID,
                "to_username": toUsername,
                "to_avatar": toAvatar,
                "duel_id": duelId,
                "duel_code": duelCode,
                "mode": mode.rawValue,
                "status": "pending",
                "created_at": FieldValue.serverTimestamp(),
                "expires_at": Timestamp(date: expiresAt)
            ]
            transaction.setData(inviteData, forDocument: inviteRef)

            let stateData: [String: Any] = [
                "user_ids": [uid, toUID],
                "pending_invitation_id": inviteRef.documentID,
                "status": "pending",
                "expires_at": Timestamp(date: expiresAt)
            ]
            transaction.setData(stateData, forDocument: stateRef)

            return nil
        }

        var invite = DuelInvitation()
        invite.id = inviteRef.documentID
        invite.fromUID = uid
        invite.toUID = toUID
        invite.fromUsername = myProfile.username
        invite.fromAvatar = myProfile.socialAvatarID
        invite.toUsername = toUsername
        invite.toAvatar = toAvatar
        invite.duelId = duelId
        invite.duelCode = duelCode
        invite.mode = mode
        invite.status = .pending
        invite.createdAt = now
        invite.expiresAt = expiresAt
        return invite
        #else
        return DuelInvitation()
        #endif
    }

    /// Load incoming duel invitations
    func loadIncomingDuelInvitations() async -> [DuelInvitation] {
        guard let uid = currentUID else { return [] }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("duel_invitations")
            .whereField("to_uid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "created_at", descending: true)
            .getDocuments()
        else { return [] }
        return snap.documents.compactMap { DuelInvitation(id: $0.documentID, data: $0.data()) }
        #else
        return []
        #endif
    }

    /// Load outgoing duel invitations (active + historical statuses)
    func loadOutgoingDuelInvitations() async -> [DuelInvitation] {
        guard let uid = currentUID else { return [] }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("duel_invitations")
            .whereField("from_uid", isEqualTo: uid)
            .whereField("status", in: ["pending", "accepted", "in_progress", "rejected", "cancelled", "expired"])
            .order(by: "created_at", descending: true)
            .getDocuments()
        else { return [] }
        return snap.documents.compactMap { DuelInvitation(id: $0.documentID, data: $0.data()) }
        #else
        return []
        #endif
    }

    /// Accept a duel invitation (invitee only)
    func acceptDuelInvitation(_ invitation: DuelInvitation) async throws {
        guard let uid = currentUID, uid == invitation.toUID else { return }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        // Check expiry
        if invitation.isExpired {
            try? await db.collection("duel_invitations").document(invitation.id).updateData(["status": "expired"])
            throw NSError(domain: "PerfectTap", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invitation has expired"])
        }

        // Join the duel FIRST — only mark accepted if join succeeds.
        // This ensures "accepted" means the guest actually joined.
        let myProfile = PlayerProfile.load() ?? PlayerProfile()
        _ = try await joinDuel(code: invitation.duelCode, guestName: myProfile.username, guestAvatar: myProfile.socialAvatarID)

        try await db.collection("duel_invitations").document(invitation.id).updateData([
            "status": "accepted"
        ])

        // Clear guard state
        let pairId = Friendship.pairId(invitation.fromUID, invitation.toUID)
        try? await db.collection("duel_invite_state").document(pairId).delete()
        #endif
    }

    /// Mark a duel invitation as in_progress (called when host actually enters the game).
    /// This marks the invite as handled/started so UI can classify it into history or waiting states.
    func markDuelInvitationInProgress(_ invitationId: String) async -> Bool {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        do {
            try await db.collection("duel_invitations").document(invitationId).updateData([
                "status": "in_progress"
            ])
            return true
        } catch {
            #if DEBUG
            print("[FirebaseService] markDuelInvitationInProgress failed for \(invitationId): \(error.localizedDescription)")
            #endif
            return false
        }
        #else
        return false
        #endif
    }

    /// Reject a duel invitation (invitee only)
    func rejectDuelInvitation(_ invitation: DuelInvitation) async throws {
        guard let uid = currentUID, uid == invitation.toUID else { return }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        try await db.collection("duel_invitations").document(invitation.id).updateData([
            "status": "rejected"
        ])
        let pairId = Friendship.pairId(invitation.fromUID, invitation.toUID)
        try? await db.collection("duel_invite_state").document(pairId).delete()
        #endif
    }

    /// Cancel a duel invitation (inviter only)
    func cancelDuelInvitation(_ invitation: DuelInvitation) async throws {
        guard let uid = currentUID, uid == invitation.fromUID else { return }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        try await db.collection("duel_invitations").document(invitation.id).updateData([
            "status": "cancelled"
        ])
        let pairId = Friendship.pairId(invitation.fromUID, invitation.toUID)
        try? await db.collection("duel_invite_state").document(pairId).delete()
        #endif
    }

    /// Listen for incoming duel invitations (scoped to view)
    func listenIncomingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let listener = db.collection("duel_invitations")
            .whereField("to_uid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .order(by: "created_at", descending: true)
            .addSnapshotListener { snap, _ in
                let invites = snap?.documents.compactMap { DuelInvitation(id: $0.documentID, data: $0.data()) } ?? []
                onChange(invites)
            }
        return listener
        #else
        return nil
        #endif
    }

    /// Listen for outgoing duel invitations (active + historical statuses)
    func listenOutgoingDuelInvitations(onChange: @escaping ([DuelInvitation]) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let listener = db.collection("duel_invitations")
            .whereField("from_uid", isEqualTo: uid)
            .whereField("status", in: ["pending", "accepted", "in_progress", "rejected", "cancelled", "expired"])
            .order(by: "created_at", descending: true)
            .addSnapshotListener { snap, _ in
                let invites = snap?.documents.compactMap { DuelInvitation(id: $0.documentID, data: $0.data()) } ?? []
                onChange(invites)
            }
        return listener
        #else
        return nil
        #endif
    }

    /// Listen for outgoing duel invitations to a specific friend (latest active/history state)
    func listenOutgoingDuelInvitation(toUID: String, onChange: @escaping (DuelInvitation?) -> Void) -> Any? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let listener = db.collection("duel_invitations")
            .whereField("from_uid", isEqualTo: uid)
            .whereField("to_uid", isEqualTo: toUID)
            .whereField("status", in: ["pending", "accepted", "in_progress", "rejected", "cancelled", "expired"])
            .order(by: "created_at", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snap, _ in
                let invite = snap?.documents.first.flatMap { DuelInvitation(id: $0.documentID, data: $0.data()) }
                onChange(invite)
            }
        return listener
        #else
        return nil
        #endif
    }

    /// Load a single duel invitation by ID (for refresh after actions)
    func loadDuelInvitation(id: String) async -> DuelInvitation? {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        guard let snap = try? await db.collection("duel_invitations").document(id).getDocument(),
              let data = snap.data() else { return nil }
        return DuelInvitation(id: snap.documentID, data: data)
        #else
        return nil
        #endif
    }

    /// Check if there's a pending duel invite between two users
    func hasPendingDuelInvite(withUID otherUID: String) async -> DuelInvitation? {
        guard let uid = currentUID else { return nil }
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let pairId = Friendship.pairId(uid, otherUID)
        guard let stateSnap = try? await db.collection("duel_invite_state").document(pairId).getDocument(),
              stateSnap.exists,
              let stateData = stateSnap.data(),
              stateData["status"] as? String == "pending",
              let inviteId = stateData["pending_invitation_id"] as? String
        else { return nil }
        return await loadDuelInvitation(id: inviteId)
        #else
        return nil
        #endif
    }

    // MARK: - Pending Counts (for Home badge)

    /// Shared classification for outgoing duel invites, using the same presentation logic
    /// as Friends/FriendDetail (DuelInvitation.presentationState + handled receipts).
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
            let state = invite.presentationState(
                currentUID: uid,
                duel: duelsById[invite.duelId],
                isHandled: DuelInviteLaunchReceiptStore.isHandled(inviteId: invite.id, duelId: invite.duelId)
            )
            states[invite.id] = state
        }
        return states
    }

    /// Returns actionable counts for Home/Friends badges using unified duel actionability rules.
    func loadActionablePendingCounts(
        incomingFriendRequests: [FriendRequest],
        incomingDuelInvitations: [DuelInvitation],
        outgoingDuelInvitations: [DuelInvitation]
    ) async -> (friendRequests: Int, duelInvitations: Int) {
        let friendRequestsCount = incomingFriendRequests.count

        let incomingActionableCount = incomingDuelInvitations.filter { invite in
            invite.presentationState(currentUID: nil, duel: nil, isHandled: false) != .history
        }.count

        let outgoingStates = await loadOutgoingDuelInvitePresentationStates(
            outgoingInvitations: outgoingDuelInvitations
        )
        let outgoingReadyToPlayCount = outgoingStates.values.filter { $0 == .readyToPlay }.count

        return (friendRequestsCount, incomingActionableCount + outgoingReadyToPlayCount)
    }

    /// Returns (incomingFriendRequests, actionableDuelInvitations) counts.
    /// Kept for compatibility; now uses unified actionability rules.
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

    /// Remove a Firestore listener
    func removeListener(_ listener: Any?) {
        #if canImport(FirebaseFirestore)
        (listener as? ListenerRegistration)?.remove()
        #endif
    }

    // MARK: - Codable helpers (manual Firestore ↔ PlayerProfile mapping)
    private func decode(_ data: [String: Any]) -> PlayerProfile? {
        var p = PlayerProfile()
        p.uid              = data["uid"] as? String ?? ""
        p.username         = data["username"] as? String ?? ""
        p.avatar           = data["avatar"] as? String ?? "default"
        p.coins            = data["coins"] as? Int ?? 0
        p.level            = data["level"] as? Int ?? 1
        p.xp               = data["xp"] as? Int ?? 0
        p.bestClassic      = data["best_classic"] as? Int ?? 0
        p.bestEndless      = data["best_endless"] as? Int ?? 0
        p.bestTimed        = data["best_timed"] as? Int ?? 0
        p.bestSudden       = data["best_sudden"] as? Int ?? 0
        p.bestComboFrenzy  = data["best_combofrenzy"] as? Int ?? 0
        p.friendCode       = data["friend_code"] as? String ?? ""
        p.friends          = data["friends"] as? [String] ?? []
        p.ownedItems       = data["owned_items"] as? [String] ?? []
        p.equippedTheme    = data["equipped_theme"] as? String ?? "default"
        p.equippedAvatar   = data["equipped_avatar"] as? String ?? "default"
        p.equippedTapFX    = data["equipped_tapfx"] as? String ?? "fx_default"
        p.equippedTrail    = data["equipped_trail"] as? String ?? "trail_none"
        p.equippedBadge    = data["equipped_badge"] as? String ?? ""
        p.dailyRewardStreak    = data["daily_reward_streak"] as? Int ?? 0
        p.dailyRewardLastClaim = data["daily_reward_last_claim"] as? String ?? ""
        p.activeChallenge  = data["active_challenge"] as? String ?? ""
        p.seasonXP         = data["season_xp"] as? Int ?? 0
        p.seasonTier       = data["season_tier"] as? Int ?? 0
        p.seasonPremium    = data["season_premium"] as? Bool ?? false
        p.seasonAdProgress = data["season_ad_progress"] as? Int ?? 0
        p.seasonClaimedTiers = data["season_claimed_tiers"] as? [Int] ?? []
        p.questsJSON       = data["quests_json"] as? String ?? "{}"
        p.achievements     = data["achievements"] as? [String] ?? []
        p.completedChallenges = data["completed_challenges"] as? [String] ?? []
        p.noAds            = data["no_ads"] as? Bool ?? false
        p.revivesUsedToday = data["revives_used_today"] as? Int ?? 0
        p.lastReviveDate   = data["last_revive_date"] as? String ?? ""
        if let extra = data["best_scores_extra"] as? [String: Any] {
            p.bestScoresExtra = extra.reduce(into: [:]) { partialResult, entry in
                if let value = intValue(entry.value) {
                    partialResult[entry.key] = value
                }
            }
        }
        for mode in GameMode.selectableModes {
            let key = mode.bestScoreKey
            guard !key.isEmpty else { continue }
            if let value = intValue(data[key]) {
                p.bestScoresExtra[key] = max(p.bestScoresExtra[key] ?? 0, value)
            }
        }
        if let boostData = data["boost"] as? [String: Any],
           let value = doubleValue(boostData["value"]) {
            p.boost = ScoreBoost(
                value: value,
                used: boostData["used"] as? Bool ?? false,
                games: intValue(boostData["games"]) ?? 0
            )
        }
        if let history = data["score_history"] as? [[String: Any]] {
            p.scoreHistory = history.compactMap { row in
                guard let score = intValue(row["score"]), let date = row["date"] as? String else { return nil }
                let id = (row["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
                return ScoreEntry(id: id, score: score, date: date)
            }
        }
        if let statsData = data["stats"] as? [String: Any] {
            p.stats.totalGames        = statsData["totalGames"] as? Int ?? 0
            p.stats.duelWins          = statsData["duelWins"] as? Int ?? 0
            p.stats.duelLosses        = statsData["duelLosses"] as? Int ?? 0
            p.stats.duelTies          = statsData["duelTies"] as? Int ?? 0
            p.stats.totalCoinsEarned  = statsData["totalCoinsEarned"] as? Int ?? 0
            p.stats.perfectTaps       = statsData["perfectTaps"] as? Int ?? 0
            p.stats.highestCombo      = statsData["highestCombo"] as? Int ?? 0
        }
        p.normalizeAndMigrate()
        return p
    }

    private func encode(_ profile: PlayerProfile) -> [String: Any] {
        var p = profile
        p.normalizeAndMigrate()
        var data: [String: Any] = [
            "uid": p.uid,
            "username": p.username,
            "username_lower": p.username.lowercased(),
            "avatar": p.socialAvatarID,
            "coins": p.coins,
            "level": p.level,
            "xp": p.xp,
            "best_classic": p.bestClassic,
            "best_endless": p.bestEndless,
            "best_timed": p.bestTimed,
            "best_sudden": p.bestSudden,
            "best_combofrenzy": p.bestComboFrenzy,
            "friend_code": p.friendCode,
            "friends": p.friends,
            "owned_items": p.ownedItems,
            "equipped_theme": p.equippedTheme,
            "equipped_avatar": p.equippedAvatar,
            "equipped_tapfx": p.equippedTapFX,
            "equipped_trail": p.equippedTrail,
            "equipped_badge": p.equippedBadge,
            "daily_reward_streak": p.dailyRewardStreak,
            "daily_reward_last_claim": p.dailyRewardLastClaim,
            "active_challenge": p.activeChallenge,
            "season_xp": p.seasonXP,
            "season_tier": p.seasonTier,
            "season_premium": p.seasonPremium,
            "season_ad_progress": p.seasonAdProgress,
            "season_claimed_tiers": p.seasonClaimedTiers,
            "quests_json": p.questsJSON,
            "achievements": p.achievements,
            "completed_challenges": p.completedChallenges,
            "no_ads": p.noAds,
            "revives_used_today": p.revivesUsedToday,
            "last_revive_date": p.lastReviveDate,
            "best_scores_extra": p.bestScoresExtra,
            "score_history": p.scoreHistory.map { ["id": $0.id, "score": $0.score, "date": $0.date] },
            "stats": [
                "totalGames": p.stats.totalGames,
                "duelWins": p.stats.duelWins,
                "duelLosses": p.stats.duelLosses,
                "duelTies": p.stats.duelTies,
                "totalCoinsEarned": p.stats.totalCoinsEarned,
                "perfectTaps": p.stats.perfectTaps,
                "highestCombo": p.stats.highestCombo,
            ]
        ]
        if let boost = p.boost {
            data["boost"] = [
                "value": boost.value,
                "used": boost.used,
                "games": boost.games
            ]
        } else {
            data["boost"] = NSNull()
        }
        for (key, value) in p.bestScoresExtra {
            data[key] = value
        }
        return data
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }
}
