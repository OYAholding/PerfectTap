import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - Auth state machine
enum AuthState {
    case loading
    case needsUsername     // first launch — no username chosen yet
    case authenticated     // fully set up with permanent username
}

// MARK: - AuthViewModel
// Uses anonymous auth (Firebase or Supabase via Backend.shared) so every user gets a valid token at startup.
// No login wall. Username is chosen once and is permanent.
// Optional email linking (Cloud Backup) upgrades the anonymous account.
@MainActor
final class AuthViewModel: ObservableObject {

    static let shared = AuthViewModel()

    @Published var authState: AuthState = .loading
    @Published var currentUID: String? = nil
    @Published var errorMessage: String? = nil
    @Published private(set) var isLinkingApple = false

    /// Set to `true` when Delete Account needs the user to re-enter their password
    /// (Firebase requires recent authentication for linked email users).
    @Published var needsReauthForDelete: Bool = false

    /// Set when Cloud Backup emailed a verification code (Supabase); the UI then
    /// asks for the code and calls `confirmEmailLink(code:password:)`.
    @Published var pendingVerificationEmail: String? = nil

    /// Temporary nickname for friend/local play sessions (not persisted across app restarts)
    @Published var tempNickname: String? = nil

    /// The display name to show in multiplayer contexts.
    /// Returns tempNickname if set, otherwise the permanent username.
    var displayName: String {
        if let nick = tempNickname, !nick.isEmpty { return nick }
        return PlayerProfile.load()?.username ?? "Player"
    }

    /// Whether the current user has linked an email account
    var isLinkedToEmail: Bool {
        Backend.shared.isLinkedToEmail
    }

    var isPermanentAccount: Bool { Backend.shared.isPermanentAccount }

    /// Re-applies Apple-owned non-consumables (Remove Forced Ads, premium
    /// skins) after a profile merge replaced `noAds`/items with the cloud
    /// copy. Seam for tests.
    var reconcileOwnedEntitlements: () async -> Void = {
        await PurchaseManager.shared.reconcileOwnedEntitlements()
    }

    private init() {
        bootstrapIdentity()
    }

    /// Adopts a profile produced by a sign-in / identity merge: local save,
    /// cloud save, then StoreKit reconciliation so the merge never wipes an
    /// entitlement the Apple ID owns, then the economy account switch.
    func adoptMergedProfile(_ profile: PlayerProfile, uid: String) async {
        profile.save()
        currentUID = uid
        await Backend.shared.saveProfile(profile)
        await reconcileOwnedEntitlements()
        EconomyManager.shared.service.accountDidChange()
    }

    // MARK: - Identity bootstrap (Anonymous Auth)
    /// On launch: signs in anonymously with Firebase Auth to get a valid token.
    /// Then loads or creates the local profile using the Firebase UID.
    /// Never shows a login wall — goes straight to username selection or home.
    private func bootstrapIdentity() {
        // Start async bootstrap
        Task {
            // Sign in anonymously (or reuse existing session)
            let firebaseUID = await Backend.shared.signInAnonymously()

            if let profile = PlayerProfile.load(), !profile.uid.isEmpty {
                // Existing profile found
                if let fbUID = firebaseUID, fbUID != profile.uid {
                    // Firebase UID changed (e.g. after reinstall) — migrate profile
                    var updated = profile
                    updated.uid = fbUID
                    updated.save()
                    currentUID = fbUID
                    await Backend.shared.saveProfile(updated)
                } else {
                    currentUID = firebaseUID ?? profile.uid
                }
                authState = profile.username.isEmpty ? .needsUsername : .authenticated
                EconomyManager.shared.service.accountDidChange()
            } else if firebaseUID != nil,
                      let cloudProfile = await Backend.shared.loadProfile(),
                      !cloudProfile.username.isEmpty {
                // No local profile, but Firebase restored a session (Keychain
                // survives reinstall) and the cloud has this player's progress.
                // Restore it instead of creating a blank profile — previously the
                // blank profile was saved with merge:true and wiped cloud coins,
                // levels, purchases and best scores.
                var restored = cloudProfile
                restored.uid = firebaseUID ?? cloudProfile.uid
                if restored.friendCode.isEmpty { restored.friendCode = generateFriendCode() }
                restored.save()
                currentUID = restored.uid
                authState = .authenticated
                // The cloud copy replaced local entitlements: re-apply StoreKit.
                await reconcileOwnedEntitlements()
            } else {
                // First launch — create guest profile with Firebase UID
                let uid = firebaseUID ?? getOrCreateDeviceUID()
                currentUID = uid
                var profile = PlayerProfile()
                profile.uid = uid
                profile.friendCode = generateFriendCode()
                profile.save()
                authState = .needsUsername
            }
        }
    }

