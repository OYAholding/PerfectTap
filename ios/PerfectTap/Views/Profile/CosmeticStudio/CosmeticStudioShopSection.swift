import SwiftUI

// MARK: - Studio tab of the shop (FeatureFlags.cosmeticStudioEnabled)
//
// Collections (bundles, pro-rated) and individual slot items. Every item can be
// previewed for free in the Preview Studio before buying. No timers, no loot
// boxes, no pressure copy; prices are always shown before confirmation.

enum CosmeticStudioFilter: String, CaseIterable, Identifiable {
    case collections, tapButtons, sounds, lifeIcons, effects, owned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections: return "Collections"
        case .tapButtons:  return "Tap Buttons"
        case .sounds:      return "Sound & Feel"
        case .lifeIcons:   return "Life Icons"
        case .effects:     return "Effects"
        case .owned:       return "Owned"
        }
    }

    var icon: String {
        switch self {
        case .collections: return "square.stack.3d.up.fill"
        case .tapButtons:  return CosmeticSlot.tapButton.systemImage
        case .sounds:      return CosmeticSlot.tapSound.systemImage
        case .lifeIcons:   return CosmeticSlot.lifeIcon.systemImage
        case .effects:     return "sparkles"
        case .owned:       return "checkmark.seal.fill"
        }
    }

    /// Slots listed under this filter (empty for collections; all for owned).
    var slots: [CosmeticSlot] {
        switch self {
        case .collections: return []
        case .tapButtons:  return [.tapButton]
        case .sounds:      return [.tapSound, .haptics]
        case .lifeIcons:   return [.lifeIcon]
        case .effects:     return CosmeticSlot.effectSlots
        case .owned:       return CosmeticSlot.allCases
        }
    }

    /// Items shown for this filter. Slot filters include the free Classic item
    /// (so players can go back to it); Owned lists purchased items only.
    func items(isOwned: (CosmeticItem) -> Bool) -> [CosmeticItem] {
        let listed = CosmeticCatalog.items.filter { item in
            slots.contains(item.slot) && (item.availability != .hidden || isOwned(item))
        }
        switch self {
        case .collections: return []
        case .owned:       return listed.filter { !$0.isDefault && isOwned($0) }
        default:           return listed
        }
    }
}

struct CosmeticStudioShopSection: View {
    @Binding var profile: PlayerProfile
    let spendable: Int

    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var loadoutStore = CosmeticLoadoutStore.shared
    @StateObject private var flow = CosmeticPurchaseFlow()
    @State private var filter: CosmeticStudioFilter = .collections
    @State private var selected: CosmeticItem?
    @State private var previewRequest: CosmeticPreviewRequest?

