import Foundation
import Combine

// MARK: - Auth state machine
enum AuthState {
    case loading
    case needsUsername     // first launch — no username chosen yet
    case authenticated     // fully set up with permanent username
}

// MARK: - AuthViewModel
// Uses Firebase Anonymous Auth so every user gets a valid auth token at startup.
// No login wall. Username is chosen once and is permanent.
// Optional email linking (Cloud Backup) upgrades the anonymous account.
@MainActor
final class AuthViewModel: ObservableObject {

    static let shared = AuthViewModel()

    @Published var authState: AuthState = .loading
    @Published var currentUID: String? = nil
    @Published var errorMessage: String? = nil

    /// Set to `true` when Delete Account needs the user to re-enter their password
    /// (Firebase requires recent authentication for linked email users).
    @Published var needsReauthForDelete: Bool = false

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
        FirebaseService.shared.isLinkedToEmail
    }

    private init() {
        bootstrapIdentity()
    }

    // MARK: - Identity bootstrap (Anonymous Auth)
    /// On launch: signs in anonymously with Firebase Auth to get a valid token.
    /// Then loads or creates the local profile using the Firebase UID.
    /// Never shows a login wall — goes straight to username selection or home.
    private func bootstrapIdentity() {
        // Start async bootstrap
        Task {
            // Sign in anonymously (or reuse existing session)
            let firebaseUID = await FirebaseService.shared.signInAnonymously()

            if let profile = PlayerProfile.load(), !profile.uid.isEmpty {
                // Existing profile found
                if let fbUID = firebaseUID, fbUID != profile.uid {
                    // Firebase UID changed (e.g. after reinstall) — migrate profile
                    var updated = profile
                    updated.uid = fbUID
                    updated.save()
                    currentUID = fbUID
                    await FirebaseService.shared.saveProfile(updated)
                } else {
                    currentUID = firebaseUID ?? profile.uid
                }
                authState = profile.username.isEmpty ? .needsUsername : .authenticated
            } else if firebaseUID != nil,
                      let cloudProfile = await FirebaseService.shared.loadProfile(),
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
        let isUnique = await FirebaseService.shared.isUsernameAvailable(trimmed)
        guard isUnique else {
            errorMessage = "That username is already taken. Try another."
            return
        }

        var profile = PlayerProfile.load() ?? PlayerProfile()
        profile.uid = uid
        profile.username = trimmed
        if profile.friendCode.isEmpty { profile.friendCode = generateFriendCode() }
        profile.save()
        await FirebaseService.shared.saveProfile(profile)
        authState = .authenticated
    }

    // MARK: - Temporary nickname (for friend/local play sessions)
    func setTempNickname(_ nickname: String?) {
        tempNickname = nickname
    }

    func clearTempNickname() {
        tempNickname = nil
    }

    // MARK: - Cloud Backup: Link anonymous account to email/password
    /// Upgrades the current anonymous account to a permanent email account.
    /// The UID stays the same — no data migration needed.
    func linkAccount(email: String, password: String) async {
        errorMessage = nil
        do {
            let uid = try await FirebaseService.shared.linkAnonymousAccount(email: email, password: password)
            // UID should be the same, but update just in case
            var profile = PlayerProfile.load() ?? PlayerProfile()
            profile.uid = uid
            profile.save()
            currentUID = uid
            await FirebaseService.shared.saveProfile(profile)
        } catch {
            let nsError = error as NSError
            // Firebase error 17025 = "credential already in use" (account exists)
            if nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17025 {
                errorMessage = "This email is already linked to another account. Use Sign In instead."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Signs in with an existing email account and migrates local data.
    /// The current anonymous account is replaced by the email account.
    func signInAndLink(email: String, password: String) async {
        errorMessage = nil
        do {
            let firebaseUID = try await FirebaseService.shared.signInWithEmail(email: email, password: password)
            let localProfile = PlayerProfile.load() ?? PlayerProfile()

            // Load cloud profile and apply explicit field-by-field deterministic merge.
            if let cloudProfile = await FirebaseService.shared.loadProfile() {
                let merged = mergeProfiles(local: localProfile, cloud: cloudProfile, firebaseUID: firebaseUID)
                merged.save()
                currentUID = firebaseUID
                await FirebaseService.shared.saveProfile(merged)
            } else {
                // No cloud profile — just update UID
                var local = localProfile
                local.uid = firebaseUID
                local.save()
                currentUID = firebaseUID
                await FirebaseService.shared.saveProfile(local)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign out (goes back to anonymous — keeps local data)
    func signOut() {
        FirebaseService.shared.signOut()
        // Sign back in anonymously so Firestore writes still work
        Task {
            let anonUID = await FirebaseService.shared.signInAnonymously()
            let uid = anonUID ?? getOrCreateDeviceUID()
            currentUID = uid
            var profile = PlayerProfile.load() ?? PlayerProfile()
            profile.uid = uid
            profile.save()
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
        let result = await FirebaseService.shared.deleteCurrentAccount()

        if result == .requiresReauth {
            // Firestore doc is already deleted, but Auth user needs re-auth.
            if FirebaseService.shared.isLinkedToEmail {
                // Email-linked user — prompt for password via UI alert
                needsReauthForDelete = true
                return
            } else {
                // Anonymous user — can't re-auth with password, just sign out.
                // The orphaned anonymous Auth user will expire on its own.
                FirebaseService.shared.signOut()
            }
        }

        // Auth user deleted (or no user / anonymous fallback) — proceed with full cleanup
        finishDeleteCleanup()
    }

    /// Called after the user provides their password for re-authentication.
    /// Completes the Auth user deletion that was blocked by Firebase's
    /// recent-login requirement.
    func deleteAccountAfterReauth(password: String) async {
        guard let email = FirebaseService.shared.currentUserEmail else {
            // No email found — force sign out and clean up
            FirebaseService.shared.signOut()
            finishDeleteCleanup()
            return
        }

        let success = await FirebaseService.shared.reauthenticateAndDelete(email: email, password: password)
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
        UserDefaults.standard.removeObject(forKey: "perfecttap_player_profile")
        UserDefaults.standard.removeObject(forKey: "perfecttap_device_uid")
        UserDefaults.standard.removeObject(forKey: "perfecttap_sound")
        UserDefaults.standard.removeObject(forKey: "perfecttap_music")
        UserDefaults.standard.removeObject(forKey: "perfecttap_haptics")
        DuelContext.clear()
        DuelInviteLaunchReceiptStore.clear()

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

    private func mergeProfiles(local: PlayerProfile, cloud: PlayerProfile, firebaseUID: String) -> PlayerProfile {
        var merged = local
        merged.uid = firebaseUID

        // 1) Identity fields
        merged.username = cloud.username.isEmpty ? local.username : cloud.username
        merged.friendCode = cloud.friendCode.isEmpty ? local.friendCode : cloud.friendCode

        // 2) Core progression/economy
        merged.coins = max(local.coins, cloud.coins)
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
        merged.ownedItems = unionPreservingOrder(local.ownedItems, cloud.ownedItems)
        merged.friends = unionPreservingOrder(local.friends, cloud.friends)
        merged.achievements = unionPreservingOrder(local.achievements, cloud.achievements)
        merged.completedChallenges = unionPreservingOrder(local.completedChallenges, cloud.completedChallenges)
        merged.seasonClaimedTiers = unionPreservingOrder(local.seasonClaimedTiers, cloud.seasonClaimedTiers)

        // 6) Season fields
        merged.seasonXP = max(local.seasonXP, cloud.seasonXP)
        merged.seasonTier = max(local.seasonTier, cloud.seasonTier)
        merged.seasonAdProgress = max(local.seasonAdProgress, cloud.seasonAdProgress)
        merged.seasonPremium = local.seasonPremium || cloud.seasonPremium
        merged.noAds = local.noAds || cloud.noAds

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
