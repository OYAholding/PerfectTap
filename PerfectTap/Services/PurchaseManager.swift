import Foundation
import StoreKit

// MARK: - Product Definitions
//
// These product IDs must match what you configure in App Store Connect.
// Until you create them there, StoreKit will return empty products.
//
// To test locally: create a StoreKit Configuration file in Xcode
// (File → New → StoreKit Configuration File) and add these products.

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

    var bonusLabel: String? {
        switch self {
        case .small:  return nil
        case .medium: return "+20% BONUS"
        case .large:  return "+50% BONUS"
        case .mega:   return "BEST VALUE"
        }
    }
}

enum SpecialProductID: String, CaseIterable {
    case removeAds = "com.perfecttap.removeads"

    var displayName: String {
        switch self {
        case .removeAds: return "Remove Ads Forever"
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

// MARK: - PurchaseManager (StoreKit 2)

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // All available products fetched from App Store
    @Published private(set) var coinProducts: [Product] = []
    @Published private(set) var specialProducts: [Product] = []
    @Published private(set) var purchaseInProgress: Bool = false
    @Published private(set) var lastError: String? = nil
    @Published private(set) var lastCoinPackCreditEvent: CoinPackCreditEvent? = nil

    private var transactionListener: Task<Void, Error>?
    private let processedTransactionIDsKey = "perfecttap_processed_iap_transaction_ids"

    private init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Fetch Products

    /// Call on app launch to load available products from App Store Connect.
    func loadProducts() async {
        let allIDs = CoinPackID.allCases.map(\.rawValue) + SpecialProductID.allCases.map(\.rawValue)
        do {
            let products = try await Product.products(for: Set(allIDs))
            coinProducts = products
                .filter { p in CoinPackID.allCases.map(\.rawValue).contains(p.id) }
                .sorted { $0.price < $1.price }
            specialProducts = products
                .filter { p in SpecialProductID.allCases.map(\.rawValue).contains(p.id) }
        } catch {
            lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    /// Purchase a coin pack.
    /// - Returns: explicit purchase state + credited coins when completed.
    func purchaseCoinPack(_ packID: CoinPackID) async -> CoinPackPurchaseResult {
        guard let product = coinProducts.first(where: { $0.id == packID.rawValue }) else {
            let message = "Product not found"
            lastError = message
            return .failed(message: message)
        }
        let outcome = await purchase(product)
        switch outcome {
        case .verified(let transaction):
            let applyResult = applyTransactionEntitlementsIfNeeded(transaction, origin: .purchaseFlow)
            await transaction.finish()
            if let credited = applyResult.coinsCredited, credited > 0 {
                let delivery: CoinPackPurchaseDelivery = applyResult.status == .appliedNow
                    ? .creditedNow
                    : .alreadyCredited
                return .success(creditedCoins: credited, delivery: delivery)
            }
            if let mapped = coinAmount(for: transaction.productID), mapped > 0 {
                return .success(creditedCoins: mapped, delivery: .alreadyCredited)
            }
            let message = "Purchase completed, but coin credit mapping is missing."
            lastError = message
            return .failed(message: message)
        case .pending:
            lastError = "Purchase pending approval"
            return .pending
        case .cancelled:
            return .cancelled
        case .failed(let message):
            lastError = message
            return .failed(message: message)
        }
    }

    /// Purchase the remove-ads product. Returns true on success.
    func purchaseRemoveAds() async -> Bool {
        guard let product = specialProducts.first(where: { $0.id == SpecialProductID.removeAds.rawValue }) else {
            lastError = "Product not found"
            return false
        }
        let outcome = await purchase(product)
        switch outcome {
        case .verified(let transaction):
            _ = applyTransactionEntitlementsIfNeeded(transaction, origin: .purchaseFlow)
            await transaction.finish()
            return true
        case .pending:
            lastError = "Purchase pending approval"
            return false
        case .cancelled:
            return false
        case .failed(let message):
            lastError = message
            return false
        }
    }

    private enum PurchaseOutcome {
        case verified(Transaction)
        case pending
        case cancelled
        case failed(String)
    }

    private enum EntitlementOrigin {
        case purchaseFlow
        case transactionListener
        case restore
    }

    private enum EntitlementApplyStatus {
        case appliedNow
        case alreadyApplied
        case notApplicable
    }

    private struct EntitlementApplyResult {
        let status: EntitlementApplyStatus
        let coinsCredited: Int?
    }

    private func purchase(_ product: Product) async -> PurchaseOutcome {
        purchaseInProgress = true
        lastError = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                return .verified(transaction)
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

    // MARK: - Restore Purchases

    func restorePurchases() async {
        // Iterate through all current entitlements
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            _ = applyTransactionEntitlementsIfNeeded(transaction, origin: .restore)
            await transaction.finish()
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                let transaction: Transaction
                switch result {
                case .verified(let t): transaction = t
                case .unverified: continue
                }
                await MainActor.run {
                    _ = self.applyTransactionEntitlementsIfNeeded(transaction, origin: .transactionListener)
                }
                await transaction.finish()
            }
        }
    }

    private func applyTransactionEntitlementsIfNeeded(
        _ transaction: Transaction,
        origin: EntitlementOrigin
    ) -> EntitlementApplyResult {
        let txID = String(transaction.id)
        if hasProcessedTransaction(txID) {
            return EntitlementApplyResult(
                status: .alreadyApplied,
                coinsCredited: coinAmount(for: transaction.productID)
            )
        }

        if transaction.productID == SpecialProductID.removeAds.rawValue {
            EconomyManager.shared.grantNoAds()
            markTransactionProcessed(txID)
            return EntitlementApplyResult(status: .appliedNow, coinsCredited: nil)
        }

        if let coins = coinAmount(for: transaction.productID) {
            EconomyManager.shared.addCoins(coins, source: .purchase)
            markTransactionProcessed(txID)
            lastCoinPackCreditEvent = CoinPackCreditEvent(
                productID: transaction.productID,
                coins: coins,
                origin: creditEventOrigin(for: origin)
            )
            return EntitlementApplyResult(status: .appliedNow, coinsCredited: coins)
        }

        return EntitlementApplyResult(status: .notApplicable, coinsCredited: nil)
    }

    private func creditEventOrigin(for origin: EntitlementOrigin) -> CoinPackCreditEventOrigin {
        switch origin {
        case .purchaseFlow:
            return .purchaseFlow
        case .transactionListener:
            return .transactionListener
        case .restore:
            return .restore
        }
    }

    private func coinAmount(for productID: String) -> Int? {
        CoinPackID(rawValue: productID)?.coinAmount
    }

    private func hasProcessedTransaction(_ transactionID: String) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: processedTransactionIDsKey) ?? []
        return ids.contains(transactionID)
    }

    private func markTransactionProcessed(_ transactionID: String) {
        var ids = UserDefaults.standard.stringArray(forKey: processedTransactionIDsKey) ?? []
        guard !ids.contains(transactionID) else { return }
        ids.append(transactionID)
        if ids.count > 500 {
            ids.removeFirst(ids.count - 500)
        }
        UserDefaults.standard.set(ids, forKey: processedTransactionIDsKey)
    }

    func consumeLastCoinPackCreditEvent() {
        lastCoinPackCreditEvent = nil
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
