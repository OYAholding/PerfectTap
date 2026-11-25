import Foundation
import StoreKit

// MARK: - Product Definitions
//
// These product IDs must match what you configure in App Store Connect.
// Until you create them there, StoreKit will return empty products.
//
// Local testing: PerfectTap/PerfectTap.storekit lists every product (coin packs,
// Remove Ads, premium skins). Select it in the scheme (Run › Options › StoreKit
// Configuration) to buy with fake money in the simulator.

enum CoinPackID: String, CaseIterable {
    case small  = "com.perfecttap.coins.500"
    case medium = "com.perfecttap.coins.1200"
    case large  = "com.perfecttap.coins.3000"
    case mega   = "com.perfecttap.coins.8000"

    var coinAmount: Int {
        switch self {
        case .small:  return 500
        case .medium: return 1200
        case .large:  return 3000
        case .mega:   return 8000
        }
    }

    var displayName: String {
        switch self {
        case .small:  return "Starter Pack"
        case .medium: return "Popular Pack"
        case .large:  return "Pro Pack"
        case .mega:   return "Mega Pack"
        }
    }

}

enum SpecialProductID: String, CaseIterable {
    case removeAds = "com.perfecttap.removeads"

    var displayName: String {
        switch self {
        case .removeAds: return "Remove Forced Ads"
        }
    }
}

enum CoinPackPurchaseDelivery: Equatable {
    case creditedNow
    case alreadyCredited
}

enum CoinPackCreditEventOrigin: Equatable {
    case purchaseFlow
    case transactionListener
    case restore
}

struct CoinPackCreditEvent: Equatable {
    let productID: String
    let coins: Int
    let origin: CoinPackCreditEventOrigin
}

enum CoinPackPurchaseResult: Equatable {
    case success(creditedCoins: Int, delivery: CoinPackPurchaseDelivery)
    case pending
    case cancelled
    case failed(message: String)
}

// MARK: - Premium purchase result

enum PremiumPurchaseResult: Equatable {
    case success
    case pending
    case cancelled
    /// Paid, but the server could not be reached: delivered automatically later.
    case deferred
    case failed(message: String)
}

enum RestorePurchasesResult: Equatable {
    case restored(Int)
    case nothingToRestore
    case failed(message: String)
}

