import Foundation

// MARK: - Cross-device loadout sync (PREPARED, NOT WIRED)
//
// Pure functions for the proposed `equipped_cosmetics` profile field —
// docs/cosmetics/LOADOUT_SYNC_CONTRACT.md. No networking, no persistence, and
// nothing in the app calls this yet: wiring needs the PlayerProfile /
// BackendCodec change owned by the release session (after PR #14).
//
// Invariants (tested in CosmeticEconomyHardeningTests):
//  * The wire value only *selects*. Decoding never grants ownership; rendering
//    still goes through `ResolvedCosmetics.resolve` with `ownedItems`.
//  * Unknown slots, unknown ids, ids of another slot and non-string values are
//    dropped one by one (a newer build's slot never breaks an older build).
//  * Default items are never sent: a missing slot means "default".
//  * Merge rule: the server's selection wins per slot, except for slots the
//    player changed on this device that the server has not acknowledged yet.

enum CosmeticLoadoutSync {

    /// Proposed key in the profile JSON (BackendCodec snake_case style).
    static let wireKey = "equipped_cosmetics"

    /// More entries than this is not a loadout (9 slots today): ignored whole.
    static let maxWireEntries = 32

    // MARK: Encode

    /// `CosmeticLoadout` → wire dictionary `slot rawValue → item id`.
    /// Default selections and ids that are unknown or belong to another slot
    /// are omitted. Ownership is not checked here (the server validates).
    static func encode(_ loadout: CosmeticLoadout) -> [String: String] {
        var out: [String: String] = [:]
        for (slot, id) in loadout.selections {
            guard let item = CosmeticCatalog.item(id: id), item.slot == slot, !item.isDefault else { continue }
            out[slot.rawValue] = id
        }
        return out
    }

    // MARK: Decode

    /// Wire value (as found in a decoded JSON dictionary: `[String: Any]`,
    /// `[String: String]`, `NSNull`, missing …) → selection. Never throws.
    /// - Parameter isOwned: optional ownership filter; when given, non-default
    ///   ids it rejects are dropped as well. It is only ever used to *drop*.
    static func decode(_ raw: Any?, isOwned: ((String) -> Bool)? = nil) -> CosmeticLoadout {
        guard let dict = raw as? [String: Any], dict.count <= maxWireEntries else { return .default }
        var selections: [CosmeticSlot: String] = [:]
        for (key, value) in dict {
            guard let slot = CosmeticSlot(rawValue: key), let id = value as? String,
                  let item = CosmeticCatalog.item(id: id), item.slot == slot else { continue }
            if item.isDefault { continue }                       // default = no selection
            if let isOwned, !isOwned(id) { continue }
            selections[slot] = id
        }
        return CosmeticLoadout(selections: selections)
    }

    // MARK: Merge

    /// Server wins per slot, except the slots in `pendingLocalSlots` (changed on
    /// this device, not yet acknowledged by a successful profile save), which
    /// keep the local value — including a local "back to default" (nil).
    /// The result is sanitized like `encode` (no unknown / wrong-slot ids).
    static func merge(server: CosmeticLoadout, local: CosmeticLoadout,
                      pendingLocalSlots: Set<CosmeticSlot>) -> CosmeticLoadout {
        var selections: [CosmeticSlot: String] = [:]
        for slot in CosmeticSlot.allCases {
            let id = pendingLocalSlots.contains(slot) ? local.selections[slot] : server.selections[slot]
            guard let id, let item = CosmeticCatalog.item(id: id), item.slot == slot, !item.isDefault else { continue }
            selections[slot] = id
        }
        return CosmeticLoadout(selections: selections)
    }

    /// Slots whose selection differs between two loadouts (a missing selection
    /// and an explicit default selection count as equal). The store would add
    /// these to its pending set on a local equip.
    static func changedSlots(from old: CosmeticLoadout, to new: CosmeticLoadout) -> Set<CosmeticSlot> {
        Set(CosmeticSlot.allCases.filter { old.itemID(for: $0) != new.itemID(for: $0) })
    }
}
