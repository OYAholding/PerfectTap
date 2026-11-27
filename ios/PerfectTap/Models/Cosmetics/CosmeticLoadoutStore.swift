import Foundation
import Combine

// MARK: - Loadout store
//
// Holds the equipped loadout for the signed-in account and publishes the
// ownership-validated `resolved` cosmetics. Selection is local (per account);
// ownership always comes from PlayerProfile.ownedItems. Editing the stored
// loadout can never grant an item: unowned selections resolve to defaults.
//
// Storage: UserDefaults `pt_cosmetic_loadout.<uid|anon>` = JSON `CosmeticLoadout`.
// Keyed by account so signing into another account shows that account's
// selection, and the selection of a signed-out account never leaks into the
// next one. (Cross-device sync is a follow-up: contract §6.)
//
// Performance: everything here is O(slots) on in-memory data (PlayerProfile is
// cached; UserDefaults is in-memory after first read). Gameplay reads
// `resolved` once at round bootstrap — never per tap.

@MainActor
final class CosmeticLoadoutStore: ObservableObject {
    static let shared = CosmeticLoadoutStore()

    static let storageKeyPrefix = "pt_cosmetic_loadout."

    @Published private(set) var loadout: CosmeticLoadout = .default
    @Published private(set) var resolved: ResolvedCosmetics = .defaults

    /// UserDefaults key of the account the current `loadout` belongs to.
    private(set) var storageKey: String

    private let defaults: UserDefaults
    private let loadProfile: () -> PlayerProfile
    private let isEnabled: () -> Bool
    /// Ownership snapshot taken at the last refresh/equip.
    private var profile: PlayerProfile

    /// - Parameters:
    ///   - defaults: where loadouts are stored (tests pass a throwaway suite).
    ///   - loadProfile: current profile (ownership + account id).
    ///   - isEnabled: Cosmetic Studio flag. OFF ⇒ `resolved` is always `.defaults`.
    init(defaults: UserDefaults = .standard,
         loadProfile: @escaping () -> PlayerProfile = { PlayerProfile.load() ?? PlayerProfile() },
         isEnabled: @escaping () -> Bool = { CosmeticStudioFlag.isEnabled }) {
        self.defaults = defaults
        self.loadProfile = loadProfile
        self.isEnabled = isEnabled
        let profile = loadProfile()
        self.profile = profile
        self.storageKey = Self.storageKey(forUID: profile.uid)
        let stored = Self.readLoadout(defaults: defaults, key: storageKey)
        self.loadout = stored
        self.resolved = Self.resolve(stored, profile: profile, enabled: isEnabled())
    }

    static func storageKey(forUID uid: String) -> String {
        storageKeyPrefix + (uid.isEmpty ? "anon" : uid)
    }

    // MARK: Ownership

    /// Default items are always owned; everything else must be in ownedItems.
    func isOwned(_ item: CosmeticItem) -> Bool {
        Self.isOwned(item.id, profile: profile)
    }

    private static func isOwned(_ itemID: String, profile: PlayerProfile) -> Bool {
        if let item = CosmeticCatalog.item(id: itemID), item.isDefault { return true }
        return EconomyManager.isOwned(itemID, in: profile)
    }

    // MARK: Equip

    /// Equip one item. Returns false (and changes nothing) if not owned.
    @discardableResult
    func equip(_ item: CosmeticItem) -> Bool {
        reloadProfile()
        // Trust only the catalog's copy: a caller-built CosmeticItem with a
        // borrowed id must not be able to smuggle different assets in.
        guard let catalogItem = CosmeticCatalog.item(id: item.id), catalogItem.slot == item.slot,
              Self.isOwned(catalogItem.id, profile: profile) else { return false }
        var next = loadout
        select(catalogItem, in: &next)
        commit(next)
        return true
    }

    /// Equip every *owned* item of a collection; unowned slots are left as they are.
    /// Returns the ids that were equipped.
    @discardableResult
    func equip(collection: CosmeticCollection) -> [String] {
        reloadProfile()
        var next = loadout
        var equipped: [String] = []
        for id in collection.itemIDs {
            guard let item = CosmeticCatalog.item(id: id), Self.isOwned(id, profile: profile) else { continue }
            select(item, in: &next)
            equipped.append(id)
        }
        if !equipped.isEmpty { commit(next) }
        return equipped
    }

    /// Re-validate after ownership or account changes (purchase, refund, sign-in/out).
    /// Re-reads the profile and the stored loadout of *its* account, so a
    /// different uid picks up a different selection and a revoked item falls
    /// back to its slot default on the next resolve.
    func refresh() {
        reloadProfile()
        let stored = Self.readLoadout(defaults: defaults, key: storageKey)
        if stored != loadout { loadout = stored }
        publishResolved()
    }

    /// Resolve an arbitrary (preview) loadout without ownership checks — Preview Studio only.
    static func previewResolved(_ loadout: CosmeticLoadout) -> ResolvedCosmetics {
        ResolvedCosmetics.resolve(loadout, isOwned: { _ in true })
    }

    // MARK: Internals

    /// Default items are stored as "no selection" so the stored JSON only ever
    /// holds deliberate choices.
    private func select(_ item: CosmeticItem, in loadout: inout CosmeticLoadout) {
        if item.isDefault {
            loadout.selections[item.slot] = nil
        } else {
            loadout.select(item)
        }
    }

    private func commit(_ next: CosmeticLoadout) {
        if next != loadout {
            loadout = next
            Self.writeLoadout(next, defaults: defaults, key: storageKey)
        }
        publishResolved()
    }

    /// Picks up the current profile; on an account switch, loads that account's loadout.
    private func reloadProfile() {
        profile = loadProfile()
        let key = Self.storageKey(forUID: profile.uid)
        guard key != storageKey else { return }
        storageKey = key
        let stored = Self.readLoadout(defaults: defaults, key: key)
        if stored != loadout { loadout = stored }
    }

    private func publishResolved() {
        let next = Self.resolve(loadout, profile: profile, enabled: isEnabled())
        if next != resolved { resolved = next }
    }

    private static func resolve(_ loadout: CosmeticLoadout, profile: PlayerProfile, enabled: Bool) -> ResolvedCosmetics {
        guard enabled else { return .defaults }
        return ResolvedCosmetics.resolve(loadout, isOwned: { isOwned($0, profile: profile) })
    }

    private static func readLoadout(defaults: UserDefaults, key: String) -> CosmeticLoadout {
        // Corrupt or foreign data reads as "nothing selected", never as an error
        // the player can see.
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(CosmeticLoadout.self, from: data) else { return .default }
        return decoded
    }

    private static func writeLoadout(_ loadout: CosmeticLoadout, defaults: UserDefaults, key: String) {
        if loadout.selections.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(loadout) {
            defaults.set(data, forKey: key)
        }
    }
}
