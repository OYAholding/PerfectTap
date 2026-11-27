import SwiftUI

// MARK: - Cosmetic purchase flow (shared by the Studio tab and the Preview Studio)
//
// One confirmed purchase path for every cosmetic: a single item, a collection
// bundle (pro-rated), or the unowned items of a Preview Studio draft.
// Rules: always ask for confirmation with the exact price, never charge a price
// the player did not see (`expectedPrice`), no timers / pressure copy.
// Authoritative economy ON ⇒ nothing here is offered (preview only).

@MainActor
final class CosmeticPurchaseFlow: ObservableObject {

    enum Request: Identifiable, Equatable {
        case item(CosmeticItem, price: Int)
        case bundle(CosmeticBundleQuote, name: String)
        case items([CosmeticItem], price: Int)

        var id: String {
            switch self {
            case .item(let item, _):     return "item.\(item.id)"
            case .bundle(let quote, _):  return "bundle.\(quote.bundleID)"
            case .items(let items, _):   return "items.\(items.map(\.id).joined(separator: ","))"
            }
        }

        var price: Int {
            switch self {
            case .item(_, let price), .items(_, let price): return price
            case .bundle(let quote, _): return quote.completionPrice
            }
        }

        var title: String {
            switch self {
            case .item(let item, let price):
                return "Unlock \(item.name) for \(price) coins?"
            case .bundle(let quote, let name):
                return quote.ownedCount > 0
                    ? "Complete \(name) for \(quote.completionPrice) coins?"
                    : "Unlock \(name) bundle for \(quote.completionPrice) coins?"
            case .items(let items, let price):
                return "Unlock \(items.count) item\(items.count == 1 ? "" : "s") for \(price) coins?"
            }
        }

        var detail: String {
            switch self {
            case .item(let item, _):
                return "\(CosmeticCatalog.collection(id: item.collectionID)?.name ?? "") · \(item.slot.title)"
            case .bundle(let quote, _):
                let missing = quote.missingItemIDs.count
                var text = "Adds the \(missing) item\(missing == 1 ? "" : "s") you don't own yet."
                if quote.ownedCount > 0 { text += " Items you already own are not charged again." }
                if quote.savings > 0 { text += " Saves \(quote.savings) coins versus buying them one by one." }
                return text
            case .items(let items, _):
                return items.map(\.name).joined(separator: ", ")
            }
        }
    }

    @Published var pending: Request?
    @Published var message: String?
    /// Ids granted by the last successful multi-item purchase (offer "Equip now").
    @Published private(set) var lastGranted: [String] = []
    @Published private(set) var isPurchasing = false

    private let economy: EconomyManager
    /// Called after any state change the host should re-read (profile, loadout).
    var onChange: () -> Void = {}

    init(economy: EconomyManager = .shared) {
        self.economy = economy
    }

    var purchasesAvailable: Bool { economy.cosmeticPurchasesAvailable }

    // MARK: Requests (ask for confirmation; never charge here)

    func requestItem(_ item: CosmeticItem, spendable: Int) {
        guard economy.canPurchaseCosmetic(item) else { return showPreviewOnly() }
        let price = ShopItem.cosmeticPrice(item.id)
        guard ensureAffordable(price, spendable: spendable) else { return }
        pending = .item(item, price: price)
    }

    func requestBundle(_ bundle: CosmeticBundle, profile: PlayerProfile, spendable: Int) {
        guard economy.canPurchaseCosmeticBundle(bundle) else { return showPreviewOnly() }
        let quote = economy.bundleQuote(bundle, in: profile)
        guard !quote.isComplete else {
            message = "You already own every item in this collection."
            return
        }
        guard ensureAffordable(quote.completionPrice, spendable: spendable) else { return }
        let name = CosmeticCatalog.collection(id: bundle.collectionID)?.name ?? "Collection"
        pending = .bundle(quote, name: name)
    }

    func requestItems(_ items: [CosmeticItem], profile: PlayerProfile, spendable: Int) {
        let unowned = items.filter { !economy.isCosmeticOwned($0, in: profile) }
        guard !unowned.isEmpty else { return }
        guard unowned.allSatisfy(economy.canPurchaseCosmetic) else { return showPreviewOnly() }
        if unowned.count == 1, let only = unowned.first { return requestItem(only, spendable: spendable) }
        // Never charge more than the bundle rate for a whole missing set.
        if let (bundle, _) = economy.cheaperBundle(for: unowned, in: profile) {
            return requestBundle(bundle, profile: profile, spendable: spendable)
        }
        let price = economy.cosmeticItemsPrice(unowned, in: profile)
        guard ensureAffordable(price, spendable: spendable) else { return }
        pending = .items(unowned, price: price)
    }