    private var economy: EconomyManager { .shared }
    private var fallbackColors: [Color] { [themeManager.current.barGradient.0, themeManager.current.barGradient.1] }
    private func isOwned(_ item: CosmeticItem) -> Bool { economy.isCosmeticOwned(item, in: profile) }
    private func isEquipped(_ item: CosmeticItem) -> Bool {
        _ = loadoutStore.loadout   // re-render when the loadout changes
        return economy.isCosmeticEquipped(item, in: profile)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.bottom, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    StudioDebugPriceNote()
                    if !flow.purchasesAvailable { previewOnlyBanner }
                    previewEntry
                    if filter == .collections {
                        ForEach(CosmeticCatalog.collections) { collectionCard($0) }
                    } else {
                        itemGrid
                    }
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            if let item = selected, filter != .collections {
                actionBar(for: item)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.35))
            }
        }
        .cosmeticPurchaseFlow(flow)
        .sheet(item: $previewRequest, onDismiss: reload) { request in
            CosmeticPreviewStudioView(request: request)
                .environmentObject(themeManager)
        }
        .onAppear {
            flow.onChange = { reload() }
        }
    }

    private func reload() {
        profile = economy.currentProfile()
        CosmeticLoadoutStore.shared.refresh()
    }

    // MARK: Filter

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CosmeticStudioFilter.allCases) { f in
                    Button {
                        filter = f
                        selected = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.icon).font(.caption2)
                            Text(f.title).font(.caption.weight(.bold))
                        }
                        .foregroundColor(filter == f ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(filter == f ? StudioStyle.gold : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var previewOnlyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill").foregroundColor(StudioStyle.gold)
            Text("Preview only — Studio items are coming soon. You can try every item for free.")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(StudioStyle.gold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var previewEntry: some View {
        Button { previewRequest = CosmeticPreviewRequest() } label: {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.title3)
                    .foregroundColor(StudioStyle.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Preview Studio").font(.subheadline.weight(.bold)).foregroundColor(.white)
                    Text("Mix & match any item and try it before you decide.")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(StudioStyle.purple.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(StudioStyle.purple.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityIdentifier("studio.openPreview")
    }

    private var footnote: some View {
        Text("Cosmetics change how the game looks, sounds and feels — never timing, scoring, lives or speed.")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    // MARK: Collection cards

    private func collectionCard(_ collection: CosmeticCollection) -> some View {
        let isDefault = collection.id == CosmeticCatalog.defaultCollectionID
        let bundle = CosmeticCatalog.bundle(collectionID: collection.id)
        let quote = bundle.map { economy.bundleQuote($0, in: profile) }
        let items = collection.itemIDs.compactMap(CosmeticCatalog.item(id:))
        let ownedCount = isDefault ? items.count : (quote?.ownedCount ?? items.filter(isOwned).count)
        let hero = CosmeticCatalog.item(id: collection.heroItemID ?? "") ?? CosmeticCatalog.defaultItem(for: .tapButton)
        let life = items.first { $0.slot == .lifeIcon } ?? CosmeticCatalog.defaultItem(for: .lifeIcon)
        let colors = StudioStyle.palette(collection.palette)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.name).font(.headline.weight(.black)).foregroundColor(.white)
                    Text(collection.tagline).font(.caption).foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CosmeticLivesView(item: life, maxLives: 3, lives: 3)
                    .accessibilityHidden(true)
            }
            CosmeticTapButtonSkin(item: hero, fallbackColors: fallbackColors, label: "TAP!", height: 56)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            HStack {
                Text(isDefault ? "Free · always yours" : "\(ownedCount)/\(items.count) owned")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                if let quote, !isDefault {
                    bundlePriceLabel(quote)
                }
            }
            HStack(spacing: 8) {
                StudioActionButton(title: "Preview", systemImage: "eye.fill", color: .white, filled: false, expand: true) {
                    previewRequest = CosmeticPreviewRequest(focus: .collection(collection))
                }
                if ownedCount > 0 {
                    StudioActionButton(title: isDefault ? "Equip all" : "Equip all owned",
                                       systemImage: "checkmark.circle.fill", color: StudioStyle.green, expand: true) {
                        if isDefault {
                            items.forEach { economy.equipCosmetic($0) }
                        } else {
                            economy.equipOwnedCosmetics(of: collection)
                        }
                        reload()
                    }
                }
            }
            if let bundle, let quote, !quote.isComplete {
                    if economy.canPurchaseCosmeticBundle(bundle) {
                        StudioActionButton(title: quote.ownedCount > 0
                                               ? "Complete set · \(quote.completionPrice) \u{1FA99}"
                                               : "Unlock bundle · \(quote.completionPrice) \u{1FA99}",
                                           systemImage: "lock.open.fill",
                                           color: spendable >= quote.completionPrice ? StudioStyle.gold : .gray,
                                           expand: true) {
                            flow.requestBundle(bundle, profile: profile, spendable: spendable)
                        }
                        .disabled(flow.isPurchasing)
                        .accessibilityLabel("Unlock \(collection.name) bundle for \(quote.completionPrice) coins")
                    } else {
                        StudioPreviewOnlyLabel()
                    }
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: colors.map { $0.opacity(0.28) } + [Color.white.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(colors.first?.opacity(0.35) ?? StudioStyle.stroke))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(collection.name) collection")
        .accessibilityValue(isDefault ? "Free" : "\(ownedCount) of \(items.count) owned"
                            + (quote.map { $0.isComplete ? ", owned" : ", bundle \($0.completionPrice) coins" } ?? ""))
        .accessibilityIdentifier("studio.collection.\(collection.id)")
    }

    @ViewBuilder
    private func bundlePriceLabel(_ quote: CosmeticBundleQuote) -> some View {
        if quote.isComplete {
            StudioBadge(text: "OWNED", systemImage: "checkmark", color: StudioStyle.green)
        } else {
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(quote.completionPrice) \u{1FA99}")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(StudioStyle.gold)
                if quote.savings > 0 {
                    Text("\(quote.missingListValue) if bought separately")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Item grid

    private var itemGrid: some View {
        let items = filter.items(isOwned: isOwned)
        return Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.title2).foregroundColor(.white.opacity(0.3))
                    Text("Nothing here yet. Preview any item for free in the Preview Studio.")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(items) { itemCard($0) }
                }
            }
        }
    }

    private func itemCard(_ item: CosmeticItem) -> some View {
        let owned = isOwned(item)
        let equipped = isEquipped(item)
        let isSelected = selected?.id == item.id
        let price = ShopItem.cosmeticPrice(item.id)
        let collectionName = CosmeticCatalog.collection(id: item.collectionID)?.name ?? ""
        let status = equipped ? "Equipped" : owned ? (item.isDefault ? "Free" : "Owned") : "\(price) coins"
        let rarity = StudioStyle.rarityColor(item.rarity)

        return Button { selected = item } label: {
            VStack(alignment: .leading, spacing: 6) {
                CosmeticItemArt(item: item, fallbackColors: fallbackColors)
                    .frame(maxWidth: .infinity)
                Text(item.name)
                    .font(.footnote.weight(.bold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(collectionName) · \(item.slot.title)")
                    .font(.caption2).foregroundColor(.white.opacity(0.5))
                    .lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    if equipped {
                        StudioBadge(text: "EQUIPPED", systemImage: "checkmark.circle.fill", color: StudioStyle.green)
                    } else if owned {
                        StudioBadge(text: item.isDefault ? "FREE" : "OWNED", color: .white.opacity(0.6))
                    } else {
                        StudioBadge(text: "\(price) \u{1FA99}", systemImage: "lock.fill",
                                    color: spendable >= price ? StudioStyle.gold : .red.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? rarity.opacity(0.12) : StudioStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? rarity.opacity(0.7) : StudioStyle.stroke, lineWidth: isSelected ? 2 : 1))
        }
        .accessibilityIdentifier("studio.item.\(item.id)")
        .accessibilityLabel("\(item.name), \(collectionName), \(item.slot.title)")
        .accessibilityValue(status)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Action bar (Preview / Buy / Equip)

    private func actionBar(for item: CosmeticItem) -> some View {
        let owned = isOwned(item)
        let equipped = isEquipped(item)
        let price = ShopItem.cosmeticPrice(item.id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.bold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(CosmeticCatalog.collection(id: item.collectionID)?.name ?? "") · \(item.rarity.rawValue.capitalized)")
                    .font(.caption2).foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 4)
            StudioActionButton(title: "Preview", systemImage: "eye.fill", color: .white, filled: false) {
                previewRequest = CosmeticPreviewRequest(focus: .item(item))
            }
            if equipped {
                Label("EQUIPPED", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.black))
                    .foregroundColor(StudioStyle.green)
                    .frame(minHeight: 44)
            } else if owned {
                StudioActionButton(title: "Equip", color: StudioStyle.green) {
                    economy.equipCosmetic(item)
                    reload()
                }
            } else if economy.canPurchaseCosmetic(item) {
                StudioActionButton(title: "Buy \(price) \u{1FA99}",
                                   color: spendable >= price ? StudioStyle.gold : .gray) {
                    flow.requestItem(item, spendable: spendable)
                }
                .disabled(flow.isPurchasing)
                .accessibilityLabel("Buy \(item.name) for \(price) coins")
            } else {
                StudioPreviewOnlyLabel()
            }
        }
    }
}
