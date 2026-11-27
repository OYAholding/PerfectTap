import SwiftUI

// MARK: - Shared Studio styling and small preview art

enum StudioStyle {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059)
    static let gold = Color(red: 0.98, green: 0.73, blue: 0.26)
    static let green = Color(red: 0.22, green: 0.82, blue: 0.49)
    static let purple = Color(red: 0.59, green: 0.28, blue: 0.98)
    static let card = Color.white.opacity(0.04)
    static let stroke = Color.white.opacity(0.08)

    static func rarityColor(_ rarity: ShopRarity) -> Color {
        switch rarity {
        case .common:    return .white.opacity(0.5)
        case .rare:      return Color(red: 0.22, green: 0.58, blue: 0.98)
        case .epic:      return purple
        case .legendary: return gold
        }
    }

    static func palette(_ colors: [CosmeticRGBA], fallback: [Color] = [purple, Color(red: 0.22, green: 0.87, blue: 0.98)]) -> [Color] {
        let mapped = colors.map(\.color)
        return mapped.count >= 2 ? mapped : (mapped.isEmpty ? fallback : mapped + mapped)
    }
}

/// Small, static art for an item card: real tap-button / lives views for those
/// slots, a palette badge with the slot symbol for sounds, effects and haptics.
struct CosmeticItemArt: View {
    let item: CosmeticItem
    var fallbackColors: [Color]
    var compact: Bool = false

    private var collectionPalette: [Color] {
        let own = item.assets.palette
        if !own.isEmpty { return StudioStyle.palette(own) }
        return StudioStyle.palette(CosmeticCatalog.collection(id: item.collectionID)?.palette ?? [])
    }

    var body: some View {
        Group {
            switch item.slot {
            case .tapButton:
                CosmeticTapButtonSkin(item: item, fallbackColors: fallbackColors, label: "TAP",
                                      height: compact ? 30 : 40)
                    .scaleEffect(compact ? 0.9 : 1)
            case .lifeIcon:
                CosmeticLivesView(item: item, maxLives: 3, lives: 2)
            default:
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: collectionPalette, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(0.85)
                    Image(systemName: item.slot.systemImage)
                        .font(.system(size: compact ? 14 : 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: compact ? 30 : 40, height: compact ? 30 : 40)
            }
        }
        .frame(height: compact ? 34 : 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Capsule badge ("OWNED", "EQUIPPED", lock).
struct StudioBadge: View {
    let text: String
    var systemImage: String? = nil
    var color: Color

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.black))
        .foregroundColor(color)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
}

/// Primary pill button used across the Studio (44 pt minimum target).
struct StudioActionButton: View {
    let title: String
    var systemImage: String? = nil
    var color: Color
    var foreground: Color = .black
    var filled: Bool = true
    var expand: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1).minimumScaleFactor(0.75)
            }
            .font(.footnote.weight(.black))
            .foregroundColor(filled ? foreground : color)
            .padding(.horizontal, 12)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 44)
            .background(filled ? color : color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Amber "DEBUG" note shown only in DEBUG builds: catalog prices are proposals.
struct StudioDebugPriceNote: View {
    var body: some View {
        #if DEBUG
        Text("DEBUG: proposed prices (unapproved, docs/cosmetics/SHOP_CATALOG_PROPOSAL.md)")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.orange.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Debug build: proposed prices, not approved")
        #else
        EmptyView()
        #endif
    }
}

/// "Preview only — coming soon" label used when purchases are not offered.
struct StudioPreviewOnlyLabel: View {
    var body: some View {
        Label("Preview only — coming soon", systemImage: "eye")
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.55))
            .frame(minHeight: 44)
            .accessibilityLabel("Preview only, coming soon. Not available to buy yet.")
    }
}
