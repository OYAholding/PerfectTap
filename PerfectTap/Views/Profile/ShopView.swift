import SwiftUI

// MARK: - ShopView (full cosmetic shop — ported from Shop.jsx)
// NOTE: Real IAP requires StoreKit 2. Product IDs must match App Store Connect.

struct ShopView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var profile: PlayerProfile = PlayerProfile.load() ?? PlayerProfile()
    @State private var selectedCategory: ShopCategory = .themes
    @State private var showPurchaseAlert = false
    @State private var alertMessage = ""
    @State private var showCoinPacks = false

    /// Set to `true` to enable real-money IAP (coin packs + remove ads).
    /// Hidden for v1.0 launch — enable in a future update after gathering feedback.
    private let iapEnabled = false

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.039, blue: 0.059).ignoresSafeArea()
            VStack(spacing: 0) {
                navBar(title: "SHOP") { router.pop() }

                // Coin balance + Buy Coins button
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                        Text("\(profile.coins) coins")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.98, green: 0.73, blue: 0.26))
                    }

                    Spacer()

                    if iapEnabled {
                        Button {
                            withAnimation(.spring(response: 0.3)) { showCoinPacks.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 13))
                                Text("BUY COINS").font(.system(size: 11, weight: .black)).tracking(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.98, green: 0.73, blue: 0.26), Color(red: 0.98, green: 0.55, blue: 0.10)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // Coin packs (expandable) — hidden when IAP disabled
                if iapEnabled && showCoinPacks {
                    coinPacksSection
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ShopCategory.shopVisible, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon).font(.system(size: 11))
                                    Text(cat.rawValue).font(.system(size: 11, weight: .bold)).tracking(1)
                                }
                                .foregroundColor(selectedCategory == cat ? .white : .white.opacity(0.4))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(selectedCategory == cat ? Color.white.opacity(0.12) : Color.clear)
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 12)

                // Items grid
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(ShopItem.items(for: selectedCategory)) { item in
                            ShopItemCard(
                                item: item,
                                isOwned: isOwned(item),
                                isEquipped: isEquipped(item),
                                canAfford: profile.coins >= item.price,
                                onTap: { handleItemTap(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .alert(alertMessage, isPresented: $showPurchaseAlert) {
            Button("OK", role: .cancel) {}
        }
        .onReceive(purchaseManager.$lastCoinPackCreditEvent) { event in
            guard let event else { return }
            defer { purchaseManager.consumeLastCoinPackCreditEvent() }
            guard event.origin == .transactionListener else { return }
            profile = PlayerProfile.load() ?? PlayerProfile()
            alertMessage = "Purchase completed: +\(event.coins) coins added."
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

    private func isOwned(_ item: ShopItem) -> Bool {
        if item.isFree { return true }
        return profile.ownedItems.contains(item.id)
    }

    private func isEquipped(_ item: ShopItem) -> Bool {
        switch item.category {
        case .themes:  return profile.equippedTheme == themeNameFromId(item.id)
        case .tapFX:   return profile.equippedTapFX == item.id
        case .trails:  return profile.equippedTrail == item.id
        case .badges:  return profile.equippedBadge == item.id
        case .avatars: return profile.equippedAvatar == item.id
        }
    }

    private func themeNameFromId(_ id: String) -> String {
        id.replacingOccurrences(of: "theme_", with: "")
    }

    private func handleItemTap(_ item: ShopItem) {
        if isOwned(item) {
            EconomyManager.shared.equipItem(item)
            profile = EconomyManager.shared.currentProfile()
        } else if profile.coins >= item.price {
            if EconomyManager.shared.buyItem(item) {
                profile = EconomyManager.shared.currentProfile()
                AnalyticsService.logShopItemBought(itemId: item.id, price: item.price)
                alertMessage = "Purchased \(item.name)!"
                showPurchaseAlert = true
            }
        } else {
            alertMessage = "Not enough coins! You need \(item.price - profile.coins) more."
            showPurchaseAlert = true
        }
    }
}

// MARK: - Shop Item Card
private struct ShopItemCard: View {
    let item: ShopItem
    let isOwned: Bool
    let isEquipped: Bool
    let canAfford: Bool
    let onTap: () -> Void

    private var rarityColor: Color {
        switch item.rarity {
        case .common:    return .white.opacity(0.5)
        case .rare:      return Color(red: 0.22, green: 0.58, blue: 0.98)
        case .epic:      return Color(red: 0.59, green: 0.28, blue: 0.98)
        case .legendary: return Color(red: 0.98, green: 0.73, blue: 0.26)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(item.icon).font(.system(size: 32))

                Text(item.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                if isEquipped {
                    Text("EQUIPPED")
                        .font(.system(size: 9, weight: .black)).tracking(1)
                        .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.49))
                } else if isOwned {
                    Text("OWNED")
                        .font(.system(size: 9, weight: .black)).tracking(1)
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    Text("\(item.price) \u{1FA99}")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(canAfford ? Color(red: 0.98, green: 0.73, blue: 0.26) : .red.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isEquipped ? rarityColor.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isEquipped ? rarityColor.opacity(0.4) : Color.white.opacity(0.07))
                    )
            )
        }
    }
}
