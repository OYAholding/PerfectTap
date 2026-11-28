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

    // MARK: - Economy service seam

    /// The single coin source/sink seam. Tests inject a fake or a
    /// `LedgerEconomyService` with an in-memory remote.
    var service: EconomyService = LedgerEconomyService.shared

    // MARK: - Currency

    /// Add coins from a legacy entry point. Flag OFF: unchanged local credit.
    /// Flag ON: no local mutation (each source has its own server path).
    func addCoins(_ amount: Int, source: CoinSource) {
        guard amount > 0, !service.isAuthoritative else { return }
        _ = updateProfile { profile in
            self.service.recordGrant(.legacy(source), legacyCoins: amount,
                                     countsTowardTotalEarned: true, profile: &profile)
        }
    }

    /// Spend coins locally. Flag ON: refused — spending is server-side only.
    func spendCoins(_ amount: Int) -> Bool {
        guard amount > 0, !service.isAuthoritative else { return false }
        var didSpend = false
        _ = updateProfile { profile in
            guard profile.coins >= amount else { return }
            profile.coins -= amount
            didSpend = true
        }
        return didSpend
    }

    /// Current coin balance (flag ON: the server-confirmed balance).
    var coinBalance: Int {
        service.spendableBalance(profile: currentProfile())
    }

    // MARK: - Item Ownership

    /// Check if player owns an item
    func ownsItem(_ itemID: String) -> Bool {
        let profile = currentProfile()
        return isOwned(itemID, in: profile)
    }

    func isOwned(_ itemID: String, in profile: PlayerProfile) -> Bool {
        Self.isOwned(itemID, in: profile)
    }

    nonisolated static func isOwned(_ itemID: String, in profile: PlayerProfile) -> Bool {
        // Free items are always owned
        if let item = ShopItem.item(id: itemID), item.isFree {
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

    /// Remove an item after a refund / revoked purchase. Unequips it.
    func revokeItem(_ itemID: String) {
        _ = updateProfile { profile in
            profile.ownedItems.removeAll { $0 == itemID }
            if itemID.hasPrefix("theme_"), profile.equippedTheme == ShopItem.themeName(forID: itemID) {
                profile.equippedTheme = "default"
            }
        }
    }

    /// Buy an item with coins locally (legacy path). Returns true if purchase
    /// succeeded. Premium skins are only sold through StoreKit. Flag ON: refused.
    func buyItem(_ item: ShopItem) -> Bool {
        guard !item.isFree, !item.isPremium, !service.isAuthoritative else { return false }
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

    /// Shop entry point for both rollout paths.
    func buyItemForCurrentRollout(_ item: ShopItem) async -> Bool {
        // Cosmetic Studio items are not in the server catalog yet: in
        // authoritative mode they are preview-only and never sent to the server.
        if item.category == .cosmetics {
            guard let cosmetic = item.cosmeticItem, canPurchaseCosmetic(cosmetic) else { return false }
        }
        let purchased = await service.purchaseItem(item)
        if purchased, item.category == .cosmetics { CosmeticLoadoutStore.shared.refresh() }
        return purchased
    }

    // MARK: - Equip

    func equipItem(_ item: ShopItem) {
        guard ownsItem(item.id) else { return }
        if item.category == .cosmetics {
            if let cosmetic = item.cosmeticItem { equipCosmetic(cosmetic) }
            return
        }
        _ = updateProfile { profile in
            switch item.category {
            case .themes:
                profile.equippedTheme = ShopItem.themeName(forID: item.id)
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
            case .cosmetics:
                break   // handled above; the loadout is not part of PlayerProfile
            }
        }
    }

    func isEquipped(_ item: ShopItem) -> Bool {
        isEquipped(item, in: currentProfile())
    }

    func isEquipped(_ item: ShopItem, in profile: PlayerProfile) -> Bool {
        switch item.category {
        case .themes:
            return profile.equippedTheme == ShopItem.themeName(forID: item.id)
        case .tapFX:   return profile.equippedTapFX == item.id
        case .trails:  return profile.equippedTrail == item.id
        case .badges:  return profile.equippedBadge == item.id
        case .avatars: return profile.equippedAvatar == item.id
        case .cosmetics:
            guard let cosmetic = item.cosmeticItem else { return false }
            return isCosmeticEquipped(cosmetic, in: profile)
        }
    }

    // MARK: - Cosmetic Studio (docs/cosmetics/OWNERSHIP_AND_ECONOMY.md)

    /// Cosmetic coin purchases exist only on the legacy (local) economy. With
    /// the authoritative economy ON the server catalog does not know these ids
    /// (`item_unavailable`) — the Studio shows them as "Preview only".
    /// Proposal for the server side: supabase/proposals/.
    var cosmeticPurchasesAvailable: Bool { !service.isAuthoritative }

    /// The catalog's copy of `item` (QA-13). Ownership, price and availability
    /// are decided on this copy, never on fields of a caller-built value.
    /// nil when the id is unknown or the value claims another slot/collection
    /// than the catalog (a forged value is refused, not reinterpreted).
    nonisolated static func canonicalCosmetic(_ item: CosmeticItem) -> CosmeticItem? {
        guard let canonical = CosmeticCatalog.item(id: item.id),
              canonical.slot == item.slot, canonical.collectionID == item.collectionID else { return nil }
        return canonical
    }

    /// The item can be bought with coins right now (not owned is checked separately).
    func canPurchaseCosmetic(_ item: CosmeticItem) -> Bool {
        guard cosmeticPurchasesAvailable, let canonical = Self.canonicalCosmetic(item) else { return false }
        return !canonical.isDefault && canonical.availability == .available
            && ShopItem.cosmeticPrice(canonical.id) > 0
    }

    func canPurchaseCosmeticBundle(_ bundle: CosmeticBundle) -> Bool {
        guard cosmeticPurchasesAvailable else { return false }
        return bundle.itemIDs.allSatisfy { id in
            guard let item = CosmeticCatalog.item(id: id) else { return false }
            return item.availability == .available
        }
    }

    /// Owned = the CATALOG item for this id is a free default, or the id is in
    /// `ownedItems` (QA-13). A caller-supplied `isDefault` / `collectionID` is
    /// never trusted: a forged value "claiming default" for a paid id is not owned.
    func isCosmeticOwned(_ item: CosmeticItem, in profile: PlayerProfile) -> Bool {
        Self.isCosmeticOwned(id: item.id, in: profile)
    }

    nonisolated static func isCosmeticOwned(id: String, in profile: PlayerProfile) -> Bool {
        guard let canonical = CosmeticCatalog.item(id: id) else { return false }
        return canonical.isDefault || isOwned(canonical.id, in: profile)
    }

    /// Equipped = what gameplay will actually render for that slot (the stored
    /// selection validated against this profile's ownership). O(1) per call
    /// (QA-17): only the stored selection of the item's own slot is validated —
    /// the same rule `ResolvedCosmetics.resolve` applies per slot — instead of
    /// resolving all nine slots for every card.
    func isCosmeticEquipped(_ item: CosmeticItem, in profile: PlayerProfile) -> Bool {
        Self.isCosmeticEquipped(item, loadout: CosmeticLoadoutStore.shared.loadout, in: profile)
    }

    nonisolated static func isCosmeticEquipped(_ item: CosmeticItem, loadout: CosmeticLoadout,
                                               in profile: PlayerProfile) -> Bool {
        guard let canonical = CosmeticCatalog.item(id: item.id), canonical.slot == item.slot else { return false }
        let selectedID = loadout.itemID(for: canonical.slot)
        let rendersSelection: Bool = {
            guard let selected = CosmeticCatalog.item(id: selectedID), selected.slot == canonical.slot else { return false }
            return selected.isDefault || isOwned(selectedID, in: profile)
        }()
        let renderedID = rendersSelection ? selectedID : CosmeticCatalog.defaultItemID(for: canonical.slot)
        return renderedID == canonical.id
    }

    /// Cheapest check for views that already hold a resolved loadout (e.g.
    /// `CosmeticLoadoutStore.shared.resolved`, read once per render): a
    /// dictionary lookup, no ownership work at all. Same answer as
    /// `isCosmeticEquipped(_:in: profile)` whenever `resolved` was resolved
    /// against that profile.
    nonisolated static func isCosmeticEquipped(_ item: CosmeticItem, in resolved: ResolvedCosmetics) -> Bool {
        resolved.item(for: item.slot).id == item.id
    }

    /// Equip one cosmetic. Refuses (returns false, changes nothing) when not owned.
    @discardableResult
    func equipCosmetic(_ item: CosmeticItem) -> Bool {
        guard isCosmeticOwned(item, in: currentProfile()) else { return false }
        return CosmeticLoadoutStore.shared.equip(item)
    }

    /// Equip every owned item of a collection; unowned slots stay as they are.
    @discardableResult
    func equipOwnedCosmetics(of collection: CosmeticCollection) -> [String] {
        CosmeticLoadoutStore.shared.equip(collection: collection)
    }

    func bundleQuote(_ bundle: CosmeticBundle, in profile: PlayerProfile) -> CosmeticBundleQuote {
        CosmeticBundlePricing.quote(for: bundle, bundlePrice: ShopItem.cosmeticBundlePrice(bundle),
                                    price: ShopItem.cosmeticPrice,
                                    isOwned: { Self.isOwned($0, in: profile) })
    }

    func bundleQuote(_ bundle: CosmeticBundle) -> CosmeticBundleQuote {
        bundleQuote(bundle, in: currentProfile())
    }

    enum CosmeticPurchaseResult: Equatable {
        /// Coins deducted once; `granted` are the newly owned ids.
        case purchased(granted: [String], charged: Int)
        /// Everything requested is already owned: nothing charged.
        case alreadyOwned
        case insufficientCoins(needed: Int)
        /// The price differs from the one the player confirmed (ownership or
        /// price changed in between): nothing charged, ask again.
        case priceChanged(current: Int)
        /// Preview only (authoritative economy) or not purchasable.
        case unavailable
        /// Reserved; `purchaseCosmetics` never returns it today (see QA-18 note
        /// there). Kept so `CosmeticPurchaseFlow`'s exhaustive switch and a
        /// future asynchronous server path keep compiling.
        case inProgress
    }

    /// Unlock the missing items of a collection bundle at the pro-rated price.
    /// Legacy economy: one atomic local update (check, deduct once, grant every
    /// missing id, single persist + cloud sync). Authoritative economy: refused.
    /// `expectedPrice`: the price shown in the confirmation; a mismatch charges nothing.
    func buyCosmeticBundle(_ bundle: CosmeticBundle, expectedPrice: Int? = nil) -> CosmeticPurchaseResult {
        guard canPurchaseCosmeticBundle(bundle) else { return .unavailable }
        return purchaseCosmetics(expectedPrice: expectedPrice) { profile in
            let quote = self.bundleQuote(bundle, in: profile)
            return (quote.missingItemIDs, quote.completionPrice)
        }
    }

    /// Unlock several individual items at once (Preview Studio "Unlock N items"):
    /// sum of their individual prices, one deduction, all granted together.
    func buyCosmeticItems(_ items: [CosmeticItem], expectedPrice: Int? = nil) -> CosmeticPurchaseResult {
        guard !items.isEmpty, items.allSatisfy(canPurchaseCosmetic) else { return .unavailable }
        return purchaseCosmetics(expectedPrice: expectedPrice) { profile in
            var seen = Set<String>()
            let missing = items.map(\.id).filter { !Self.isOwned($0, in: profile) && seen.insert($0).inserted }
            return (missing, missing.reduce(0) { $0 + ShopItem.cosmeticPrice($1) })
        }
    }

    /// A bundle whose missing items are exactly the unowned ones of `items`
    /// and whose completion price is lower — the player gets the bundle rate.
    func cheaperBundle(for items: [CosmeticItem], in profile: PlayerProfile) -> (bundle: CosmeticBundle, quote: CosmeticBundleQuote)? {
        let unowned = Set(items.map(\.id).filter { !Self.isOwned($0, in: profile) })
        guard !unowned.isEmpty else { return nil }
        let individual = cosmeticItemsPrice(items, in: profile)
        for bundle in CosmeticCatalog.bundles where canPurchaseCosmeticBundle(bundle) {
            let quote = bundleQuote(bundle, in: profile)
            if Set(quote.missingItemIDs) == unowned, quote.completionPrice < individual { return (bundle, quote) }
        }
        return nil
    }

    /// Price for `items` that would be charged now (owned ones excluded).
    func cosmeticItemsPrice(_ items: [CosmeticItem], in profile: PlayerProfile) -> Int {
        Set(items.map(\.id)).filter { !Self.isOwned($0, in: profile) }
            .reduce(0) { $0 + ShopItem.cosmeticPrice($1) }
    }

    /// Double-charge protection (QA-18). There is deliberately no "in flight"
    /// flag: this function is synchronous and `@MainActor`, so two calls can
    /// never interleave — a flag set and cleared inside it could never be
    /// observed by another caller. What actually prevents a double charge:
    ///  1. Serial execution: check, deduct and grant run without a suspension
    ///     point, and the profile is persisted before returning, so the next
    ///     call (second tap, second confirmation Task) reads the updated profile.
    ///  2. Ownership re-check: `plan` recomputes the missing ids from that fresh
    ///     profile; a repeat finds nothing missing ⇒ `.alreadyOwned`, no charge.
    ///  3. `expectedPrice`: if ownership or price changed after the player saw
    ///     the confirmation, the computed price differs ⇒ `.priceChanged`, no charge.
    ///  4. UI: `CosmeticPurchaseFlow.isPurchasing` drops a second `confirm` while
    ///     one is running (it matters for the async single-item path,
    ///     `buyItemForCurrentRollout`, whose legacy buy re-checks ownership too).
    /// An asynchronous (server) bundle path must add its own in-flight guard and
    /// an idempotency key; this function stays legacy/local only.
    private func purchaseCosmetics(expectedPrice: Int?,
                                   plan: (PlayerProfile) -> (missing: [String], price: Int)) -> CosmeticPurchaseResult {
        guard !service.isAuthoritative else { return .unavailable }

        var profile = currentProfile()
        let (missing, price) = plan(profile)
        guard !missing.isEmpty else { return .alreadyOwned }
        if let expectedPrice, expectedPrice != price { return .priceChanged(current: price) }
        guard price > 0 else { return .unavailable }
        guard profile.coins >= price else { return .insufficientCoins(needed: price - profile.coins) }

        profile.coins -= price
        for id in missing where !profile.ownedItems.contains(id) {
            profile.ownedItems.append(id)
        }
        // Same persistence as the legacy single-item buy: local save + cloud sync.
        persistProfile(profile)
        CosmeticLoadoutStore.shared.refresh()
        return .purchased(granted: missing, charged: price)
    }

    // MARK: - Theme Ownership Check (for Settings)

    func ownsTheme(_ themeName: String) -> Bool {
        if themeName == "default" { return true }
        let themeID = "theme_\(themeName)"
        return ownsItem(themeID)
    }

    // MARK: - Revive Eligibility

    /// Check if revive is available for the current session.
    /// Session guard: one revive per game. The rewarded placement separately
    /// enforces the owner-candidate cap of three verified claims per server day.
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

    /// Refunded Remove Ads purchase.
    func revokeNoAds() {
        _ = updateProfile { profile in
            profile.noAds = false
        }
    }

    /// Refunded coin pack: remove the credited coins, never below zero.
    func debitCoins(_ amount: Int) {
        guard amount > 0 else { return }
        service.applyPurchasedCoins(-amount)
    }

    /// StoreKit entry point used by PurchaseManager. Coin effects go through
    /// the economy service (flag ON: the server ledger credits/debits them).
    func apply(_ effect: EntitlementEffect) {
        switch effect {
        case .creditCoins(let n): if n > 0 { service.applyPurchasedCoins(n) }
        case .debitCoins(let n):  debitCoins(n)
        case .grantNoAds:         grantNoAds()
        case .revokeNoAds:        revokeNoAds()
        case .grantItem(let id):  grantItem(id)
        case .revokeItem(let id): revokeItem(id)
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
    case rewardedAd     // Optional, capped rewarded placement
}
