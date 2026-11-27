import Foundation

// MARK: - Cosmetic catalog (data only)
//
// Adding a collection = add one `CosmeticCollectionSpec` below + its assets
// (Assets.xcassets/Cosmetics/<collection>/) + its sound pack
// (Resources/Sounds/<collection>/). No gameplay code changes.
// Guide: docs/cosmetics/COLLECTION_GUIDE.md.
//
// Prices here are PROPOSALS (owner approval pending). Live prices always come
// from EconomyConfig / the server's economy_shop_items.

enum CosmeticCatalog {

    static let defaultCollectionID: CosmeticCollectionID = "default"
    static let defaultSoundPackID = "default"

    /// Slot specification for one collection: what each slot looks/sounds like.
    struct SlotSpec {
        let slot: CosmeticSlot
        let name: String
        var rarity: ShopRarity = .rare
        var price: Int = 0
        var assets: CosmeticAssetRefs = CosmeticAssetRefs()
    }

    struct CollectionSpec {
        let id: CosmeticCollectionID
        let name: String
        let tagline: String
        let palette: [CosmeticRGBA]
        let slots: [SlotSpec]
        var bundlePrice: Int = 0
        var availability: CosmeticAvailability = .available
    }

    // MARK: Specs

    static let specs: [CollectionSpec] = [defaultSpec, quackAttack, purrfectTap, boomMode]

    /// Free defaults: reproduce the pre-Studio game exactly.
    static let defaultSpec = CollectionSpec(
        id: defaultCollectionID, name: "Classic", tagline: "The original PerfectTap look and sound.",
        palette: [CosmeticRGBA(r: 0.76, g: 0.55, b: 0.99), CosmeticRGBA(r: 0.22, g: 0.87, b: 0.98)],
        slots: [
            SlotSpec(slot: .tapButton, name: "Classic Button", rarity: .common),
            SlotSpec(slot: .tapSound, name: "Classic Tones", rarity: .common,
                     assets: CosmeticAssetRefs(soundPackID: defaultSoundPackID)),
            SlotSpec(slot: .lifeIcon, name: "Classic Dots", rarity: .common),
            SlotSpec(slot: .tapEffect, name: "None", rarity: .common, assets: CosmeticAssetRefs(effectStyle: CosmeticEffectStyle.none)),
            SlotSpec(slot: .perfectEffect, name: "Classic Particles", rarity: .common,
                     assets: CosmeticAssetRefs(effectStyle: .legacyParticles)),
            SlotSpec(slot: .missEffect, name: "None", rarity: .common, assets: CosmeticAssetRefs(effectStyle: CosmeticEffectStyle.none)),
            SlotSpec(slot: .lifeLostEffect, name: "None", rarity: .common, assets: CosmeticAssetRefs(effectStyle: CosmeticEffectStyle.none)),
            SlotSpec(slot: .gameOverEffect, name: "None", rarity: .common, assets: CosmeticAssetRefs(effectStyle: CosmeticEffectStyle.none)),
            SlotSpec(slot: .haptics, name: "Classic Haptics", rarity: .common,
                     assets: CosmeticAssetRefs(hapticStyleID: "default")),
        ]
    )

    static let quackAttack: CollectionSpec = {
        let yellow = CosmeticRGBA(r: 1.0, g: 0.82, b: 0.16)
        let orange = CosmeticRGBA(r: 1.0, g: 0.55, b: 0.10)
        let water = CosmeticRGBA(r: 0.20, g: 0.68, b: 1.0)
        let aqua = CosmeticRGBA(r: 0.55, g: 0.90, b: 1.0)
        return CollectionSpec(
            id: "quack_attack", name: "Quack Attack", tagline: "Glossy rubber duck, big blue splashes.",
            palette: [yellow, orange, water],
            slots: [
                SlotSpec(slot: .tapButton, name: "Duck Button", rarity: .epic, price: 300,
                         assets: CosmeticAssetRefs(imageName: "cos_quack_button", secondaryImageName: "cos_quack_button_pressed",
                                                   emblemImageName: "cos_quack_emblem", palette: [yellow, orange, water])),
                SlotSpec(slot: .tapSound, name: "Quack Pack", rarity: .epic, price: 250,
                         assets: CosmeticAssetRefs(soundPackID: "quack_attack")),
                SlotSpec(slot: .lifeIcon, name: "Duck Lives", rarity: .rare, price: 200,
                         assets: CosmeticAssetRefs(imageName: "cos_quack_life", secondaryImageName: "cos_quack_life_lost")),
                SlotSpec(slot: .tapEffect, name: "Water Splash", rarity: .rare, price: 150,
                         assets: CosmeticAssetRefs(effectStyle: .splash, palette: [water, aqua])),
                SlotSpec(slot: .perfectEffect, name: "Golden Stars", rarity: .epic, price: 200,
                         assets: CosmeticAssetRefs(effectStyle: .starBurst, palette: [yellow, orange, CosmeticRGBA(r: 1, g: 0.95, b: 0.6)])),
                SlotSpec(slot: .missEffect, name: "Panic Splash", rarity: .rare, price: 120,
                         assets: CosmeticAssetRefs(effectStyle: .splash, palette: [water, CosmeticRGBA(r: 0.95, g: 0.3, b: 0.3)])),
                SlotSpec(slot: .lifeLostEffect, name: "Feather Drift", rarity: .rare, price: 150,
                         assets: CosmeticAssetRefs(imageName: "cos_quack_feather", effectStyle: .feathers, palette: [yellow, orange])),
                SlotSpec(slot: .gameOverEffect, name: "Duck Panic", rarity: .epic, price: 150,
                         assets: CosmeticAssetRefs(imageName: "cos_quack_gameover", effectStyle: .rainDroop, palette: [water, yellow])),
                SlotSpec(slot: .haptics, name: "Bouncy Haptics", rarity: .common, price: 100,
                         assets: CosmeticAssetRefs(hapticStyleID: "bouncy")),
            ],
            bundlePrice: 1100
        )
    }()

