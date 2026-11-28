import SwiftUI

// MARK: - Shared Studio styling and small preview art

enum StudioStyle {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059)
    static let gold = Color(red: 0.98, green: 0.73, blue: 0.26)
    static let green = Color(red: 0.22, green: 0.82, blue: 0.49)
    static let purple = Color(red: 0.59, green: 0.28, blue: 0.98)
    static let card = Color.white.opacity(0.04)
    static let stroke = Color.white.opacity(0.08)
    /// The coin glyph of the shop header balance row (`ShopView.balanceRow`):
    /// every Studio price uses it (QA-19), never the coin emoji (U+1FA99).
    static let coinSymbol = "dollarsign.circle.fill"

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

// MARK: - Coins (QA-19)

/// The one number formatter for coin amounts in the shop: grouping separators
/// ("1,100" in English), no decimals. Used by every Studio price, the Studio
/// action bars, the Preview Studio unlock bar, purchase alerts and the shop
/// balance row.
enum CoinFormat {
    private static let currentLocaleFormatter = makeFormatter(.current)

    private static func makeFormatter(_ locale: Locale) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }

    /// "1,100" (grouped number only).
    static func string(_ amount: Int, locale: Locale? = nil) -> String {
        let formatter = locale.map(makeFormatter) ?? currentLocaleFormatter
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    /// "1,100 coins" / "1 coin" — for alerts and VoiceOver, where no glyph can be drawn.
    static func coins(_ amount: Int, locale: Locale? = nil) -> String {
        "\(string(amount, locale: locale)) \(amount == 1 ? "coin" : "coins")"
    }
}

/// Coin glyph + grouped amount. VoiceOver reads "1,100 coins".
struct StudioCoinAmount: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StudioStyle.coinSymbol)
            Text(CoinFormat.string(amount))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CoinFormat.coins(amount))
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
    /// Appends the coin glyph + formatted amount (price badges).
    var coins: Int? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            if !text.isEmpty { Text(text) }
            if let coins { StudioCoinAmount(amount: coins) }
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
    /// Appends " · <coin> 1,100" to the title (price buttons).
    var coins: Int? = nil
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                // At accessibility sizes wrap instead of shrinking to an unreadable size.
                Text(title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                if let coins {
                    Text("·")
                    StudioCoinAmount(amount: coins).fixedSize()
                }
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
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
        // Capped size (QA-20): a developer note must not take a whole screen at
        // accessibility text sizes.
        Text("DEBUG · proposed prices, unapproved (SHOP_CATALOG_PROPOSAL.md)")
            .font(.caption2.weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.large)
            .lineLimit(2)
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