    // MARK: - Set permanent username (one-time, during onboarding)
    func setUsername(_ username: String) async {
        guard let uid = currentUID else { return }
        errorMessage = nil

        // Validate format
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.count <= 20,
              trimmed.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil else {
            errorMessage = "Username must be 2–20 characters: letters, numbers, underscore only."
            return
        }

        // Check uniqueness via Firebase (if available)
        let isUnique = await Backend.shared.isUsernameAvailable(trimmed)
        guard isUnique else {
            errorMessage = "That username is already taken. Try another."
            return
        }

        var profile = PlayerProfile.load() ?? PlayerProfile()
        profile.uid = uid
        profile.username = trimmed
        if profile.friendCode.isEmpty { profile.friendCode = generateFriendCode() }
        profile.save()
        await Backend.shared.saveProfile(profile)
        authState = .authenticated
    }

    // MARK: - Temporary nickname (for friend/local play sessions)
    func setTempNickname(_ nickname: String?) {
        tempNickname = nickname
    }

    func clearTempNickname() {
        tempNickname = nil
    }

    // MARK: - Optional one-tap account protection

    /// Links the current anonymous Supabase/Firebase user to Apple without
    /// changing its UID. When the Apple identity already exists, signs into it
    /// and deterministically merges this device's local profile with the cloud.
    @discardableResult
    func linkWithApple() async -> Bool {
        guard !isLinkingApple else { return false }
        isLinkingApple = true
        errorMessage = nil
        defer { isLinkingApple = false }

        let rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(rawNonce)

        do {
            let authorization = try await AppleAuthorizationCoordinator.authorize(request)
            return await finishAppleAuthorization(authorization, rawNonce: rawNonce)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Entry point for SwiftUI's official SignInWithAppleButton.
    @discardableResult
    func linkWithApple(authorization: ASAuthorization, rawNonce: String) async -> Bool {
        guard !isLinkingApple else { return false }
        isLinkingApple = true
        errorMessage = nil
        defer { isLinkingApple = false }
        return await finishAppleAuthorization(authorization, rawNonce: rawNonce)
    }

    private func finishAppleAuthorization(_ authorization: ASAuthorization, rawNonce: String) async -> Bool {
        do {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                throw BackendError.server("Apple did not return a valid identity token. Please try again.")
            }
            let local = PlayerProfile.load() ?? PlayerProfile()
            let result = try await Backend.shared.linkOrSignInWithApple(
                idToken: idToken, nonce: rawNonce, fullName: credential.fullName)
            let profile: PlayerProfile
            if result.keptAnonymousUID {
                var linked = local
                linked.uid = result.uid
                profile = linked
            } else if let cloud = await Backend.shared.loadProfile() {
                profile = mergeProfiles(local: local, cloud: cloud, firebaseUID: result.uid)
            } else {
                var migrated = local
                migrated.uid = result.uid
                profile = migrated
            }
            await adoptMergedProfile(profile, uid: result.uid)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Cloud Backup: Link anonymous account to email/password
    /// Upgrades the current anonymous account to a permanent email account.
    /// The UID stays the same — no data migration needed.
    func linkAccount(email: String, password: String) async {
        errorMessage = nil
        pendingVerificationEmail = nil
        do {
            let uid = try await Backend.shared.linkAnonymousAccount(email: email, password: password)
            // UID should be the same, but update just in case
            var profile = PlayerProfile.load() ?? PlayerProfile()
            profile.uid = uid
            profile.save()
            currentUID = uid
            await Backend.shared.saveProfile(profile)
        } catch BackendError.verificationCodeSent(let sentTo) {
            pendingVerificationEmail = sentTo
        } catch {
            let nsError = error as NSError
            // Firebase error 17025 = "credential already in use" (account exists)
            if (error as? BackendError) == .emailInUse
                || (nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17025) {
                errorMessage = "This email is already linked to another account. Use Sign In instead."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Second step of Cloud Backup on Supabase: proves email ownership.
    func confirmEmailLink(code: String, password: String) async {
        guard let email = pendingVerificationEmail else { return }
        errorMessage = nil
        do {
            let uid = try await Backend.shared.confirmEmailLink(email: email, code: code, password: password)
            pendingVerificationEmail = nil
            var profile = PlayerProfile.load() ?? PlayerProfile()
            profile.uid = uid
            profile.save()
            currentUID = uid
            await Backend.shared.saveProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Signs in with an existing email account and migrates local data.
    /// The current anonymous account is replaced by the email account.
    func signInAndLink(email: String, password: String) async {
        errorMessage = nil
        do {
            let firebaseUID = try await Backend.shared.signInWithEmail(email: email, password: password)
            let localProfile = PlayerProfile.load() ?? PlayerProfile()

            // Load cloud profile and apply explicit field-by-field deterministic merge.
            if let cloudProfile = await Backend.shared.loadProfile() {
                let merged = mergeProfiles(local: localProfile, cloud: cloudProfile, firebaseUID: firebaseUID)
                await adoptMergedProfile(merged, uid: firebaseUID)
            } else {
                // No cloud profile — just update UID
                var local = localProfile
                local.uid = firebaseUID
                local.save()
                currentUID = firebaseUID
                await Backend.shared.saveProfile(local)
                EconomyManager.shared.service.accountDidChange()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign out (goes back to anonymous — keeps local data)
    func signOut() {
        // Sign back in anonymously so cloud writes still work (after sign-out completes).
        Task {
            await Backend.shared.signOut()
            let anonUID = await Backend.shared.signInAnonymously()
            let uid = anonUID ?? getOrCreateDeviceUID()
            currentUID = uid
            var profile = PlayerProfile.load() ?? PlayerProfile()
            profile.uid = uid
            profile.save()
            EconomyManager.shared.service.accountDidChange()
            // Stay authenticated — user still has their username
        }
    }

    // MARK: - Delete Account (Apple-compliant full account deletion)
    /// Deletes the current user's Firestore data, releases their username,
    /// deletes the Firebase Auth account, clears local data, and returns to
    /// a fresh anonymous guest state.
    ///
    /// For linked email users, Firebase may require re-authentication.
    /// If so, sets `needsReauthForDelete = true` — the UI should then
    /// prompt for the password and call `deleteAccountAfterReauth(password:)`.
    func deleteAccount() async {
        // 1. Delete Firestore player document + Firebase Auth account.
        //    Must happen BEFORE clearing local state, while we still have
        //    the Auth token needed for Firestore writes.
        let result = await Backend.shared.deleteCurrentAccount()

        if result == .requiresReauth {
            // Firestore doc is already deleted, but Auth user needs re-auth.
            if Backend.shared.isLinkedToEmail {
                // Email-linked user — prompt for password via UI alert
                needsReauthForDelete = true
                return
            } else {
                // Anonymous user — can't re-auth with password, just sign out.
                // The orphaned anonymous Auth user will expire on its own.
                await Backend.shared.signOut()
            }
        }

        // Auth user deleted (or no user / anonymous fallback) — proceed with full cleanup
        finishDeleteCleanup()
    }

    /// Called after the user provides their password for re-authentication.
    /// Completes the Auth user deletion that was blocked by Firebase's
    /// recent-login requirement.
    func deleteAccountAfterReauth(password: String) async {
        guard let email = Backend.shared.currentUserEmail else {
            // No email found — force sign out and clean up
            await Backend.shared.signOut()
            finishDeleteCleanup()
            return
        }

        let success = await Backend.shared.reauthenticateAndDelete(email: email, password: password)
        if !success {
            errorMessage = "Incorrect password. Your data has been deleted but the login may remain. Contact support if needed."
        }
        needsReauthForDelete = false
        finishDeleteCleanup()
    }

    /// Clears all local data and bootstraps a fresh anonymous identity.
    /// Called after Auth + Firestore deletion is complete (or after best-effort fallback).
    func finishDeleteCleanup() {
        // Clear ALL local user data
        PlayerProfile.clearSaved()
        SessionMetricsStore.shared.clearAll()
        UserDefaults.standard.removeObject(forKey: EffectsLevel.storageKey)
        UserDefaults.standard.removeObject(forKey: "perfecttap_device_uid")
        UserDefaults.standard.removeObject(forKey: "perfecttap_sound")
        UserDefaults.standard.removeObject(forKey: "perfecttap_music")
        UserDefaults.standard.removeObject(forKey: "perfecttap_haptics")
        DuelContext.clear()
        DuelInviteLaunchReceiptStore.clear()
        PendingDuelStore.clear()
        // A fresh account must not inherit today's wheel/quest claims.
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("perfecttap_quests_") || key.hasPrefix("perfecttap_wheel_") || key == "perfecttap_last_spin" {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Reset in-memory state
        currentUID = nil
        tempNickname = nil
        errorMessage = nil

        // Show loading screen immediately (prevents flash of empty HomeView)
        authState = .loading

        // Bootstrap fresh anonymous identity (only AFTER deletion completes)
        bootstrapIdentity()
    }

    // MARK: - Helpers

    private func getOrCreateDeviceUID() -> String {
        let key = "perfecttap_device_uid"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newUID = UUID().uuidString
        UserDefaults.standard.set(newUID, forKey: key)
        return newUID
    }

    private func generateFriendCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement() ?? "A" })
    }

    nonisolated static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        while result.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            for byte in bytes where byte < alphabet.count * (256 / alphabet.count) {
                result.append(alphabet[Int(byte) % alphabet.count])
                if result.count == length { break }
            }
        }
        return result
    }

    private func mergeProfiles(local: PlayerProfile, cloud: PlayerProfile, firebaseUID: String) -> PlayerProfile {
        var merged = local
        merged.uid = firebaseUID

        // 1) Identity fields
        merged.username = cloud.username.isEmpty ? local.username : cloud.username
        merged.friendCode = cloud.friendCode.isEmpty ? local.friendCode : cloud.friendCode

        // 2) Core progression/economy
        // Once the authoritative ledger is owner-enabled, only the server
        // balance may cross an identity merge. The legacy rollout keeps the
        // historical max merge until reconciliation is approved.
        let authoritative = EconomyManager.shared.service.isAuthoritative
        merged.coins = Self.mergedCoins(local: local.coins, cloud: cloud.coins, authoritative: authoritative)
        if cloud.level > local.level || (cloud.level == local.level && cloud.xp > local.xp) {
            merged.level = cloud.level
            merged.xp = cloud.xp
        } else {
            merged.level = local.level
            merged.xp = local.xp
        }

        // 3) Core best scores
        merged.bestClassic = max(local.bestClassic, cloud.bestClassic)
        merged.bestEndless = max(local.bestEndless, cloud.bestEndless)
        merged.bestTimed = max(local.bestTimed, cloud.bestTimed)
        merged.bestSudden = max(local.bestSudden, cloud.bestSudden)
        merged.bestComboFrenzy = max(local.bestComboFrenzy, cloud.bestComboFrenzy)

        // 4) Extra best scores (union + max by key)
        var mergedExtra: [String: Int] = [:]
        let allExtraKeys = Set(local.bestScoresExtra.keys).union(cloud.bestScoresExtra.keys)
        for key in allExtraKeys {
            mergedExtra[key] = max(local.bestScoresExtra[key] ?? 0, cloud.bestScoresExtra[key] ?? 0)
        }
        merged.bestScoresExtra = mergedExtra

        // 5) Set-like unions
        merged.ownedItems = Self.mergedOwnedItems(local: local.ownedItems, cloud: cloud.ownedItems,
                                                  authoritative: authoritative)
        merged.friends = unionPreservingOrder(local.friends, cloud.friends)
        merged.achievements = unionPreservingOrder(local.achievements, cloud.achievements)
        merged.completedChallenges = unionPreservingOrder(local.completedChallenges, cloud.completedChallenges)
        merged.seasonClaimedTiers = unionPreservingOrder(local.seasonClaimedTiers, cloud.seasonClaimedTiers)

        // 6) Season fields
        merged.seasonXP = max(local.seasonXP, cloud.seasonXP)
        merged.seasonTier = max(local.seasonTier, cloud.seasonTier)
        merged.seasonAdProgress = max(local.seasonAdProgress, cloud.seasonAdProgress)
        merged.seasonPremium = local.seasonPremium || cloud.seasonPremium
        // With server verification the purchase ledger owns Remove Ads (a
        // refund must be able to turn it off); until then keep the OR merge.
        merged.noAds = FeatureFlags.serverPurchaseVerification ? cloud.noAds : (local.noAds || cloud.noAds)

        // 7) Stats
        merged.stats.totalGames = max(local.stats.totalGames, cloud.stats.totalGames)
        merged.stats.duelWins = max(local.stats.duelWins, cloud.stats.duelWins)
        merged.stats.duelLosses = max(local.stats.duelLosses, cloud.stats.duelLosses)
        merged.stats.duelTies = max(local.stats.duelTies, cloud.stats.duelTies)
        merged.stats.totalCoinsEarned = max(local.stats.totalCoinsEarned, cloud.stats.totalCoinsEarned)
        merged.stats.perfectTaps = max(local.stats.perfectTaps, cloud.stats.perfectTaps)
        merged.stats.highestCombo = max(local.stats.highestCombo, cloud.stats.highestCombo)

        // 8) Daily reward tuple
        switch compareDateStrings(cloud.dailyRewardLastClaim, local.dailyRewardLastClaim) {
        case .orderedDescending:
            merged.dailyRewardLastClaim = cloud.dailyRewardLastClaim
            merged.dailyRewardStreak = cloud.dailyRewardStreak
        case .orderedAscending:
            merged.dailyRewardLastClaim = local.dailyRewardLastClaim
            merged.dailyRewardStreak = local.dailyRewardStreak
        case .orderedSame:
            merged.dailyRewardLastClaim = cloud.dailyRewardLastClaim.isEmpty ? local.dailyRewardLastClaim : cloud.dailyRewardLastClaim
            merged.dailyRewardStreak = max(local.dailyRewardStreak, cloud.dailyRewardStreak)
        }

        // 9) Equip fields (prefer cloud if valid, else local, else defaults)
        let owned = Set(merged.ownedItems)
        merged.equippedTheme = pickEquipped(
            cloudValue: cloud.equippedTheme,
            localValue: local.equippedTheme,
            fallback: "default",
            isValid: { isValidTheme($0, owned: owned) }
        )
        merged.equippedAvatar = pickEquipped(
            cloudValue: cloud.equippedAvatar,
            localValue: local.equippedAvatar,
            fallback: "default",
            isValid: { isValidAvatar($0, owned: owned) }
        )
        merged.equippedTapFX = pickEquipped(
            cloudValue: cloud.equippedTapFX,
            localValue: local.equippedTapFX,
            fallback: "fx_default",
            isValid: { isValidTapFX($0, owned: owned) }
        )
        merged.equippedTrail = pickEquipped(
            cloudValue: cloud.equippedTrail,
            localValue: local.equippedTrail,
            fallback: "trail_none",
            isValid: { isValidTrail($0, owned: owned) }
        )
        merged.equippedBadge = pickEquipped(
            cloudValue: cloud.equippedBadge,
            localValue: local.equippedBadge,
            fallback: "",
            isValid: { isValidBadge($0, owned: owned) }
        )

        // 10) Active challenge
        merged.activeChallenge = cloud.activeChallenge.isEmpty ? local.activeChallenge : cloud.activeChallenge

        // 11) Score history
        merged.scoreHistory = mergeScoreHistory(local.scoreHistory, cloud.scoreHistory)

        // 12) Keep cloud if present, else local
        merged.boost = cloud.boost ?? local.boost
        merged.questsJSON = isPresentQuestsJSON(cloud.questsJSON) ? cloud.questsJSON : local.questsJSON
        if !cloud.lastReviveDate.isEmpty || cloud.revivesUsedToday > 0 {
            merged.revivesUsedToday = cloud.revivesUsedToday
            merged.lastReviveDate = cloud.lastReviveDate
        } else {
            merged.revivesUsedToday = local.revivesUsedToday
            merged.lastReviveDate = local.lastReviveDate
        }

        merged.normalizeAndMigrate()
        return merged
    }

    /// Coins across an identity merge. Authoritative economy: only the server
    /// balance crosses (never `max(local, cloud)`, which minted coins).
    nonisolated static func mergedCoins(local: Int, cloud: Int, authoritative: Bool) -> Int {
        authoritative ? cloud : max(local, cloud)
    }

    /// Owned items across an identity merge. Legacy: plain union. Authoritative
    /// economy: the server list plus only local items with StoreKit evidence
    /// (premium skins, re-verified from Apple's signed entitlements). Coin-sold
    /// items owned only locally have no server evidence and are not merged in.
    nonisolated static func mergedOwnedItems(local: [String], cloud: [String], authoritative: Bool) -> [String] {
        let candidates = authoritative
            ? local.filter { ShopItem.item(id: $0)?.isPremium == true }
            : local
        var out: [String] = []
        var seen = Set<String>()
        for value in candidates + cloud where seen.insert(value).inserted {
            out.append(value)
        }
        return out
    }

    private func unionPreservingOrder<T: Hashable>(_ local: [T], _ cloud: [T]) -> [T] {
        var out: [T] = []
        var seen = Set<T>()
        for value in local + cloud where seen.insert(value).inserted {
            out.append(value)
        }
        return out
    }

    private func pickEquipped(
        cloudValue: String,
        localValue: String,
        fallback: String,
        isValid: (String) -> Bool
    ) -> String {
        if isValid(cloudValue) { return cloudValue }
        if isValid(localValue) { return localValue }
        return fallback
    }

    private func isValidTheme(_ value: String, owned: Set<String>) -> Bool {
        guard AppTheme.all.contains(where: { $0.name == value }) else { return false }
        return value == "default" || owned.contains("theme_\(value)")
    }

    private func isValidAvatar(_ value: String, owned: Set<String>) -> Bool {
        if value == "default" || value == "avatar_default" { return true }
        let validIDs = Set(ShopItem.avatars.map { $0.id })
        return validIDs.contains(value) && owned.contains(value)
    }

    private func isValidTapFX(_ value: String, owned: Set<String>) -> Bool {
        if value == "fx_default" { return true }
        let validIDs = Set(ShopItem.tapFX.map { $0.id })
        return validIDs.contains(value) && owned.contains(value)
    }

    private func isValidTrail(_ value: String, owned: Set<String>) -> Bool {
        if value == "trail_none" { return true }
        let validIDs = Set(ShopItem.trails.map { $0.id })
        return validIDs.contains(value) && owned.contains(value)
    }

    private func isValidBadge(_ value: String, owned: Set<String>) -> Bool {
        if value.isEmpty { return true }
        let validIDs = Set(ShopItem.badges.map { $0.id })
        return validIDs.contains(value) && owned.contains(value)
    }

    private func mergeScoreHistory(_ local: [ScoreEntry], _ cloud: [ScoreEntry]) -> [ScoreEntry] {
        var mergedById: [String: ScoreEntry] = [:]
        for entry in local + cloud {
            if let existing = mergedById[entry.id] {
                if compareDateStrings(entry.date, existing.date) == .orderedDescending {
                    mergedById[entry.id] = entry
                }
            } else {
                mergedById[entry.id] = entry
            }
        }
        let sorted = mergedById.values.sorted { compareDateStrings($0.date, $1.date) == .orderedDescending }
        return Array(sorted.prefix(10))
    }

    private func isPresentQuestsJSON(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}"
    }

    private func compareDateStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if lhs.isEmpty && rhs.isEmpty { return .orderedSame }
        if lhs.isEmpty { return .orderedAscending }
        if rhs.isEmpty { return .orderedDescending }

        if let leftDate = parseDate(lhs), let rightDate = parseDate(rhs) {
            if leftDate < rightDate { return .orderedAscending }
            if leftDate > rightDate { return .orderedDescending }
            return .orderedSame
        }

        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private func parseDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: raw)
    }
}

private final class AppleAuthorizationCoordinator: NSObject,
                                                   ASAuthorizationControllerDelegate,
                                                   ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    @MainActor
    static func authorize(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        let coordinator = AppleAuthorizationCoordinator()
        return try await coordinator.perform(request)
    }

    @MainActor
    private func perform(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
