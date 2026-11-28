import Foundation

// MARK: - Shop Item Categories
enum ShopCategory: String, CaseIterable {
    case themes   = "Themes"
    case tapFX    = "Tap FX"
    case trails   = "Trails"
    case badges   = "Badges"
    case avatars  = "Avatars"
    /// Cosmetic Studio slot items (docs/cosmetics/INTEGRATION_CONTRACT.md).
    /// Never listed in the legacy grid: the Studio tab renders them.
    case cosmetics = "Cosmetics"

    var icon: String {
        switch self {
        case .themes:  return "paintpalette.fill"
        case .tapFX:   return "sparkles"
        case .trails:  return "wind"
        case .badges:  return "shield.fill"
        case .avatars: return "person.fill"
        case .cosmetics: return "wand.and.stars"
        }
    }

    /// Categories visible in the shop UI.
    /// Trails and Badges are still hidden — their rendering is not yet implemented.
    /// Tap FX is now functional (particle colors change based on equipped FX).
    /// Cosmetics are deliberately absent: they live in the Studio tab (flagged).
    static var shopVisible: [ShopCategory] {
        [.themes, .tapFX, .avatars]
    }
}

// MARK: - Rarity
enum ShopRarity: String, Codable {
    case common, rare, epic, legendary
}

// MARK: - Shop Item
struct ShopItem: Identifiable {
    let id: String
    let name: String
    let category: ShopCategory
    let price: Int        // 0 = free/default
    let icon: String      // emoji or SF Symbol
    let rarity: ShopRarity
    /// StoreKit product ID for skins sold for real money. Premium items are
    /// never sold for coins and grant no gameplay advantage.
    var premiumProductID: String? = nil

    var isPremium: Bool { premiumProductID != nil }
    var isFree: Bool { price == 0 && !isPremium }

    // MARK: Lookups (single place; was duplicated across ~10 views)

    static func themeID(forName name: String) -> String { "theme_\(name)" }
    static func themeName(forID id: String) -> String {
        id.hasPrefix("theme_") ? String(id.dropFirst("theme_".count)) : id
    }

    /// Emoji for an avatar ID ("😊" for unknown / empty).
    static func avatarEmoji(for id: String?) -> String {
        let canonical = PlayerProfile.canonicalAvatarID(id ?? "")
        return avatars.first(where: { $0.id == canonical })?.icon ?? "😊"
    }

    /// O(1): `itemsByID` is built once from `allItems` (QA-17). First entry wins
    /// for a duplicated id, exactly like the former `allItems.first { $0.id == id }`.
    static func item(id: String) -> ShopItem? { itemsByID[id] }
    static func item(productID: String) -> ShopItem? { premium.first { $0.premiumProductID == productID } }
}

// MARK: - Full catalog (ported from Shop.jsx)
extension ShopItem {

