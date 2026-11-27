import Foundation
import Combine

// MARK: - Loadout store (contract stub — owned by Agent A)
//
// Holds the equipped loadout for the signed-in account and publishes the
// ownership-validated `resolved` cosmetics. Selection is local (per account);
// ownership always comes from PlayerProfile.ownedItems. Editing the stored
// loadout can never grant an item: unowned selections resolve to defaults.

@MainActor
final class CosmeticLoadoutStore: ObservableObject {
    static let shared = CosmeticLoadoutStore()

    @Published private(set) var loadout: CosmeticLoadout = .default
    @Published private(set) var resolved: ResolvedCosmetics = .defaults

    init() {}

    /// Equip one item. Returns false (and changes nothing) if not owned.
    @discardableResult
    func equip(_ item: CosmeticItem) -> Bool { false }

    /// Equip every *owned* item of a collection; unowned slots are left as they are.
    /// Returns the ids that were equipped.
    @discardableResult
    func equip(collection: CosmeticCollection) -> [String] { [] }

    /// Re-validate after ownership or account changes (purchase, refund, sign-in/out).
    func refresh() {}

    /// Resolve an arbitrary (preview) loadout without ownership checks — Preview Studio only.
    static func previewResolved(_ loadout: CosmeticLoadout) -> ResolvedCosmetics {
        ResolvedCosmetics.resolve(loadout, isOwned: { _ in true })
    }
}
