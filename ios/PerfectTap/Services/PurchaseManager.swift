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
//   StoreKit on-device JWS verification (.verified only) → bundle / product /
//   product-type / appAccountToken checks → server verification (when the
//   ceiling enables it) → EntitlementLedger (exactly once per transaction ID)
//   → EconomyManager.apply → finish().
//
// finish() runs only after the server acknowledged the transaction (or
// definitively rejected it). A consumable whose server call fails stays
// unfinished and grants nothing; it is retried from Transaction.unfinished
// after an app kill, on foreground and with backoff. A non-consumable is
// granted locally from Apple's signed history while the server is unreachable
// (restore must never be blocked) and finished once the server acknowledges.
//
// Starting a NEW purchase additionally needs the build ceiling and the server
// sales gate (FeatureFlags.swift). Delivery / restore never depend on the gate.

/// Server "sales open" signal (`public.get_iap_sales_status`).
@MainActor
protocol SalesStatusProviding {
    func fetchSalesStatus() async -> ServerSalesStatus?
}

struct SupabaseSalesStatusProvider: SalesStatusProviding {
    func fetchSalesStatus() async -> ServerSalesStatus? {
        guard let service = Backend.shared as? SupabaseService,
              let data = try? await service.client.rpc("get_iap_sales_status").execute().data
        else { return nil }   // unreachable / RPC not deployed ⇒ closed
        return ServerSalesStatus.decode(data)
    }
}