    static let purrfectTap: CollectionSpec = {
        let pink = CosmeticRGBA(r: 1.0, g: 0.42, b: 0.70)
        let cream = CosmeticRGBA(r: 1.0, g: 0.93, b: 0.88)
        let magenta = CosmeticRGBA(r: 0.92, g: 0.25, b: 0.62)
        return CollectionSpec(
            id: "purrfect_tap", name: "Purrfect Tap", tagline: "Soft paws, pink magic.",
            palette: [pink, cream, magenta],
            slots: [
                SlotSpec(slot: .tapButton, name: "Paw Button", rarity: .epic, price: 300,
                         assets: CosmeticAssetRefs(imageName: "cos_paw_button", secondaryImageName: "cos_paw_button_pressed",
                                                   emblemImageName: "cos_paw_emblem", palette: [pink, cream, magenta])),
                SlotSpec(slot: .tapSound, name: "Purr Pack", rarity: .epic, price: 250,
                         assets: CosmeticAssetRefs(soundPackID: "purrfect_tap")),
                SlotSpec(slot: .lifeIcon, name: "Paw Lives", rarity: .rare, price: 200,
                         assets: CosmeticAssetRefs(imageName: "cos_paw_life", secondaryImageName: "cos_paw_life_lost")),
                SlotSpec(slot: .tapEffect, name: "Pink Ripple", rarity: .rare, price: 150,
                         assets: CosmeticAssetRefs(effectStyle: .ripple, palette: [pink, magenta])),
                SlotSpec(slot: .perfectEffect, name: "Magic Sparkle", rarity: .epic, price: 200,
                         assets: CosmeticAssetRefs(effectStyle: .sparkle, palette: [pink, cream, CosmeticRGBA(r: 1, g: 0.85, b: 0.95)])),
                SlotSpec(slot: .missEffect, name: "Claw Swipe", rarity: .rare, price: 120,
                         assets: CosmeticAssetRefs(effectStyle: .scratch, palette: [magenta, CosmeticRGBA(r: 0.9, g: 0.2, b: 0.35)])),
                SlotSpec(slot: .lifeLostEffect, name: "Fluff Burst", rarity: .rare, price: 150,
                         assets: CosmeticAssetRefs(effectStyle: .fluff, palette: [cream, pink])),
                SlotSpec(slot: .gameOverEffect, name: "Dizzy Kitty", rarity: .epic, price: 150,
                         assets: CosmeticAssetRefs(imageName: "cos_paw_gameover", effectStyle: .rainDroop, palette: [pink, cream])),
                SlotSpec(slot: .haptics, name: "Soft Haptics", rarity: .common, price: 100,
                         assets: CosmeticAssetRefs(hapticStyleID: "soft")),
            ],
            bundlePrice: 1100
        )
    }()