    // MARK: Confirmed purchase

    func confirm(_ request: Request) async {
        pending = nil
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false; onChange() }
        lastGranted = []

        switch request {
        case .item(let item, let price):
            guard let shopItem = ShopItem.cosmetic(item), shopItem.price == price else {
                message = "The price changed. Please check it and try again. Your coins were not changed."
                return
            }
            if await economy.buyItemForCurrentRollout(shopItem) {
                AnalyticsService.logShopItemBought(itemId: item.id, price: price)
                lastGranted = [item.id]
                message = "\(item.name) is yours."
            } else {
                message = "Purchase could not be confirmed. Your coins were not changed."
            }

        case .bundle(let quote, let name):
            guard let bundle = CosmeticCatalog.bundles.first(where: { $0.id == quote.bundleID }) else { return }
            handle(economy.buyCosmeticBundle(bundle, expectedPrice: quote.completionPrice),
                   analyticsID: bundle.id, successName: name)

        case .items(let items, let price):
            handle(economy.buyCosmeticItems(items, expectedPrice: price),
                   analyticsID: "cosmetic_items", successName: "\(items.count) items")
        }
    }

    /// Equip what the last purchase granted (explicit player action).
    func equipLastGranted() {
        for id in lastGranted {
            if let item = CosmeticCatalog.item(id: id) { economy.equipCosmetic(item) }
        }
        lastGranted = []
        onChange()
    }

    func clearGranted() { lastGranted = [] }

    // MARK: Helpers

    private func handle(_ result: EconomyManager.CosmeticPurchaseResult, analyticsID: String, successName: String) {
        switch result {
        case .purchased(let granted, let charged):
            AnalyticsService.logShopItemBought(itemId: analyticsID, price: charged)
            lastGranted = granted
            message = "\(successName) unlocked for \(charged) coins."
        case .alreadyOwned:
            message = "You already own these items. Nothing was charged."
        case .insufficientCoins(let needed):
            message = "Not enough coins. You need \(needed) more."
        case .priceChanged(let current):
            message = "The price is now \(current) coins. Nothing was charged — please confirm again."
        case .unavailable:
            showPreviewOnly()
        case .inProgress:
            message = "Another purchase is still being processed."
        }
    }

    private func ensureAffordable(_ price: Int, spendable: Int) -> Bool {
        guard spendable >= price else {
            message = "Not enough coins. You need \(price - spendable) more."
            return false
        }
        return true
    }

    private func showPreviewOnly() {
        message = "Preview only — these cosmetics are coming soon."
    }
}

// MARK: - Presentation

extension View {
    /// Confirmation dialog + result alert for a `CosmeticPurchaseFlow`.
    func cosmeticPurchaseFlow(_ flow: CosmeticPurchaseFlow) -> some View {
        modifier(CosmeticPurchaseFlowModifier(flow: flow))
    }
}

private struct CosmeticPurchaseFlowModifier: ViewModifier {
    @ObservedObject var flow: CosmeticPurchaseFlow

    func body(content: Content) -> some View {
        content
            .alert(
                flow.pending?.title ?? "",
                isPresented: Binding(get: { flow.pending != nil }, set: { if !$0 { flow.pending = nil } }),
                presenting: flow.pending
            ) { request in
                Button("Unlock for \(request.price) coins") { Task { await flow.confirm(request) } }
                Button("Cancel", role: .cancel) { flow.pending = nil }
            } message: { request in
                Text(request.detail)
            }
            .alert(
                flow.message ?? "",
                isPresented: Binding(get: { flow.message != nil && flow.pending == nil },
                                     set: { if !$0 { flow.message = nil } })
            ) {
                if !flow.lastGranted.isEmpty {
                    Button("Equip now") { flow.equipLastGranted() }
                    Button("Later", role: .cancel) { flow.clearGranted() }
                } else {
                    Button("OK", role: .cancel) {}
                }
            }
    }
}