enum StoreEnvironmentResolver {
    /// AppTransaction (signed by Apple) first; the receipt file name is only a
    /// fallback for older OS edge cases. Anything else ⇒ .unknown (Production gate).
    static func resolve() async -> StoreEnvironment {
        if let result = try? await AppTransaction.shared, case .verified(let app) = result {
            switch app.environment {
            case .production: return .production
            case .sandbox:    return .sandbox
            case .xcode:      return .xcode
            default:          return .unknown
            }
        }
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { return .sandbox }
        return .unknown
    }
}

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    @Published private(set) var coinProducts: [Product] = []
    @Published private(set) var specialProducts: [Product] = []
    @Published private(set) var premiumProducts: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var lastCoinPackCreditEvent: CoinPackCreditEvent? = nil
    /// Runtime sales gate (environment + server signal). Published so the shop
    /// re-renders when sales open or close.
    @Published private(set) var salesGate: SalesGate = .closed

    private var transactionListener: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var startedForUserID: String?
    private var resolvedEnvironment: StoreEnvironment?
    private var ledger: EntitlementLedger
    private let defaults: UserDefaults
    var verifier: PurchaseVerifying
    var salesStatusProvider: SalesStatusProviding

    init(defaults: UserDefaults = .standard, verifier: PurchaseVerifying? = nil,
         salesStatusProvider: SalesStatusProviding? = nil) {
        self.defaults = defaults
        self.ledger = EntitlementLedger.load(from: defaults)
        self.verifier = verifier ?? PurchaseManager.defaultVerifier()
        self.salesStatusProvider = salesStatusProvider ?? SupabaseSalesStatusProvider()
    }

    private static func defaultVerifier() -> PurchaseVerifying {
        switch verifierKind(serverVerification: FeatureFlags.serverPurchaseVerification,
                            authoritativeEconomy: FeatureFlags.authoritativeEconomyEnabled,
                            supabaseBackend: Backend.shared is SupabaseService) {
        case .server: return SupabasePurchaseVerifier()
        case .onDevice: return OnDeviceVerifier()
        case .unavailable: return UnavailableVerifier()
        }
    }

    enum VerifierKind: Equatable { case server, onDevice, unavailable }

    /// With the authoritative economy, coins exist only in the server ledger:
    /// a build that cannot verify server side must never finish a coin
    /// transaction (it would be paid and credited nowhere). Fail closed.
    nonisolated static func verifierKind(serverVerification: Bool, authoritativeEconomy: Bool,
                                         supabaseBackend: Bool) -> VerifierKind {
        if serverVerification, supabaseBackend { return .server }
        return authoritativeEconomy ? .unavailable : .onDevice
    }

    deinit {
        transactionListener?.cancel()
        retryTask?.cancel()
    }

    // MARK: - Launch

    /// The Transaction.updates listener attaches at launch, before auth: a
    /// transaction that arrives without a UUID stays unfinished and is picked
    /// up from Transaction.unfinished once Auth has restored/created the
    /// account whose UUID is the appAccountToken.
    func start() async {
        if isUnitTestHostSingleton { return }
        if transactionListener == nil { transactionListener = listenForTransactions() }
        await loadProducts()
        await refreshSalesGate(force: true)
        guard let uid = Backend.shared.currentUID, UUID(uuidString: uid) != nil else {
            return
        }
        guard startedForUserID != uid else {
            return
        }
        startedForUserID = uid
        await processUnfinishedTransactions()
        await reconcileCurrentEntitlements(origin: .transactionListener)
        await reconcileRevocations()
    }

    /// Called when the app returns to the foreground. It retries recoverable
    /// verification failures immediately instead of waiting for another launch.
    func resume() async {
        guard !isUnitTestHostSingleton, Backend.shared.currentUID != nil else { return }
        retryTask?.cancel()
        retryTask = nil
        retryAttempt = 0
        await refreshSalesGate(force: false)
        await processUnfinishedTransactions()
        await reconcileCurrentEntitlements(origin: .transactionListener)
        await reconcileRevocations()
    }

    /// Re-applies Apple-owned non-consumables (Remove Forced Ads, skins) to
    /// the signed-in profile without network or UI. Call after a profile merge
    /// that may have replaced local entitlements with the cloud copy.
    func reconcileOwnedEntitlements() async {
        guard !isUnitTestHostSingleton, Backend.shared.currentUID != nil else { return }
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

    /// In an XCTest host the shared instance never processes StoreKit on its
    /// own; tests drive dedicated instances (isolated ledger, fake verifier).
    private var isUnitTestHostSingleton: Bool { Backend.isRunningUnitTests && self === PurchaseManager.shared }

    // MARK: - Sales gate

    /// Re-reads the server sales signal. Binaries whose ceiling sells nothing
    /// make no call at all (flag-OFF builds keep the 1.1.x network profile).
    /// Any failure closes sales; it never touches delivery or restore.
    func refreshSalesGate(force: Bool) async {
        guard FeatureFlags.anyCategoryWithinCeiling else {
            applyGate(.closed)
            return
        }
        if resolvedEnvironment == nil { resolvedEnvironment = await StoreEnvironmentResolver.resolve() }
        let environment = resolvedEnvironment ?? .unknown
        if environment == .xcode {
            applyGate(SalesGate(environment: .xcode, status: nil))
            return
        }
        if !force, salesGate.environment == environment, salesGate.status?.isFresh() == true { return }
        applyGate(SalesGate(environment: environment, status: await salesStatusProvider.fetchSalesStatus()))
    }

    private func applyGate(_ gate: SalesGate) {
        MonetizationRuntime.shared.update(gate)
        if salesGate != gate { salesGate = gate }
    }

    /// Test seam: install a gate without StoreKit / network.
    func setSalesGateForTesting(_ gate: SalesGate) { applyGate(gate) }

    // MARK: - Purchase

    private func availability(for category: MonetizationCategory, productID: String) async -> MonetizationAvailability {
        await refreshSalesGate(force: false)
        return FeatureFlags.monetizationAvailability(for: category, productID: productID)
    }

    func purchaseCoinPack(_ packID: CoinPackID) async -> CoinPackPurchaseResult {
        guard case .available(let accountToken) = await availability(for: .coins, productID: packID.rawValue) else {
            return .failed(message: availabilityMessage(for: .coins, productID: packID.rawValue))
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
        let id = SpecialProductID.removeAds.rawValue
        guard case .available(let accountToken) = await availability(for: .removeAds, productID: id) else {
            return .failed(message: availabilityMessage(for: .removeAds, productID: id))
        }
        guard let product = specialProducts.first(where: { $0.id == id }) else {
            return .failed(message: "This item is not available right now.")
        }
        return premiumResult(from: await purchase(product, accountToken: accountToken))
    }

    func purchasePremium(_ item: ShopItem) async -> PremiumPurchaseResult {
        guard let id = item.premiumProductID else { return .failed(message: "This item is not available right now.") }
        guard case .available(let accountToken) = await availability(for: .premiumSkins, productID: id) else {
            return .failed(message: availabilityMessage(for: .premiumSkins, productID: id))
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
                case .delivered(let effects), .provisional(let effects):
                    // The background listener may have delivered it first.
                    return .delivered(effects, alreadyDelivered: wasProcessed || effects.isEmpty)
                case .rejected(let reason):   return .failed("The purchase was rejected: \(reason)")
                case .deferred:               return .deferred
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                // Ask to Buy / SCA: nothing is granted now. Approval arrives
                // later through Transaction.updates with the same token.
                return .pending
            @unknown default:
                return .failed("Purchase failed: unknown transaction state")
            }
        } catch {
            return .failed("Purchase failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    /// Re-delivers non-consumables (Remove Forced Ads, premium skins) the Apple
    /// ID owns to whichever account is signed in, guests included. Independent
    /// of the build ceiling and of the server sales gate.
    func restorePurchases() async -> RestorePurchasesResult {
        guard let uid = Backend.shared.currentUID, UUID(uuidString: uid) != nil else {
            return .failed(message: MonetizationBlocker.invalidAccount.message)
        }
        var syncError: Error?
        do {
            try await AppStore.sync()
        } catch {
            // Still honour the signed history already on this device.
            syncError = error
        }
        var restored = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            switch await deliver(transaction, jws: result.jwsRepresentation, origin: .restore) {
            case .delivered, .provisional: restored += 1
            case .rejected, .deferred: break
            }
        }
        if restored > 0 { return .restored(restored) }
        if let syncError { return .failed(message: "Restore failed: \(syncError.localizedDescription)") }
        return .nothingToRestore
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

    /// Refunds / revocations that happened while the app was not running and
    /// were never seen through Transaction.updates (non-consumables only:
    /// finished consumables are not in Transaction.all).
    private func reconcileRevocations() async {
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.revocationDate != nil,
                  ledger.hasProcessed(transaction.id) else { continue }
            _ = await deliver(transaction, jws: result.jwsRepresentation, origin: .transactionListener)
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
        /// Applied (or already applied) and acknowledged: finish().
        case delivered([EntitlementEffect])
        /// Non-consumable granted from Apple's signed history while the server
        /// is unreachable: keep unfinished, retry the acknowledgement.
        case provisional([EntitlementEffect])
        /// Definitive rejection: finish() without a grant.
        case rejected(String)
        /// Nothing granted: keep unfinished and retry.
        case deferred
    }

    enum TransactionCheck: Equatable {
        case accept(PurchaseProductKind)
        /// Not for this app / catalog / type: never grant, never finish.
        case ignore
        /// Consumable bound to another (or no) account: never credit here,
        /// keep unfinished for the account that bought it.
        case accountMismatch
    }

    /// Pure gate applied to every verified transaction before anything else.
    nonisolated static func check(productID: String, bundleID: String, expectedBundleID: String?,
                                  isConsumableType: Bool, appAccountToken: UUID?,
                                  currentAccount: UUID) -> TransactionCheck {
        guard let expectedBundleID, bundleID == expectedBundleID else { return .ignore }
        guard let kind = PurchaseProductKind.kind(for: productID) else { return .ignore }
        guard kind.isConsumable == isConsumableType else { return .ignore }
        if kind.isConsumable, appAccountToken != currentAccount { return .accountMismatch }
        return .accept(kind)
    }

    private enum Origin { case purchaseFlow, transactionListener, restore }

    private func deliver(_ transaction: Transaction, jws: String, origin: Origin) async -> DeliveryOutcome {
        guard let uid = Backend.shared.currentUID,
              let currentAccount = UUID(uuidString: uid) else {
            return .deferred
        }
        let check = Self.check(productID: transaction.productID, bundleID: transaction.appBundleID,
                               expectedBundleID: Bundle.main.bundleIdentifier,
                               isConsumableType: transaction.productType == .consumable,
                               appAccountToken: transaction.appAccountToken, currentAccount: currentAccount)
        guard case .accept = check else {
            // Unknown product: a corrected release can still recover it.
            // Wrong account: Transaction.unfinished re-delivers it when the
            // permanent account that bought it signs in (start() re-runs on
            // every UID change). No retry loop in between, never finished here.
            return .deferred
        }
        let event = PurchaseEvent(transactionID: transaction.id, productID: transaction.productID,
                                  isRevoked: transaction.revocationDate != nil,
                                  appAccountToken: transaction.appAccountToken,
                                  signedDate: transaction.signedDate)
        let outcome = await deliver(event, jws: jws, reapplyOwned: origin != .purchaseFlow)
        switch outcome {
        case .delivered, .rejected:
            await transaction.finish()
        case .provisional, .deferred:
            scheduleRetry()
        }
        if case .delivered(let effects) = outcome {
            for case .creditCoins(let coins) in effects {
                lastCoinPackCreditEvent = CoinPackCreditEvent(productID: event.productID, coins: coins,
                                                              origin: creditOrigin(origin))
            }
        }
        return outcome
    }

    /// StoreKit-free core of the pipeline (unit-tested with a fake verifier).
    /// `reapplyOwned`: re-grant an already-recorded active non-consumable to
    /// the current account (restore / launch reconcile), idempotently.
    func deliver(_ event: PurchaseEvent, jws: String, reapplyOwned: Bool = false) async -> DeliveryOutcome {
        guard let kind = PurchaseProductKind.kind(for: event.productID) else { return .deferred }
        // Effects are applied to the signed-in profile: if the account
        // changes while the server verifies, apply nothing (StoreKit
        // re-delivers the unfinished transaction to the right account).
        let accountAtStart = Backend.shared.currentUID
        func accountChanged() -> Bool { Backend.shared.currentUID != accountAtStart }

        // Refunds and refund reversals are Apple-signed state changes, applied
        // without asking the server (it learns them from App Store Server
        // Notifications V2) so a reversal is never blocked by an outage.
        if event.isRevoked || ledger.isReinstatement(event) {
            return .delivered(commit(ledger.process(event)))
        }

        if ledger.isLegacyNonConsumable(event) {
            _ = commit(ledger.process(event))   // upgrade only, no second grant
        }
        if ledger.hasProcessed(event.transactionID) {
            if ledger.needsServerAcknowledgement(event.transactionID) {
                let verification = await verifier.verify(jws: jws)
                if accountChanged() { return .deferred }
                switch verification {
                case .verified:
                    ledger.markServerAcknowledged(event.transactionID)
                case .rejected(let reason):
                    _ = commit(ledger.rejectProvisional(event.transactionID))
                    return .rejected(reason)
                case .unavailable:
                    return .provisional(commit(reapplyOwned ? ownedEffects(for: event) : []))
                }
            }
            return .delivered(commit(reapplyOwned ? ownedEffects(for: event) : []))
        }

        let verification = await verifier.verify(jws: jws)
        if accountChanged() { return .deferred }
        switch verification {
        case .verified:
            return .delivered(commit(ledger.process(event)))
        case .rejected(let reason):
            return .rejected(reason)
        case .unavailable:
            // Coins: no credit, no finish, retry. Non-consumables: Apple's
            // signed history is enough to unlock on this device now.
            guard !kind.isConsumable else { return .deferred }
            return .provisional(commit(ledger.process(event, serverAcknowledged: false)))
        }
    }

    private func commit(_ effects: [EntitlementEffect]) -> [EntitlementEffect] {
        ledger.save(to: defaults)
        effects.forEach(EconomyManager.shared.apply)
        return effects
    }

    /// Restore effects the current profile is actually missing.
    private func ownedEffects(for event: PurchaseEvent) -> [EntitlementEffect] {
        ledger.restoreEffects(for: event).filter { effect in
            switch effect {
            case .grantNoAds:        return !EconomyManager.shared.hasNoAds
            case .grantItem(let id): return !EconomyManager.shared.ownsItem(id)
            default:                 return true
            }
        }
    }

    /// StoreKitTest entry point: the exact listener / restore path, minus the
    /// AsyncSequence. Unverified results are ignored, as in production.
    func handleForTesting(_ result: VerificationResult<Transaction>, restore: Bool = false) async -> DeliveryOutcome? {
        guard case .verified(let transaction) = result else { return nil }
        return await deliver(transaction, jws: result.jwsRepresentation, origin: restore ? .restore : .transactionListener)
    }

    /// Read-only view for tests and diagnostics.
    var ledgerSnapshot: EntitlementLedger { ledger }

    /// Tests switch the backoff timer off to stay deterministic.
    var automaticRetryEnabled = true

    private func scheduleRetry() {
        guard automaticRetryEnabled, retryTask == nil else { return }
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

    private func availabilityMessage(for category: MonetizationCategory, productID: String) -> String {
        if case .blocked(let blocker) = FeatureFlags.monetizationAvailability(for: category, productID: productID) {
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

/// Fail-closed verifier: coins are never finished, non-consumables unlock
/// provisionally from Apple's signed history (see `verifierKind`).
struct UnavailableVerifier: PurchaseVerifying {
    func verify(jws: String) async -> PurchaseVerification { .unavailable }
}

/// Production verifier (enabled by FeatureFlags.serverPurchaseVerification).
struct SupabasePurchaseVerifier: PurchaseVerifying {
    func verify(jws: String) async -> PurchaseVerification {
        guard let service = Backend.shared as? SupabaseService else { return .unavailable }
        return await service.verifyPurchase(jws: jws)
    }
}