    static let boomMode: CollectionSpec = {
        let ember = CosmeticRGBA(r: 1.0, g: 0.55, b: 0.08)
        let gold = CosmeticRGBA(r: 1.0, g: 0.80, b: 0.25)
        let steel = CosmeticRGBA(r: 0.22, g: 0.22, b: 0.30)
        return CollectionSpec(
            id: "boom_mode", name: "Boom Mode", tagline: "Cartoon bombs, sparks and stylised booms.",
            palette: [ember, gold, steel],
            slots: [
                SlotSpec(slot: .tapButton, name: "Bomb Button", rarity: .epic, price: 300,
                         assets: CosmeticAssetRefs(imageName: "cos_boom_button", secondaryImageName: "cos_boom_button_pressed",
                                                   emblemImageName: "cos_boom_emblem", palette: [steel, ember, gold],
                                                   pressStyle: .fuseGlow)),
                SlotSpec(slot: .tapSound, name: "Boom Pack", rarity: .epic, price: 250,
                         assets: CosmeticAssetRefs(soundPackID: "boom_mode")),
                SlotSpec(slot: .lifeIcon, name: "Bomb Lives", rarity: .rare, price: 200,
                         assets: CosmeticAssetRefs(imageName: "cos_boom_life", secondaryImageName: "cos_boom_life_lost")),
                SlotSpec(slot: .tapEffect, name: "Spark Flick", rarity: .rare, price: 150,
                         assets: CosmeticAssetRefs(effectStyle: .sparks, palette: [gold, ember])),
                SlotSpec(slot: .perfectEffect, name: "Golden Shockwave", rarity: .epic, price: 200,
                         assets: CosmeticAssetRefs(effectStyle: .shockwave, palette: [gold, ember, CosmeticRGBA(r: 1, g: 0.95, b: 0.7)])),
                SlotSpec(slot: .missEffect, name: "Fizzle", rarity: .rare, price: 120,
                         assets: CosmeticAssetRefs(effectStyle: .smokePuff, palette: [CosmeticRGBA(r: 0.45, g: 0.45, b: 0.5), steel])),
                SlotSpec(slot: .lifeLostEffect, name: "Cartoon Boom", rarity: .rare, price: 150,
                         assets: CosmeticAssetRefs(effectStyle: .explosion, palette: [ember, gold, CosmeticRGBA(r: 0.35, g: 0.33, b: 0.36)])),
                SlotSpec(slot: .gameOverEffect, name: "Final Boom", rarity: .epic, price: 150,
                         assets: CosmeticAssetRefs(imageName: "cos_boom_gameover", effectStyle: .explosion, palette: [ember, gold, steel])),
                SlotSpec(slot: .haptics, name: "Punchy Haptics", rarity: .common, price: 100,
                         assets: CosmeticAssetRefs(hapticStyleID: "punchy")),
            ],
            bundlePrice: 1100
        )
    }()

    // MARK: Derived catalog (built once)

    static let items: [CosmeticItem] = specs.flatMap { spec in
        spec.slots.map { s in
            CosmeticItem(id: CosmeticItem.makeID(collection: spec.id, slot: s.slot), slot: s.slot,
                         collectionID: spec.id, name: s.name, rarity: s.rarity, proposedPrice: s.price,
                         assets: s.assets, availability: spec.availability)
        }
    }

    private static let itemsByID: [String: CosmeticItem] =
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static let collections: [CosmeticCollection] = specs.map { spec in
        CosmeticCollection(id: spec.id, name: spec.name, tagline: spec.tagline, palette: spec.palette,
                           heroItemID: CosmeticItem.makeID(collection: spec.id, slot: .tapButton),
                           itemIDs: spec.slots.map { CosmeticItem.makeID(collection: spec.id, slot: $0.slot) })
    }

    /// Purchasable collections (the default collection is free and not a bundle).
    static let bundles: [CosmeticBundle] = specs.filter { $0.id != defaultCollectionID }.map { spec in
        CosmeticBundle(id: "bundle.\(spec.id)", collectionID: spec.id,
                       itemIDs: spec.slots.map { CosmeticItem.makeID(collection: spec.id, slot: $0.slot) },
                       proposedPrice: spec.bundlePrice)
    }

    static func item(id: String) -> CosmeticItem? { itemsByID[id] }
    static func collection(id: CosmeticCollectionID) -> CosmeticCollection? { collections.first { $0.id == id } }
    static func bundle(collectionID: CosmeticCollectionID) -> CosmeticBundle? { bundles.first { $0.collectionID == collectionID } }
    static func items(in slot: CosmeticSlot) -> [CosmeticItem] { items.filter { $0.slot == slot } }

    static func defaultItemID(for slot: CosmeticSlot) -> String {
        CosmeticItem.makeID(collection: defaultCollectionID, slot: slot)
    }

    static func defaultItem(for slot: CosmeticSlot) -> CosmeticItem {
        // Built from `defaultSpec`, which covers every slot (tested).
        itemsByID[defaultItemID(for: slot)]!
    }
}
