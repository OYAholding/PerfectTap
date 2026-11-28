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

// MARK: - Per-render state (QA-17)

/// Plain values a Studio card needs, computed once per render.
struct StudioItemCardState: Equatable {
    let owned: Bool
    let equipped: Bool
    let isDefault: Bool
    let price: Int
    let affordable: Bool

    /// VoiceOver value: Equipped / Owned / Free / "Locked, 300 coins".
    var accessibilityValue: String {
        if equipped { return "Equipped" }
        if owned { return isDefault ? "Free" : "Owned" }
        return "Locked, \(CoinFormat.coins(price))" + (affordable ? "" : ", not enough coins")
    }
}

/// Ownership, equipped state and prices for one Studio render. Built once per
/// `body` from the profile and the stored loadout — one ownership lookup and
/// one price lookup per catalog item, one 9-slot resolve — and then read by
/// every card, instead of each card re-resolving the whole loadout (QA-17).
/// Pure: the lookups are injected, so tests can count them.
struct CosmeticStudioRenderState {
    let ownedIDs: Set<String>
    let equipped: ResolvedCosmetics
    let prices: [String: Int]
    let spendable: Int

    init(items: [CosmeticItem] = CosmeticCatalog.items,
         loadout: CosmeticLoadout,
         spendable: Int,
         isOwned: (String) -> Bool,
         price: (String) -> Int) {
        var owned = Set<String>()
        var prices: [String: Int] = [:]
        for item in items {
            if item.isDefault || isOwned(item.id) { owned.insert(item.id) }
            prices[item.id] = item.isDefault ? 0 : price(item.id)
        }
        self.ownedIDs = owned
        self.prices = prices
        self.spendable = spendable
        // Same rule as EconomyManager.isCosmeticEquipped (stored selection
        // validated against this profile's ownership), resolved once.
        self.equipped = ResolvedCosmetics.resolve(loadout) { owned.contains($0) }
    }

    /// Live state: `EconomyManager.isOwned` and `ShopItem.cosmeticPrice`, once per item.
    static func live(profile: PlayerProfile, loadout: CosmeticLoadout, spendable: Int) -> CosmeticStudioRenderState {
        CosmeticStudioRenderState(loadout: loadout, spendable: spendable,
                                  isOwned: { EconomyManager.isOwned($0, in: profile) },
                                  price: ShopItem.cosmeticPrice)
    }

    func isOwned(_ item: CosmeticItem) -> Bool { item.isDefault || ownedIDs.contains(item.id) }
    func isEquipped(_ item: CosmeticItem) -> Bool { equipped.item(for: item.slot).id == item.id }
    func price(_ item: CosmeticItem) -> Int { prices[item.id] ?? ShopItem.cosmeticPrice(item.id) }

    func card(for item: CosmeticItem) -> StudioItemCardState {
        let price = price(item)
        return StudioItemCardState(owned: isOwned(item), equipped: isEquipped(item), isDefault: item.isDefault,
                                   price: price, affordable: spendable >= price)
    }

    /// Same as `EconomyManager.bundleQuote(_:in:)`, from the precomputed sets.
    func quote(for bundle: CosmeticBundle) -> CosmeticBundleQuote {
        CosmeticBundlePricing.quote(for: bundle, bundlePrice: ShopItem.cosmeticBundlePrice(bundle),
                                    price: { prices[$0] ?? ShopItem.cosmeticPrice($0) },
                                    isOwned: { ownedIDs.contains($0) })
    }
}

/// VoiceOver label of a bundle unlock button:
/// "Unlock bundle, 1,100 coins, 1,620 if bought separately".
func studioBundleAccessibilityLabel(_ quote: CosmeticBundleQuote) -> String {
    var text = (quote.ownedCount > 0 ? "Complete set, " : "Unlock bundle, ") + CoinFormat.coins(quote.completionPrice)
    if quote.savings > 0 { text += ", \(CoinFormat.string(quote.missingListValue)) if bought separately" }
    return text
}

struct CosmeticStudioShopSection: View {
    @Binding var profile: PlayerProfile
    let spendable: Int

    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var loadoutStore = CosmeticLoadoutStore.shared
    @StateObject private var flow = CosmeticPurchaseFlow()
    @State private var filter: CosmeticStudioFilter = .collections
    @State private var selected: CosmeticItem?
    @State private var previewRequest: CosmeticPreviewRequest?

