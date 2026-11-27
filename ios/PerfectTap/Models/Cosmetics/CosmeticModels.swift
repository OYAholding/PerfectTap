import SwiftUI

// MARK: - Modular cosmetics (Cosmetic Studio)
//
// Integration contract v1 — docs/cosmetics/INTEGRATION_CONTRACT.md.
//
// A cosmetic fills exactly one `CosmeticSlot`. Players mix items from different
// collections freely; a collection bundle is only a convenience that equips
// (and can unlock) every item of one collection.
//
// Invariants (enforced by tests, never by convention alone):
//  * Cosmetics never change scoring, timing windows, speed, lives, hitbox or
//    any competitive outcome. Nothing in this folder is read by TimingEngine or
//    the scoring path of GameViewModel.
//  * Ownership lives in `PlayerProfile.ownedItems` (server-validated when the
//    authoritative economy is on). The loadout only *selects*; selecting an
//    unowned item resolves to the slot default.
//  * Every slot has a free default item that reproduces the pre-Studio look,
//    sound and feel exactly.

/// One customisable aspect of gameplay feedback.
enum CosmeticSlot: String, CaseIterable, Codable, Identifiable {
    case tapButton
    case tapSound          // a whole sound pack (tap / good / great / perfect / miss / life lost / game over)
    case lifeIcon
    case tapEffect         // every tap
    case perfectEffect
    case missEffect
    case lifeLostEffect
    case gameOverEffect
    case haptics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tapButton:      return "Tap Button"
        case .tapSound:       return "Sounds"
        case .lifeIcon:       return "Life Icons"
        case .tapEffect:      return "Tap Effect"
        case .perfectEffect:  return "Perfect Effect"
        case .missEffect:     return "Miss Effect"
        case .lifeLostEffect: return "Life Lost Effect"
        case .gameOverEffect: return "Game Over Effect"
        case .haptics:        return "Haptics"
        }
    }

    var systemImage: String {
        switch self {
        case .tapButton:      return "hand.tap.fill"
        case .tapSound:       return "speaker.wave.2.fill"
        case .lifeIcon:       return "heart.fill"
        case .tapEffect:      return "sparkle"
        case .perfectEffect:  return "star.fill"
        case .missEffect:     return "xmark.circle.fill"
        case .lifeLostEffect: return "heart.slash.fill"
        case .gameOverEffect: return "flag.checkered"
        case .haptics:        return "iphone.radiowaves.left.and.right"
        }
    }

    /// The effect slots, in the order an event can trigger them.
    static let effectSlots: [CosmeticSlot] = [.tapEffect, .perfectEffect, .missEffect, .lifeLostEffect, .gameOverEffect]
}

/// Gameplay moments a cosmetic can react to. Emitted by the game view *after*
/// the tap has been scored — never on the scoring path.
enum CosmeticEvent: String, CaseIterable, Codable {
    case tap, good, great, perfect, miss, lifeLost, gameOver

    init(accuracy: TapAccuracy) {
        switch accuracy {
        case .perfect: self = .perfect
        case .great:   self = .great
        case .good:    self = .good
        case .miss:    self = .miss
        }
    }

    /// The effect slot that renders this event (nil = no visual effect slot).
    var effectSlot: CosmeticSlot? {
        switch self {
        case .tap, .good, .great: return .tapEffect
        case .perfect:            return .perfectEffect
        case .miss:               return .missEffect
        case .lifeLost:           return .lifeLostEffect
        case .gameOver:           return .gameOverEffect
        }
    }
}

/// Stable identifier of a collection ("default", "quack_attack", …).
typealias CosmeticCollectionID = String

/// Visual effect styles implemented natively (Canvas / SwiftUI shapes, no frame
/// sequences). New collections reuse a style with their own palette and sprite.
enum CosmeticEffectStyle: String, Codable, CaseIterable {
    case none              // draws nothing
    case legacyParticles   // the pre-Studio PERFECT/GREAT particles (honours equipped Tap FX)
    case splash            // water droplets + ring
    case ripple            // expanding concentric rings
    case sparks            // short radial streaks
    case starBurst         // stars orbiting a halo
    case sparkle           // four-point twinkle + ring
    case shockwave         // bright expanding ring with rays
    case feathers          // a few sprites drifting down
    case fluff             // soft puff clouds
    case scratch           // three claw slashes
    case smokePuff         // grey smoke puffs rising
    case explosion         // cartoon burst + smoke
    case rainDroop         // sad sprite + falling drops
}

/// Colours as plain RGBA so the catalog stays Codable / data-driven.
struct CosmeticRGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
}

