import SwiftUI

// MARK: - ShopView
//
// Select an item to preview it on a live tap bar, then buy / equip it from the
// action bar. Coin purchases ask for confirmation. Premium skins are sold only
// through StoreKit and are listed only when FeatureFlags allow it.
// Deliberately absent: loot boxes, countdown timers, "limited time" pressure,
// streak-loss offers.

struct ShopView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.effectsLevel) private var effects
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var selectedCategory: ShopTab = .themes
    @State private var selectedItem: ShopItem?
    @State private var showPurchaseAlert = false
    @State private var alertMessage = ""
    @State private var showCoinPacks = false
    @State private var confirmItem: ShopItem?

    private let iapEnabled = FeatureFlags.iapEnabled

    /// Shop tabs: the visible cosmetic categories plus Premium (when allowed).
    enum ShopTab: Hashable {
        case themes, tapFX, avatars, premium

        var title: String {
            switch self {
            case .themes:  return "Themes"
            case .tapFX:   return "Tap FX"
            case .avatars: return "Avatars"
            case .premium: return "Premium"
            }
        }

        var icon: String {
            switch self {
            case .themes:  return ShopCategory.themes.icon
            case .tapFX:   return ShopCategory.tapFX.icon
            case .avatars: return ShopCategory.avatars.icon
            case .premium: return "crown.fill"
            }
        }

        var items: [ShopItem] {
            switch self {
            case .themes:  return ShopItem.themes
            case .tapFX:   return ShopItem.tapFX
            case .avatars: return ShopItem.avatars
            case .premium: return ShopItem.premium
            }
        }

        static var visible: [ShopTab] {
            FeatureFlags.premiumSkinsVisible ? [.themes, .tapFX, .avatars, .premium] : [.themes, .tapFX, .avatars]
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "SHOP") { router.pop() }

                balanceRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                if iapEnabled && showCoinPacks {
                    coinPacksSection
                        .transition(.opacity)
                }

                ShopPreview(item: previewItem, equippedFX: profile.equippedTapFX,
                            equippedTheme: themeManager.current, glowStrength: effects.glowStrength)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                categoryTabs
                    .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(selectedCategory.items) { item in
                            ShopItemCard(
                                item: item,
                                isOwned: EconomyManager.shared.isOwned(item.id, in: profile),
                                isEquipped: EconomyManager.shared.isEquipped(item, in: profile),
                                isSelected: selectedItem?.id == item.id,
                                canAfford: profile.coins >= item.price,
                                priceLabel: priceLabel(for: item)
                            ) {
                                selectedItem = item
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    if selectedCategory == .premium {
                        premiumFooter
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }

                if let item = selectedItem {
                    actionBar(for: item)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.35))
                }
            }
        }
        .navigationBarHidden(true)
        .alert(alertMessage, isPresented: $showPurchaseAlert) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(
            confirmItem.map { "Buy \($0.name) for \($0.price) coins?" } ?? "",
            isPresented: Binding(get: { confirmItem != nil }, set: { if !$0 { confirmItem = nil } }),
            titleVisibility: .visible
        ) {
            if let item = confirmItem {
                Button("Buy for \(item.price) coins") { buyWithCoins(item) }
            }
            Button("Cancel", role: .cancel) { confirmItem = nil }
        }
        .onReceive(purchaseManager.$lastCoinPackCreditEvent) { event in
            guard let event else { return }
            defer { purchaseManager.consumeLastCoinPackCreditEvent() }
            guard event.origin == .transactionListener else { return }
            profile = PlayerProfile.load() ?? PlayerProfile()
            alertMessage = "Purchase completed: +\(event.coins) coins added."
            showPurchaseAlert = true
        }
        .onAppear {
            profile = EconomyManager.shared.currentProfile()
        }
    }

    // MARK: - Sections

    private var previewItem: ShopItem? {
        selectedItem
    }

    private var balanceRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                Text("\(profile.coins) coins")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if iapEnabled {
                Button {
                    showCoinPacks.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 13))
                        Text("BUY COINS").font(.system(size: 11, weight: .black)).tracking(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(red: 0.98, green: 0.62, blue: 0.18))
                    .cornerRadius(10)
                }
            }
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShopTab.visible, id: \.self) { tab in
                    Button {
                        selectedCategory = tab
                        selectedItem = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon).font(.system(size: 11))
                            Text(tab.title).font(.system(size: 11, weight: .bold)).tracking(1)
                        }
                        .foregroundColor(selectedCategory == tab ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(selectedCategory == tab ? Color.white.opacity(0.12) : Color.clear)
                        .cornerRadius(10)
                    }
                    .accessibilityAddTraits(selectedCategory == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var premiumFooter: some View {
        VStack(spacing: 8) {
            Text("Premium skins change how the game looks, never how it plays: the zones, the centre line and the indicator size are the same in every skin. Effects follow your Visual Effects setting.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Button {
                Task {
                    await purchaseManager.restorePurchases()
                    profile = EconomyManager.shared.currentProfile()
                    alertMessage = "Purchases restored."
                    showPurchaseAlert = true
                }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.59, green: 0.28, blue: 0.98))
            }
        }
    }

    // MARK: - Action bar

    @ViewBuilder
    private func actionBar(for item: ShopItem) -> some View {
        let owned = EconomyManager.shared.isOwned(item.id, in: profile)
        let equipped = EconomyManager.shared.isEquipped(item, in: profile)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(item.isPremium ? "Premium skin" : item.rarity.rawValue.capitalized)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            if equipped {
                Label("EQUIPPED", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
            } else if owned {
                actionButton("EQUIP", color: Color(red: 0.22, green: 0.82, blue: 0.49)) { equip(item) }
            } else if item.isPremium {
                if let product = purchaseManager.product(for: item) {
                    actionButton("BUY \(product.displayPrice)", color: Color(red: 0.98, green: 0.73, blue: 0.26)) {
                        buyPremium(item)
                    }
                    .disabled(purchaseManager.purchaseInProgress)
                } else {
                    Text("Not available yet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
                actionButton("BUY \(item.price) \u{1FA99}",
                             color: profile.coins >= item.price ? Color(red: 0.98, green: 0.73, blue: 0.26) : .gray) {
                    if profile.coins >= item.price {
                        confirmItem = item
                    } else {
                        alertMessage = "Not enough coins. You need \(item.price - profile.coins) more."
                        showPurchaseAlert = true
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .tracking(1)
                .foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(color)
                .cornerRadius(12)
        }
    }

    private func priceLabel(for item: ShopItem) -> String {
        if item.isPremium { return purchaseManager.product(for: item)?.displayPrice ?? "Premium" }
        return "\(item.price) \u{1FA99}"
    }

    // MARK: - Actions

    private func equip(_ item: ShopItem) {
        EconomyManager.shared.equipItem(item)
        profile = EconomyManager.shared.currentProfile()
        if item.category == .themes { themeManager.apply(profile: profile) }
    }

    private func buyWithCoins(_ item: ShopItem) {
        confirmItem = nil
        guard EconomyManager.shared.buyItem(item) else { return }
        AnalyticsService.logShopItemBought(itemId: item.id, price: item.price)
        profile = EconomyManager.shared.currentProfile()
        alertMessage = "\(item.name) is yours. Tap EQUIP to use it."
        showPurchaseAlert = true
    }

    private func buyPremium(_ item: ShopItem) {
        Task {
            let result = await purchaseManager.purchasePremium(item)
            profile = EconomyManager.shared.currentProfile()
            switch result {
            case .success:
                alertMessage = "\(item.name) is yours. Tap EQUIP to use it."
            case .pending:
                alertMessage = "Purchase is waiting for approval. The skin will appear when it is approved."
            case .deferred:
                alertMessage = "Payment received. The skin will be added as soon as you are back online."
            case .cancelled:
                return
            case .failed(let message):
                alertMessage = message
            }
            showPurchaseAlert = true
        }
    }

    // MARK: - Coin Packs IAP Section
    private var coinPacksSection: some View {
        VStack(spacing: 8) {
            ForEach(CoinPackID.allCases, id: \.rawValue) { pack in
                coinPackRow(pack)
            }

            // Remove Ads
            if !EconomyManager.shared.hasNoAds {
                Button {
                    Task {
                        let success = await purchaseManager.purchaseRemoveAds()
                        if success {
                            alertMessage = "Ads removed! Enjoy ad-free gameplay."
                            showPurchaseAlert = true
                            profile = PlayerProfile.load() ?? PlayerProfile()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            .foregroundColor(.green)
                        Text("Remove Ads Forever")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        if let product = purchaseManager.specialProducts.first(where: { $0.id == SpecialProductID.removeAds.rawValue }) {
                            Text(product.displayPrice)
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(.green)
                        } else {
                            Text("Loading...")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.green.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.2)))
                    .cornerRadius(12)
                }
            }

            if purchaseManager.purchaseInProgress {
                ProgressView().tint(.white).padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func coinPackRow(_ pack: CoinPackID) -> some View {
        Button {
            Task {
                let result = await purchaseManager.purchaseCoinPack(pack)
                switch result {
                case .success(let creditedCoins, let delivery):
                    profile = PlayerProfile.load() ?? PlayerProfile()
                    switch delivery {
                    case .creditedNow:
                        alertMessage = "+\(creditedCoins) coins added!"
                    case .alreadyCredited:
                        alertMessage = "Purchase confirmed. +\(creditedCoins) coins were already applied."
                    }
                    showPurchaseAlert = true
                case .pending:
                    alertMessage = "Purchase is pending approval. Coins will be added automatically when it completes."
                    showPurchaseAlert = true
                case .cancelled:
                    break
                case .failed(let message):
                    alertMessage = message
                    showPurchaseAlert = true
                }
            }
        } label: {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(pack.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        if let bonus = pack.bonusLabel {
                            Text(bonus)
                                .font(.system(size: 8, weight: .black))
                                .tracking(0.5)
                                .foregroundColor(.green)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text("\(pack.coinAmount) coins")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.7))
                }

                Spacer()

                if let product = purchaseManager.coinProducts.first(where: { $0.id == pack.rawValue }) {
                    Text(product.displayPrice)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                } else {
                    Text("...")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.98, green: 0.73, blue: 0.26).opacity(0.15)))
            .cornerRadius(12)
        }
        .disabled(purchaseManager.purchaseInProgress)
    }

}

// MARK: - Live preview

/// Static tap bar (indicator parked just left of centre) in the selected
/// theme, or the selected Tap FX / avatar. No animation: zero per-frame cost.
private struct ShopPreview: View {
    let item: ShopItem?
    let equippedFX: String
    let equippedTheme: AppTheme
    let glowStrength: Double

    private static let relay: IndicatorRelay = {
        let r = IndicatorRelay()
        r.position = 0.46
        return r
    }()

    private var theme: AppTheme {
        guard let item, item.category == .themes else { return equippedTheme }
        return AppTheme.named(ShopItem.themeName(forID: item.id))
    }

    var body: some View {
        VStack(spacing: 10) {
            if let item, item.category == .avatars {
                Text(item.icon).font(.system(size: 56))
                    .frame(height: 84)
            } else {
                TapBarView(indicatorRelay: Self.relay, theme: theme, glowStrength: glowStrength)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if let item, item.category == .tapFX {
                    fxSwatches(item.id)
                } else if let colors = theme.particleColors {
                    swatches(colors)
                }
            }
            Text(item.map { "Preview: \($0.name)" } ?? "Select an item to preview it")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(14)
        .background(theme.backgroundColor)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func fxSwatches(_ id: String) -> some View {
        swatches(ParticleEffectView.previewColors(for: id))
    }

    private func swatches(_ colors: [Color]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.prefix(6).enumerated()), id: \.offset) { _, c in
                Circle().fill(c).frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shop Item Card
private struct ShopItemCard: View {
    let item: ShopItem
    let isOwned: Bool
    let isEquipped: Bool
    let isSelected: Bool
    let canAfford: Bool
    let priceLabel: String
    let onTap: () -> Void

    private var rarityColor: Color {
        switch item.rarity {
        case .common:    return .white.opacity(0.5)
        case .rare:      return Color(red: 0.22, green: 0.58, blue: 0.98)
        case .epic:      return Color(red: 0.59, green: 0.28, blue: 0.98)
        case .legendary: return Color(red: 0.98, green: 0.73, blue: 0.26)
        }
    }

    private var status: String {
        if isEquipped { return "EQUIPPED" }
        if isOwned { return "OWNED" }
        return priceLabel
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(item.icon).font(.system(size: 28))
                Text(item.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(status)
                    .font(.system(size: 9, weight: .black)).tracking(0.5)
                    .foregroundColor(isEquipped ? Color(red: 0.22, green: 0.82, blue: 0.49)
                                     : isOwned ? .white.opacity(0.4)
                                     : (canAfford || item.isPremium) ? Color(red: 0.98, green: 0.73, blue: 0.26) : .red.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? rarityColor.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? rarityColor.opacity(0.7) : isEquipped ? rarityColor.opacity(0.3) : Color.white.opacity(0.07),
                                    lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .accessibilityLabel("\(item.name), \(status)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