    // --- Themes --- (prices balanced: first buy within 5-10 games)
    static let themes: [ShopItem] = [
        ShopItem(id: "theme_default",  name: "Nebula",   category: .themes, price: 0,   icon: "🌌", rarity: .common),
        ShopItem(id: "theme_neon",     name: "Neon",     category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_neon", fallback: 75), icon: "💚", rarity: .common),
        ShopItem(id: "theme_fire",     name: "Fire",     category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_fire", fallback: 150), icon: "🔥", rarity: .rare),
        ShopItem(id: "theme_ice",      name: "Ice",      category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_ice", fallback: 200), icon: "❄️", rarity: .rare),
        ShopItem(id: "theme_gold",     name: "Gold",     category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_gold", fallback: 300), icon: "✨", rarity: .epic),
        ShopItem(id: "theme_galaxy",   name: "Galaxy",   category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_galaxy", fallback: 400), icon: "🌀", rarity: .epic),
        ShopItem(id: "theme_midnight", name: "Midnight", category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_midnight", fallback: 250), icon: "🌙", rarity: .rare),
        ShopItem(id: "theme_sunset",   name: "Sunset",   category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_sunset", fallback: 350), icon: "🌅", rarity: .epic),
        ShopItem(id: "theme_matrix",   name: "Matrix",   category: .themes, price: EconomyConfig.current.shopPrice(itemID: "theme_matrix", fallback: 600), icon: "🟢", rarity: .legendary),
    ]

    // --- Premium skins (real money, StoreKit; hidden until FeatureFlags allow) ---
    // Each is a theme with its own indicator finish and particle colours.
    // Zones, centre line and indicator size are identical to every other theme.
    static let premium: [ShopItem] = [
        ShopItem(id: "theme_neonpulse",  name: "Neon Pulse",    category: .themes, price: 0, icon: "💠", rarity: .legendary,
                 premiumProductID: "com.perfecttap.skin.neonpulse"),
        ShopItem(id: "theme_chrome",     name: "Liquid Chrome", category: .themes, price: 0, icon: "🪩", rarity: .legendary,
                 premiumProductID: "com.perfecttap.skin.liquidchrome"),
        ShopItem(id: "theme_glitch",     name: "Glitch Mode",   category: .themes, price: 0, icon: "👾", rarity: .legendary,
                 premiumProductID: "com.perfecttap.skin.glitchmode"),
        ShopItem(id: "theme_cosmicgold", name: "Cosmic Gold",   category: .themes, price: 0, icon: "🌟", rarity: .legendary,
                 premiumProductID: "com.perfecttap.skin.cosmicgold"),
    ]

    static var premiumProductIDs: [String] { premium.compactMap(\.premiumProductID) }

    // --- Tap FX --- (prices balanced, now functional — changes particle colors)
    static let tapFX: [ShopItem] = [
        ShopItem(id: "fx_default", name: "Classic Pulse", category: .tapFX, price: 0,   icon: "💫", rarity: .common),
        ShopItem(id: "fx_ripple",  name: "Ripple",       category: .tapFX, price: EconomyConfig.current.shopPrice(itemID: "fx_ripple", fallback: 100), icon: "🌊", rarity: .common),
        ShopItem(id: "fx_spark",   name: "Spark",        category: .tapFX, price: EconomyConfig.current.shopPrice(itemID: "fx_spark", fallback: 175), icon: "⚡", rarity: .rare),
        ShopItem(id: "fx_hearts",  name: "Hearts",       category: .tapFX, price: EconomyConfig.current.shopPrice(itemID: "fx_hearts", fallback: 150), icon: "💕", rarity: .rare),
        ShopItem(id: "fx_stars",   name: "Stars",        category: .tapFX, price: EconomyConfig.current.shopPrice(itemID: "fx_stars", fallback: 250), icon: "⭐", rarity: .epic),
        ShopItem(id: "fx_confetti",name: "Confetti",     category: .tapFX, price: EconomyConfig.current.shopPrice(itemID: "fx_confetti", fallback: 225), icon: "🎊", rarity: .epic),
        ShopItem(id: "fx_shatter", name: "Shatter",      category: .tapFX, price: EconomyConfig.current.shopPrice(itemID: "fx_shatter", fallback: 400), icon: "💥", rarity: .legendary),
    ]

    // --- Trails ---
    static let trails: [ShopItem] = [
        ShopItem(id: "trail_none",      name: "None",      category: .trails, price: 0,    icon: "➖", rarity: .common),
        ShopItem(id: "trail_glow",      name: "Glow",      category: .trails, price: 250,  icon: "💡", rarity: .common),
        ShopItem(id: "trail_fire",      name: "Fire",      category: .trails, price: 400,  icon: "🔥", rarity: .rare),
        ShopItem(id: "trail_rainbow",   name: "Rainbow",   category: .trails, price: 500,  icon: "🌈", rarity: .epic),
        ShopItem(id: "trail_pixel",     name: "Pixel",     category: .trails, price: 350,  icon: "🟩", rarity: .rare),
        ShopItem(id: "trail_lightning", name: "Lightning",  category: .trails, price: 600,  icon: "⚡", rarity: .epic),
        ShopItem(id: "trail_galaxy",    name: "Galaxy",    category: .trails, price: 1000, icon: "🌌", rarity: .legendary),
    ]

    // --- Badges ---
    static let badges: [ShopItem] = [
        ShopItem(id: "badge_neon",      name: "Neon Badge",  category: .badges, price: 0,    icon: "⚡", rarity: .epic),
        ShopItem(id: "badge_rookie",     name: "Rookie",      category: .badges, price: 100,  icon: "🏅", rarity: .common),
        ShopItem(id: "badge_pro",        name: "Pro Player",  category: .badges, price: 300,  icon: "⭐", rarity: .rare),
        ShopItem(id: "badge_legend",     name: "Legend",       category: .badges, price: 600,  icon: "👑", rarity: .epic),
        ShopItem(id: "badge_deathdefier",name: "Death Defier", category: .badges, price: 400,  icon: "💀", rarity: .rare),
        ShopItem(id: "badge_comboking",  name: "Combo King",  category: .badges, price: 400,  icon: "🔗", rarity: .rare),
        ShopItem(id: "badge_diamond",    name: "Diamond",     category: .badges, price: 1000, icon: "💎", rarity: .legendary),
        ShopItem(id: "badge_onfire",     name: "On Fire",     category: .badges, price: 500,  icon: "🔥", rarity: .epic),
        ShopItem(id: "badge_cosmic",     name: "Cosmic",      category: .badges, price: 800,  icon: "🌌", rarity: .epic),
        ShopItem(id: "badge_royal",      name: "Royal",       category: .badges, price: 1500, icon: "🏰", rarity: .legendary),
    ]

    // --- Avatars --- (prices balanced for new economy)
    static let avatars: [ShopItem] = [
        ShopItem(id: "avatar_default", name: "Default",  category: .avatars, price: 0,   icon: "😊", rarity: .common),
        ShopItem(id: "avatar_cool",    name: "Cool",     category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_cool", fallback: 100), icon: "😎", rarity: .common),
        ShopItem(id: "avatar_ninja",   name: "Ninja",    category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_ninja", fallback: 175), icon: "🥷", rarity: .rare),
        ShopItem(id: "avatar_robot",   name: "Robot",    category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_robot", fallback: 200), icon: "🤖", rarity: .rare),
        ShopItem(id: "avatar_alien",   name: "Alien",    category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_alien", fallback: 250), icon: "👽", rarity: .epic),
        ShopItem(id: "avatar_wizard",  name: "Wizard",   category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_wizard", fallback: 300), icon: "🧙", rarity: .epic),
        ShopItem(id: "avatar_king",    name: "King",     category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_king", fallback: 400), icon: "🤴", rarity: .epic),
        ShopItem(id: "avatar_devil",   name: "Devil",    category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_devil", fallback: 350), icon: "😈", rarity: .epic),
        ShopItem(id: "avatar_unicorn", name: "Unicorn",  category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_unicorn", fallback: 500), icon: "🦄", rarity: .legendary),
        ShopItem(id: "avatar_dragon",  name: "Dragon",   category: .avatars, price: EconomyConfig.current.shopPrice(itemID: "avatar_dragon", fallback: 750), icon: "🐉", rarity: .legendary),
    ]

    static func items(for category: ShopCategory) -> [ShopItem] {
        switch category {
        case .themes:  return themes
        case .tapFX:   return tapFX
        case .trails:  return trails
        case .badges:  return badges
        case .avatars: return avatars
        case .cosmetics: return cosmetics
        }
    }

    /// All items across all categories (premium and cosmetics included, for
    /// ownership lookups, legacy buy, restore and sync). Stored once (QA-17):
    /// every component is itself a `static let`, so prices were already fixed at
    /// first access and concatenating them on every call only cost time.
    static let allItems: [ShopItem] =
        themes + premium + tapFX + trails + badges + avatars + cosmetics + cosmeticDefaults

    /// Id index over `allItems` (first occurrence wins).
    private static let itemsByID: [String: ShopItem] =
        Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}

// MARK: - Cosmetic Studio bridge
//
// Every purchasable cosmetic slot item is an ordinary `ShopItem` (category
// `.cosmetics`, id `<collection>.<slot>`), so ownership (`ownedItems`), the
// legacy coin buy, restore, account switching and cloud sync work unchanged.
// Prices: `EconomyConfig.current.shopPrice(itemID:fallback:)` with the catalog's
// PROPOSED price as fallback (UNAPPROVED — docs/cosmetics/SHOP_CATALOG_PROPOSAL.md).
extension ShopItem {

    /// Purchasable cosmetic items (free Classic defaults excluded).
    static let cosmetics: [ShopItem] = CosmeticCatalog.items.filter { !$0.isDefault }.map { item in
        ShopItem(id: item.id, name: item.name, category: .cosmetics,
                 price: EconomyConfig.current.shopPrice(itemID: item.id, fallback: item.proposedPrice),
                 icon: item.slot.systemImage, rarity: item.rarity)
    }

    /// Classic defaults: price 0 ⇒ `isFree` ⇒ always owned.
    static let cosmeticDefaults: [ShopItem] = CosmeticCatalog.items.filter(\.isDefault).map { item in
        ShopItem(id: item.id, name: item.name, category: .cosmetics, price: 0,
                 icon: item.slot.systemImage, rarity: item.rarity)
    }

    /// The catalog item behind a `.cosmetics` shop item.
    var cosmeticItem: CosmeticItem? {
        category == .cosmetics ? CosmeticCatalog.item(id: id) : nil
    }

    /// Shop item for a catalog item (nil only for unknown ids).
    /// Looked up by id in the catalog (O(1)); a caller-built value whose
    /// slot / collection disagree with the catalog's copy gets nil (QA-13).
    static func cosmetic(_ item: CosmeticItem) -> ShopItem? {
        guard let canonical = CosmeticCatalog.item(id: item.id),
              canonical.slot == item.slot, canonical.collectionID == item.collectionID,
              let shopItem = itemsByID[item.id], shopItem.category == .cosmetics else { return nil }
        return shopItem
    }

    /// Live coin price of a cosmetic item (0 for defaults and unknown ids). O(1).
    static func cosmeticPrice(_ itemID: String) -> Int {
        guard let shopItem = itemsByID[itemID], shopItem.category == .cosmetics else { return 0 }
        return shopItem.price
    }

    /// Live price of a full bundle (nothing owned yet).
    static func cosmeticBundlePrice(_ bundle: CosmeticBundle) -> Int {
        EconomyConfig.current.shopPrice(itemID: bundle.id, fallback: bundle.proposedPrice)
    }
}

// MARK: - Bundle pricing (fair ownership policy)
//
// A bundle is a discount on a whole collection. If the player already owns some
// of its items, completing the bundle costs the bundle price pro-rated by the
// LIST VALUE of what is still missing:
//
//     completion = round(bundlePrice × missingListValue / totalListValue)
//
// clamped to [1, missingListValue] while anything is missing (never more than
// buying the missing items one by one, never free), and 0 / "Owned" when the
// collection is complete. Already-owned items are never charged again.
// Alternatives considered: docs/cosmetics/OWNERSHIP_AND_ECONOMY.md.

struct CosmeticBundleQuote: Equatable {
    let bundleID: String
    let collectionID: CosmeticCollectionID
    /// Full bundle price (nothing owned).
    let bundlePrice: Int
    let itemIDs: [String]
    let missingItemIDs: [String]
    /// Sum of individual prices of every item in the bundle.
    let totalListValue: Int
    /// Sum of individual prices of the missing items.
    let missingListValue: Int
    /// What the player pays now to own the whole collection.
    let completionPrice: Int

    var ownedCount: Int { itemIDs.count - missingItemIDs.count }
    var totalCount: Int { itemIDs.count }
    var isComplete: Bool { missingItemIDs.isEmpty }
    /// Coins saved versus buying the missing items one by one.
    var savings: Int { max(0, missingListValue - completionPrice) }
}

enum CosmeticBundlePricing {

    /// Pure pro-rating rule (integer, round half up).
    static func completionPrice(bundlePrice: Int, totalListValue: Int, missingListValue: Int) -> Int {
        guard missingListValue > 0 else { return 0 }
        guard totalListValue > 0, bundlePrice > 0 else { return missingListValue }
        let missing = min(missingListValue, totalListValue)
        // round(bundle * missing / total) with integers: (2·b·m + t) / (2·t)
        let numerator = 2 * Int64(bundlePrice) * Int64(missing) + Int64(totalListValue)
        let prorated = Int(numerator / (2 * Int64(totalListValue)))
        return min(missingListValue, max(1, prorated))
    }

    static func quote(for bundle: CosmeticBundle,
                      bundlePrice: Int,
                      price: (String) -> Int,
                      isOwned: (String) -> Bool) -> CosmeticBundleQuote {
        let missing = bundle.itemIDs.filter { !isOwned($0) }
        let total = bundle.itemIDs.reduce(0) { $0 + max(0, price($1)) }
        let missingValue = missing.reduce(0) { $0 + max(0, price($1)) }
        return CosmeticBundleQuote(
            bundleID: bundle.id, collectionID: bundle.collectionID, bundlePrice: bundlePrice,
            itemIDs: bundle.itemIDs, missingItemIDs: missing,
            totalListValue: total, missingListValue: missingValue,
            completionPrice: completionPrice(bundlePrice: bundlePrice, totalListValue: total,
                                             missingListValue: missingValue))
    }
}
