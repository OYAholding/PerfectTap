import Foundation

// MARK: - EconomyManager
// Centralizes all reward granting, currency changes, purchase ownership,
// revive eligibility, and skin ownership/equip state.
// Single source of truth for the game economy.

@MainActor
final class EconomyManager {

    static let shared = EconomyManager()
    private init() {}

    /// Authoritative profile mutation path for economy/progression writes.
    /// Persists locally first, then queues cloud sync.
    @discardableResult
    func updateProfile(syncCloud: Bool = true, _ mutate: (inout PlayerProfile) -> Void) -> PlayerProfile {
        var profile = PlayerProfile.load() ?? PlayerProfile()
        mutate(&profile)
        persistProfile(profile, syncCloud: syncCloud)
        return profile
    }

    func persistProfile(_ profile: PlayerProfile, syncCloud: Bool = true) {
        profile.save()
        guard syncCloud else { return }
        Task { await Backend.shared.saveProfile(profile) }
    }

    func currentProfile() -> PlayerProfile {
        PlayerProfile.load() ?? PlayerProfile()
    }

    // MARK: - Currency

    /// Add coins to player profile (from gameplay, quests, purchases, etc.)
    func addCoins(_ amount: Int, source: CoinSource) {
        guard amount > 0 else { return }
        _ = updateProfile { profile in
            profile.coins += amount
            profile.stats.totalCoinsEarned += amount
        }
    }

    /// Spend coins (for shop purchases). Returns true if successful.
    func spendCoins(_ amount: Int) -> Bool {
        guard amount > 0 else { return false }
        var didSpend = false
        _ = updateProfile { profile in
            guard profile.coins >= amount else { return }
            profile.coins -= amount
            didSpend = true
        }
        return didSpend
    }

    /// Current coin balance
    var coinBalance: Int {
        currentProfile().coins
    }

    // MARK: - Item Ownership

    /// Check if player owns an item
    func ownsItem(_ itemID: String) -> Bool {
        let profile = currentProfile()
        return isOwned(itemID, in: profile)
    }

    private func isOwned(_ itemID: String, in profile: PlayerProfile) -> Bool {
        // Free items are always owned
        if let item = ShopItem.allItems.first(where: { $0.id == itemID }), item.isFree {
            return true
        }
        return profile.ownedItems.contains(itemID)
    }

    /// Grant an item to the player (from purchase, achievement, challenge reward)
    func grantItem(_ itemID: String) {
        _ = updateProfile { profile in
            if !profile.ownedItems.contains(itemID) {
                profile.ownedItems.append(itemID)
            }
        }
    }

    /// Buy an item with coins. Returns true if purchase succeeded.
    func buyItem(_ item: ShopItem) -> Bool {
        guard !item.isFree else { return false }
        var purchased = false
        _ = updateProfile { profile in
            guard !self.isOwned(item.id, in: profile) else { return }
            guard profile.coins >= item.price else { return }
            profile.coins -= item.price
            if !profile.ownedItems.contains(item.id) {
                profile.ownedItems.append(item.id)
            }
            purchased = true
        }
        return purchased
    }

    // MARK: - Equip

    func equipItem(_ item: ShopItem) {
        guard ownsItem(item.id) else { return }
        _ = updateProfile { profile in
            switch item.category {
            case .themes:
                let themeName = item.id.replacingOccurrences(of: "theme_", with: "")
                profile.equippedTheme = themeName
            case .tapFX:
                profile.equippedTapFX = item.id
            case .trails:
                profile.equippedTrail = item.id
            case .badges:
                profile.equippedBadge = item.id
            case .avatars:
                let canonical = PlayerProfile.canonicalAvatarID(item.id)
                profile.equippedAvatar = canonical
                profile.avatar = canonical
            }
        }
    }

    func isEquipped(_ item: ShopItem) -> Bool {
        let profile = currentProfile()
        switch item.category {
        case .themes:
            let themeName = item.id.replacingOccurrences(of: "theme_", with: "")
            return profile.equippedTheme == themeName
        case .tapFX:   return profile.equippedTapFX == item.id
        case .trails:  return profile.equippedTrail == item.id
        case .badges:  return profile.equippedBadge == item.id
        case .avatars: return profile.equippedAvatar == item.id
        }
    }

    // MARK: - Theme Ownership Check (for Settings)

    func ownsTheme(_ themeName: String) -> Bool {
        if themeName == "default" { return true }
        let themeID = "theme_\(themeName)"
        return ownsItem(themeID)
    }

    // MARK: - Revive Eligibility

    /// Check if revive is available for the current session.
    /// Limit: 1 revive per game (no daily cap).
    func canRevive(mode: GameMode, hasUsedReviveThisGame: Bool) -> Bool {
        guard mode.supportsRevive else { return false }
        guard !hasUsedReviveThisGame else { return false }
        return true
    }

    // MARK: - No Ads

    var hasNoAds: Bool {
        currentProfile().noAds
    }

    func grantNoAds() {
        _ = updateProfile { profile in
            profile.noAds = true
        }
    }

}

// MARK: - Coin Sources (for analytics/tracking)
enum CoinSource: String {
    case gameplay       // All game mode earnings
    case purchase       // Real money IAP
    case achievement    // Achievement reward
    case challenge      // Challenge completion
    case quest          // Daily quest
    case dailyReward    // Daily login reward
    case wheelSpin      // Lucky wheel
}