    private var economy: EconomyManager { .shared }
    private var fallbackColors: [Color] { [themeManager.current.barGradient.0, themeManager.current.barGradient.1] }
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        // One ownership / equip / price snapshot per render, shared by every card.
        let state = CosmeticStudioRenderState.live(profile: profile, loadout: loadoutStore.loadout, spendable: spendable)
        return VStack(spacing: 0) {
            filterBar
                .padding(.bottom, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    StudioDebugPriceNote()
                    if !flow.purchasesAvailable { previewOnlyBanner }
                    previewEntry
                    if filter == .collections {
                        ForEach(CosmeticCatalog.collections) { collectionCard($0, state: state) }
                    } else {
                        itemGrid(state: state)
                    }
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            if let item = selected, filter != .collections {
                actionBar(for: item, card: state.card(for: item))
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

    /// Horizontally scrolling chips, ≥ 44 pt tall at every text size (QA-20).
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
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundColor(filter == f ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, isLarge ? 6 : 0)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(filter == f ? StudioStyle.gold : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
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
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(StudioStyle.gold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// Stacks vertically at accessibility sizes so the wand never overlaps the text (QA-20).
    private var previewEntry: some View {
        Button { previewRequest = CosmeticPreviewRequest() } label: {
            Group {
                if isLarge {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            wandIcon
                            Spacer()
                            chevron
                        }
                        previewEntryText
                    }
                } else {
                    HStack(spacing: 10) {
                        wandIcon
                        previewEntryText
                        Spacer(minLength: 4)
                        chevron
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(StudioStyle.purple.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(StudioStyle.purple.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel("Open Preview Studio")
        .accessibilityHint("Mix and match any item and try it before you decide.")
        .accessibilityIdentifier("studio.openPreview")
    }

    private var wandIcon: some View {
        Image(systemName: "wand.and.stars").font(.title3)
            .foregroundColor(StudioStyle.purple)
            .fixedSize()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.3))
    }

    private var previewEntryText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Open Preview Studio").font(.subheadline.weight(.bold)).foregroundColor(.white)
            Text("Mix & match any item and try it before you decide.")
                .font(.caption).foregroundColor(.white.opacity(0.5))
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footnote: some View {
        Text("Cosmetics change how the game looks, sounds and feels — never timing, scoring, lives or speed.")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    // MARK: Collection cards

    private func collectionCard(_ collection: CosmeticCollection, state: CosmeticStudioRenderState) -> some View {
        let isDefault = collection.id == CosmeticCatalog.defaultCollectionID
        let bundle = CosmeticCatalog.bundle(collectionID: collection.id)
        let quote = bundle.map(state.quote(for:))
        let items = collection.itemIDs.compactMap(CosmeticCatalog.item(id:))
        let ownedCount = isDefault ? items.count : (quote?.ownedCount ?? items.filter(state.isOwned).count)
        let hero = CosmeticCatalog.item(id: collection.heroItemID ?? "") ?? CosmeticCatalog.defaultItem(for: .tapButton)
        let life = items.first { $0.slot == .lifeIcon } ?? CosmeticCatalog.defaultItem(for: .lifeIcon)
        let colors = StudioStyle.palette(collection.palette)
        let ownedText = Text(isDefault ? "Free · always yours" : "\(ownedCount)/\(items.count) owned")
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.75))

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
            if isLarge {
                VStack(alignment: .leading, spacing: 4) {
                    ownedText
                    if let quote, !isDefault { bundlePriceLabel(quote, alignment: .leading) }
                }
            } else {
                HStack {
                    ownedText
                    Spacer()
                    if let quote, !isDefault { bundlePriceLabel(quote, alignment: .trailing) }
                }
            }
            collectionActions(collection, isDefault: isDefault, items: items, ownedCount: ownedCount)
            if let bundle, let quote, !quote.isComplete {
                if economy.canPurchaseCosmeticBundle(bundle) {
                    StudioActionButton(title: quote.ownedCount > 0 ? "Complete set" : "Unlock bundle",
                                       systemImage: "lock.open.fill",
                                       color: state.spendable >= quote.completionPrice ? StudioStyle.gold : .gray,
                                       expand: true,
                                       coins: quote.completionPrice) {
                        flow.requestBundle(bundle, profile: profile, spendable: spendable)
                    }
                    .disabled(flow.isPurchasing)
                    .accessibilityLabel(studioBundleAccessibilityLabel(quote))
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
                            + (quote.map { $0.isComplete ? ", owned" : ", bundle \(CoinFormat.coins($0.completionPrice))" } ?? ""))
        .accessibilityIdentifier("studio.collection.\(collection.id)")
    }

    @ViewBuilder
    private func collectionActions(_ collection: CosmeticCollection, isDefault: Bool,
                                   items: [CosmeticItem], ownedCount: Int) -> some View {
        let preview = StudioActionButton(title: "Preview", systemImage: "eye.fill", color: .white,
                                         filled: false, expand: true) {
            previewRequest = CosmeticPreviewRequest(focus: .collection(collection))
        }
        let equip = StudioActionButton(title: isDefault ? "Equip all" : "Equip all owned",
                                       systemImage: "checkmark.circle.fill", color: StudioStyle.green, expand: true) {
            if isDefault {
                items.forEach { economy.equipCosmetic($0) }
            } else {
                economy.equipOwnedCosmetics(of: collection)
            }
            reload()
        }
        if isLarge {
            VStack(spacing: 8) {
                preview
                if ownedCount > 0 { equip }
            }
        } else {
            HStack(spacing: 8) {
                preview
                if ownedCount > 0 { equip }
            }
        }
    }

    @ViewBuilder
    private func bundlePriceLabel(_ quote: CosmeticBundleQuote, alignment: HorizontalAlignment) -> some View {
        if quote.isComplete {
            StudioBadge(text: "OWNED", systemImage: "checkmark", color: StudioStyle.green)
        } else {
            VStack(alignment: alignment, spacing: 1) {
                StudioCoinAmount(amount: quote.completionPrice)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(StudioStyle.gold)
                if quote.savings > 0 {
                    Text("\(CoinFormat.string(quote.missingListValue)) if bought separately")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CoinFormat.coins(quote.completionPrice)
                                + (quote.savings > 0 ? ", \(CoinFormat.string(quote.missingListValue)) if bought separately" : ""))
        }
    }

    // MARK: Item grid

    private func itemGrid(state: CosmeticStudioRenderState) -> some View {
        let items = filter.items(isOwned: state.isOwned)
        // One column at accessibility sizes: two would truncate every name.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: isLarge ? 1 : 2)
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
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        StudioItemCard(item: item,
                                       collectionName: CosmeticCatalog.collection(id: item.collectionID)?.name ?? "",
                                       card: state.card(for: item),
                                       isSelected: selected?.id == item.id,
                                       fallbackColors: fallbackColors) { selected = item }
                    }
                }
            }
        }
    }

    // MARK: Action bar (Preview / Buy / Equip)

    private func actionBar(for item: CosmeticItem, card: StudioItemCardState) -> some View {
        let info = VStack(alignment: .leading, spacing: 2) {
            Text(item.name).font(.subheadline.weight(.bold)).foregroundColor(.white)
                .lineLimit(isLarge ? 2 : 1).minimumScaleFactor(isLarge ? 1 : 0.8)
            Text("\(CosmeticCatalog.collection(id: item.collectionID)?.name ?? "") · \(item.rarity.rawValue.capitalized)")
                .font(.caption2).foregroundColor(.white.opacity(0.45))
        }
        return Group {
            if isLarge {
                VStack(alignment: .leading, spacing: 8) {
                    info
                    actionButtons(for: item, card: card, expand: true)
                }
            } else {
                HStack(spacing: 10) {
                    info
                    Spacer(minLength: 4)
                    actionButtons(for: item, card: card, expand: false)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(for item: CosmeticItem, card: StudioItemCardState, expand: Bool) -> some View {
        StudioActionButton(title: "Preview", systemImage: "eye.fill", color: .white, filled: false, expand: expand) {
            previewRequest = CosmeticPreviewRequest(focus: .item(item))
        }
        if card.equipped {
            Label("EQUIPPED", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.black))
                .foregroundColor(StudioStyle.green)
                .frame(minHeight: 44)
        } else if card.owned {
            StudioActionButton(title: "Equip", color: StudioStyle.green, expand: expand) {
                economy.equipCosmetic(item)
                reload()
            }
        } else if economy.canPurchaseCosmetic(item) {
            StudioActionButton(title: "Buy", color: card.affordable ? StudioStyle.gold : .gray,
                               expand: expand, coins: card.price) {
                flow.requestItem(item, spendable: spendable)
            }
            .disabled(flow.isPurchasing)
            .accessibilityLabel("Buy \(item.name), \(CoinFormat.coins(card.price))")
        } else {
            StudioPreviewOnlyLabel()
        }
    }
}

// MARK: - Item card (plain values only; QA-17)

private struct StudioItemCard: View {
    let item: CosmeticItem
    let collectionName: String
    let card: StudioItemCardState
    let isSelected: Bool
    let fallbackColors: [Color]
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let rarity = StudioStyle.rarityColor(item.rarity)
        let large = dynamicTypeSize.isAccessibilitySize
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                CosmeticItemArt(item: item, fallbackColors: fallbackColors)
                    .frame(maxWidth: .infinity)
                Text(item.name)
                    .font(.footnote.weight(.bold)).foregroundColor(.white)
                    .lineLimit(large ? 3 : 1).minimumScaleFactor(large ? 1 : 0.8)
                Text("\(collectionName) · \(item.slot.title)")
                    .font(.caption2).foregroundColor(.white.opacity(0.5))
                    .lineLimit(large ? 3 : 1).minimumScaleFactor(large ? 1 : 0.8)
                HStack(spacing: 4) {
                    if card.equipped {
                        StudioBadge(text: "EQUIPPED", systemImage: "checkmark.circle.fill", color: StudioStyle.green)
                    } else if card.owned {
                        StudioBadge(text: card.isDefault ? "FREE" : "OWNED", color: .white.opacity(0.6))
                    } else {
                        StudioBadge(text: "", systemImage: "lock.fill",
                                    color: card.affordable ? StudioStyle.gold : .red.opacity(0.7),
                                    coins: card.price)
                    }
                    Spacer(minLength: 0)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(isSelected ? rarity.opacity(0.12) : StudioStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? rarity.opacity(0.7) : StudioStyle.stroke, lineWidth: isSelected ? 2 : 1))
        }
        .accessibilityIdentifier("studio.item.\(item.id)")
        .accessibilityLabel("\(item.name), \(collectionName), \(item.slot.title)")
        .accessibilityValue(card.accessibilityValue)
        .accessibilityHint("Shows preview and unlock options")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