// MARK: - PurchaseManager (StoreKit 2)
//
// Delivery pipeline for every transaction, whatever its source (purchase
// flow, Transaction.updates, Transaction.unfinished at launch, restore):
//   StoreKit on-device verification → server verification (when enabled) →
//   EntitlementLedger (exactly once per transaction ID) → finish().
// A transaction is finished only after it was delivered or rejected, so a
// crash / network loss in between is retried from Transaction.unfinished.

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    @Published private(set) var coinProducts: [Product] = []
    @Published private(set) var specialProducts: [Product] = []
    @Published private(set) var premiumProducts: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var lastCoinPackCreditEvent: CoinPackCreditEvent? = nil

    private var transactionListener: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var startedForUserID: String?
    private var ledger: EntitlementLedger
    private let defaults: UserDefaults
    var verifier: PurchaseVerifying

    init(defaults: UserDefaults = .standard, verifier: PurchaseVerifying? = nil) {
        self.defaults = defaults
        self.ledger = EntitlementLedger.load(from: defaults)
        self.verifier = verifier ?? PurchaseManager.defaultVerifier()
    }

    private static func defaultVerifier() -> PurchaseVerifying {
        if FeatureFlags.serverPurchaseVerification, Backend.shared is SupabaseService {
            return SupabasePurchaseVerifier()
        }
        return OnDeviceVerifier()
    }

    deinit {
        transactionListener?.cancel()
        retryTask?.cancel()
    }

    // MARK: - Launch

    /// Product discovery is safe before authentication. Transaction handling
    /// starts only after Auth has restored/created the UUID used to bind every
    /// new purchase to its player account.
    func start() async {
        await loadProducts()
        guard let uid = Backend.shared.currentUID, UUID(uuidString: uid) != nil else {
            return
        }
        if transactionListener == nil { transactionListener = listenForTransactions() }
        guard startedForUserID != uid else {
            return
        }
        startedForUserID = uid
        await processUnfinishedTransactions()
        await reconcileCurrentEntitlements(origin: .transactionListener)
    }

    /// Called when the app returns to the foreground. It retries recoverable
    /// verification failures immediately instead of waiting for another launch.
    func resume() async {
        guard Backend.shared.currentUID != nil else { return }
        retryTask?.cancel()
        retryTask = nil
        retryAttempt = 0
        await processUnfinishedTransactions()
        await reconcileCurrentEntitlements(origin: .transactionListener)
    }

    /// Kept for existing callers.
    func loadProducts() async {
        let coinIDs = CoinPackID.allCases.map(\.rawValue)
        let specialIDs = SpecialProductID.allCases.map(\.rawValue)
        let premiumIDs = ShopItem.premiumProductIDs
        do {
            let products = try await Product.products(for: Set(coinIDs + specialIDs + premiumIDs))
            coinProducts = products.filter { coinIDs.contains($0.id) }.sorted { $0.price < $1.price }
            specialProducts = products.filter { specialIDs.contains($0.id) }
            premiumProducts = products.filter { premiumIDs.contains($0.id) }
            lastError = nil
        } catch {
            lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func product(for item: ShopItem) -> Product? {
        guard let id = item.premiumProductID else { return nil }
        return premiumProducts.first { $0.id == id }
    }

    // MARK: - Purchase

    func purchaseCoinPack(_ packID: CoinPackID) async -> CoinPackPurchaseResult {
        guard case .available(let accountToken) = FeatureFlags.monetizationAvailability(for: .coins) else {
            return .failed(message: availabilityMessage(for: .coins))
        }
        guard let product = coinProducts.first(where: { $0.id == packID.rawValue }) else {
            lastError = "Product not found"
            return .failed(message: "Product not found")
        }
        switch await purchase(product, accountToken: accountToken) {
        case .delivered(let effects, let alreadyDelivered):
            let credited = effects.reduce(0) { if case .creditCoins(let n) = $1 { return $0 + n } else { return $0 } }
            if credited > 0 { return .success(creditedCoins: credited, delivery: .creditedNow) }
            if alreadyDelivered { return .success(creditedCoins: packID.coinAmount, delivery: .alreadyCredited) }
            return .failed(message: "Purchase completed, but no coins were credited.")
        case .deferred:
            return .pending
        case .pending:   return .pending
        case .cancelled: return .cancelled
        case .failed(let message):
            lastError = message
            return .failed(message: message)
        }
    }

    func purchaseRemoveAds() async -> PremiumPurchaseResult {
        guard case .available(let accountToken) = FeatureFlags.monetizationAvailability(for: .removeAds) else {
            return .failed(message: availabilityMessage(for: .removeAds))
        }
        guard let product = specialProducts.first(where: { $0.id == SpecialProductID.removeAds.rawValue }) else {
            return .failed(message: "This item is not available right now.")
        }
        return premiumResult(from: await purchase(product, accountToken: accountToken))
    }

    func purchasePremium(_ item: ShopItem) async -> PremiumPurchaseResult {
        guard case .available(let accountToken) = FeatureFlags.monetizationAvailability(for: .premiumSkins) else {
            return .failed(message: availabilityMessage(for: .premiumSkins))
        }
        guard let product = product(for: item) else { return .failed(message: "This item is not available right now.") }
        return premiumResult(from: await purchase(product, accountToken: accountToken))
    }

    private func premiumResult(from outcome: PurchaseFlowOutcome) -> PremiumPurchaseResult {
        switch outcome {
        case .delivered:           return .success
        case .deferred:            return .deferred
        case .pending:             return .pending
        case .cancelled:           return .cancelled
        case .failed(let message): return .failed(message: message)
        }
    }

    private enum PurchaseFlowOutcome {
        case delivered([EntitlementEffect], alreadyDelivered: Bool)
        case deferred
        case pending
        case cancelled
        case failed(String)
    }

    private func purchase(_ product: Product, accountToken: UUID) async -> PurchaseFlowOutcome {
        purchaseInProgress = true
        lastError = nil
        defer { purchaseInProgress = false }

        let options: Set<Product.PurchaseOption> = [.appAccountToken(accountToken)]
        do {
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The purchase could not be verified.")
                }
                let wasProcessed = ledger.hasProcessed(transaction.id)
                switch await deliver(transaction, jws: verification.jwsRepresentation, origin: .purchaseFlow) {
                case .delivered(let effects):
                    // The background listener may have delivered it first.
                    return .delivered(effects, alreadyDelivered: wasProcessed || effects.isEmpty)
                case .rejected(let reason):   return .failed("The purchase was rejected: \(reason)")
                case .deferred:               return .deferred
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Purchase failed: unknown transaction state")
            }
        } catch {
            return .failed("Purchase failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    /// Re-delivers non-consumables (Remove Ads, premium skins) the Apple ID owns.
    func restorePurchases() async -> RestorePurchasesResult {
        guard let uid = Backend.shared.currentUID, UUID(uuidString: uid) != nil else {
            return .failed(message: MonetizationBlocker.invalidAccount.message)
        }
        do {
            try await AppStore.sync()
        } catch {
            return .failed(message: "Restore failed: \(error.localizedDescription)")
        }
        var delivered = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if case .delivered = await deliver(transaction, jws: result.jwsRepresentation, origin: .restore) {
                delivered += 1
            }
        }
        return delivered > 0 ? .restored(delivered) : .nothingToRestore
    }

    // MARK: - Background sources

    private func processUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            _ = await deliver(transaction, jws: result.jwsRepresentation, origin: .transactionListener)
        }
    }

    private func reconcileCurrentEntitlements(origin: Origin) async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            _ = await deliver(transaction, jws: result.jwsRepresentation, origin: origin)
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                _ = await self?.deliver(transaction, jws: result.jwsRepresentation, origin: .transactionListener)
            }
        }
    }

    // MARK: - Delivery

    enum DeliveryOutcome: Equatable {
        case delivered([EntitlementEffect])
        case rejected(String)
        case deferred
    }

    private enum Origin { case purchaseFlow, transactionListener, restore }

    private func deliver(_ transaction: Transaction, jws: String, origin: Origin) async -> DeliveryOutcome {
        guard let uid = Backend.shared.currentUID,
              let expectedToken = UUID(uuidString: uid) else {
            return .deferred
        }
        guard let kind = PurchaseProductKind.kind(for: transaction.productID) else {
            // A verified transaction can outlive the catalog bundled with this
            // build. Never grant it, but keep it unfinished so a corrected
            // release can recover it instead of silently discarding ownership.
            scheduleRetry()
            return .deferred
        }
        if case .coins = kind, transaction.appAccountToken != expectedToken {
            // Consumables are not in currentEntitlements. Keep the transaction
            // unfinished until the permanent account that bought it signs in.
            scheduleRetry()
            return .deferred
        }
        let event = PurchaseEvent(transactionID: transaction.id, productID: transaction.productID,
                                  isRevoked: transaction.revocationDate != nil,
                                  appAccountToken: transaction.appAccountToken)
        let outcome = await deliver(event, jws: jws)
        if outcome != .deferred { await transaction.finish() }
        if outcome == .deferred { scheduleRetry() }
        if case .delivered(let effects) = outcome {
            for case .creditCoins(let coins) in effects {
                lastCoinPackCreditEvent = CoinPackCreditEvent(productID: event.productID, coins: coins,
                                                              origin: creditOrigin(origin))
            }
        }
        return outcome
    }

    /// StoreKit-free core of the pipeline (unit-tested with a fake verifier).
    func deliver(_ event: PurchaseEvent, jws: String) async -> DeliveryOutcome {
        // Refunds are applied without asking the server: the server learns
        // about them from App Store Server Notifications V2.
        if !event.isRevoked, !ledger.hasProcessed(event.transactionID) {
            switch await verifier.verify(jws: jws) {
            case .verified: break
            case .rejected(let reason): return .rejected(reason)
            case .unavailable: return .deferred
            }
        }
        let effects = ledger.process(event)
        ledger.save(to: defaults)
        effects.forEach(EconomyManager.shared.apply)
        return .delivered(effects)
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        let delays: [UInt64] = [2, 5, 15, 60, 300]
        let delay = delays[min(retryAttempt, delays.count - 1)]
        retryAttempt = min(retryAttempt + 1, delays.count - 1)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            await self.processUnfinishedTransactions()
        }
    }

    private func availabilityMessage(for category: MonetizationCategory) -> String {
        if case .blocked(let blocker) = FeatureFlags.monetizationAvailability(for: category) {
            return blocker.message
        }
        return "Purchases are not available yet."
    }

    private func creditOrigin(_ origin: Origin) -> CoinPackCreditEventOrigin {
        switch origin {
        case .purchaseFlow:        return .purchaseFlow
        case .transactionListener: return .transactionListener
        case .restore:             return .restore
        }
    }

    func consumeLastCoinPackCreditEvent() {
        lastCoinPackCreditEvent = nil
    }
}

/// Production verifier (enabled by FeatureFlags.serverPurchaseVerification).
struct SupabasePurchaseVerifier: PurchaseVerifying {
    func verify(jws: String) async -> PurchaseVerification {
        guard let service = Backend.shared as? SupabaseService else { return .unavailable }
        return await service.verifyPurchase(jws: jws)
    }
}