/// Everything a renderer needs, referenced by name. Asset names point into
/// Assets.xcassets/Cosmetics; a missing asset falls back to the default look.
struct CosmeticAssetRefs: Codable, Hashable {
    /// Tap button: text-free background art. Life icon: active icon. Effect: sprite.
    var imageName: String? = nil
    /// Tap button pressed state / life icon depleted state.
    var secondaryImageName: String? = nil
    /// Small character/emblem drawn at the leading edge of a tap button.
    var emblemImageName: String? = nil
    var effectStyle: CosmeticEffectStyle? = nil
    /// Sound pack id (tapSound slot).
    var soundPackID: String? = nil
    /// Haptic style id (haptics slot).
    var hapticStyleID: String? = nil
    var palette: [CosmeticRGBA] = []
}

enum CosmeticAvailability: String, Codable {
    case available      // listed and purchasable
    case previewOnly    // listed, previewable, purchase disabled (e.g. pending server catalog)
    case hidden         // not listed (still resolves if already owned)
}

struct CosmeticItem: Identifiable, Hashable, Codable {
    /// Stable id, also the `ownedItems` entry: "<collection>.<slot>".
    let id: String
    /// Bumped when the item's assets change incompatibly (cache keys, manifests).
    var version: Int = 1
    let slot: CosmeticSlot
    let collectionID: CosmeticCollectionID
    let name: String
    var rarity: ShopRarity = .rare
    /// Proposed coin price (UNAPPROVED — docs/cosmetics/SHOP_CATALOG_PROPOSAL.md).
    /// 0 = free default. The live price is `EconomyConfig.current.shopPrice(itemID:fallback:)`.
    var proposedPrice: Int = 0
    var assets: CosmeticAssetRefs = CosmeticAssetRefs()
    var availability: CosmeticAvailability = .available

    var isDefault: Bool { collectionID == CosmeticCatalog.defaultCollectionID }

    static func makeID(collection: CosmeticCollectionID, slot: CosmeticSlot) -> String {
        "\(collection).\(slot.rawValue)"
    }
}

struct CosmeticCollection: Identifiable, Hashable, Codable {
    let id: CosmeticCollectionID
    let name: String
    let tagline: String
    /// Two or three brand colours for cards and previews.
    var palette: [CosmeticRGBA]
    /// Item shown on cards (usually the tap button).
    var heroItemID: String?
    var itemIDs: [String]
}

struct CosmeticBundle: Identifiable, Hashable, Codable {
    /// "bundle.<collection>" — never stored in ownedItems; a bundle is owned
    /// when every component is owned.
    let id: String
    let collectionID: CosmeticCollectionID
    let itemIDs: [String]
    /// Proposed full price when nothing is owned yet (UNAPPROVED).
    var proposedPrice: Int
}

/// The player's selection: one item id per slot. Missing slot = default.
/// Persisted locally per account (CosmeticLoadoutStore); it grants nothing.
struct CosmeticLoadout: Codable, Equatable {
    var selections: [CosmeticSlot: String] = [:]

    static let `default` = CosmeticLoadout()

    func itemID(for slot: CosmeticSlot) -> String {
        selections[slot] ?? CosmeticCatalog.defaultItemID(for: slot)
    }

    mutating func select(_ item: CosmeticItem) { selections[item.slot] = item.id }

    /// Equip every item of a collection (convenience; slots stay independent).
    mutating func apply(collection: CosmeticCollection) {
        for id in collection.itemIDs {
            if let item = CosmeticCatalog.item(id: id) { select(item) }
        }
    }
}

/// A loadout after ownership validation: every slot holds an item that exists
/// and is owned (or is the free default). This is what renderers consume.
struct ResolvedCosmetics: Equatable {
    let items: [CosmeticSlot: CosmeticItem]

    func item(for slot: CosmeticSlot) -> CosmeticItem {
        items[slot] ?? CosmeticCatalog.defaultItem(for: slot)
    }

    var soundPackID: String { item(for: .tapSound).assets.soundPackID ?? CosmeticCatalog.defaultSoundPackID }
    var hapticStyleID: String { item(for: .haptics).assets.hapticStyleID ?? "default" }

    static let defaults = ResolvedCosmetics(items: [:])

    /// Validates `loadout` against ownership. Pure: no I/O, cheap enough for view bodies.
    static func resolve(_ loadout: CosmeticLoadout, isOwned: (String) -> Bool) -> ResolvedCosmetics {
        var out: [CosmeticSlot: CosmeticItem] = [:]
        for slot in CosmeticSlot.allCases {
            let id = loadout.itemID(for: slot)
            if let item = CosmeticCatalog.item(id: id), item.slot == slot, item.isDefault || isOwned(id) {
                out[slot] = item
            } else {
                out[slot] = CosmeticCatalog.defaultItem(for: slot)
            }
        }
        return ResolvedCosmetics(items: out)
    }
}
