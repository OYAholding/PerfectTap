import Foundation

// MARK: - Shop Item Categories
enum ShopCategory: String, CaseIterable {
    case themes   = "Themes"
    case tapFX    = "Tap FX"
    case trails   = "Trails"
    case badges   = "Badges"
    case avatars  = "Avatars"

    var icon: String {
        switch self {
        case .themes:  return "paintpalette.fill"
        case .tapFX:   return "sparkles"
        case .trails:  return "wind"
        case .badges:  return "shield.fill"
        case .avatars: return "person.fill"
        }
    }

    /// Categories visible in the shop UI.
    /// Trails and Badges are still hidden — their rendering is not yet implemented.
    /// Tap FX is now functional (particle colors change based on equipped FX).
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

    var isFree: Bool { price == 0 }
}

// MARK: - Full catalog (ported from Shop.jsx)
extension ShopItem {

    // --- Themes --- (prices balanced: first buy within 5-10 games)
    static let themes: [ShopItem] = [
        ShopItem(id: "theme_default",  name: "Nebula",   category: .themes, price: 0,   icon: "🌌", rarity: .common),
        ShopItem(id: "theme_neon",     name: "Neon",     category: .themes, price: 75,  icon: "💚", rarity: .common),
        ShopItem(id: "theme_fire",     name: "Fire",     category: .themes, price: 150, icon: "🔥", rarity: .rare),
        ShopItem(id: "theme_ice",      name: "Ice",      category: .themes, price: 200, icon: "❄️", rarity: .rare),
        ShopItem(id: "theme_gold",     name: "Gold",     category: .themes, price: 300, icon: "✨", rarity: .epic),
        ShopItem(id: "theme_galaxy",   name: "Galaxy",   category: .themes, price: 400, icon: "🌀", rarity: .epic),
        ShopItem(id: "theme_midnight", name: "Midnight", category: .themes, price: 250, icon: "🌙", rarity: .rare),
        ShopItem(id: "theme_sunset",   name: "Sunset",   category: .themes, price: 350, icon: "🌅", rarity: .epic),
        ShopItem(id: "theme_matrix",   name: "Matrix",   category: .themes, price: 600, icon: "🟢", rarity: .legendary),
    ]

    // --- Tap FX --- (prices balanced, now functional — changes particle colors)
    static let tapFX: [ShopItem] = [
        ShopItem(id: "fx_default", name: "Classic Pulse", category: .tapFX, price: 0,   icon: "💫", rarity: .common),
        ShopItem(id: "fx_ripple",  name: "Ripple",       category: .tapFX, price: 100, icon: "🌊", rarity: .common),
        ShopItem(id: "fx_spark",   name: "Spark",        category: .tapFX, price: 175, icon: "⚡", rarity: .rare),
        ShopItem(id: "fx_hearts",  name: "Hearts",       category: .tapFX, price: 150, icon: "💕", rarity: .rare),
        ShopItem(id: "fx_stars",   name: "Stars",        category: .tapFX, price: 250, icon: "⭐", rarity: .epic),
        ShopItem(id: "fx_confetti",name: "Confetti",     category: .tapFX, price: 225, icon: "🎊", rarity: .epic),
        ShopItem(id: "fx_shatter", name: "Shatter",      category: .tapFX, price: 400, icon: "💥", rarity: .legendary),
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
        ShopItem(id: "avatar_cool",    name: "Cool",     category: .avatars, price: 100, icon: "😎", rarity: .common),
        ShopItem(id: "avatar_ninja",   name: "Ninja",    category: .avatars, price: 175, icon: "🥷", rarity: .rare),
        ShopItem(id: "avatar_robot",   name: "Robot",    category: .avatars, price: 200, icon: "🤖", rarity: .rare),
        ShopItem(id: "avatar_alien",   name: "Alien",    category: .avatars, price: 250, icon: "👽", rarity: .epic),
        ShopItem(id: "avatar_wizard",  name: "Wizard",   category: .avatars, price: 300, icon: "🧙", rarity: .epic),
        ShopItem(id: "avatar_king",    name: "King",     category: .avatars, price: 400, icon: "🤴", rarity: .epic),
        ShopItem(id: "avatar_devil",   name: "Devil",    category: .avatars, price: 350, icon: "😈", rarity: .epic),
        ShopItem(id: "avatar_unicorn", name: "Unicorn",  category: .avatars, price: 500, icon: "🦄", rarity: .legendary),
        ShopItem(id: "avatar_dragon",  name: "Dragon",   category: .avatars, price: 750, icon: "🐉", rarity: .legendary),
    ]

    static func items(for category: ShopCategory) -> [ShopItem] {
        switch category {
        case .themes:  return themes
        case .tapFX:   return tapFX
        case .trails:  return trails
        case .badges:  return badges
        case .avatars: return avatars
        }
    }

    /// All items across all categories
    static var allItems: [ShopItem] {
        themes + tapFX + trails + badges + avatars
    }
}
