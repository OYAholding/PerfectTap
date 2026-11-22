import Foundation

// MARK: - Entitlement ledger (pure, unit-tested)
//
// Decides what a StoreKit transaction changes in the player's economy, exactly
// once per transaction ID. The same rules run on the server
// (supabase/functions/verify-purchase + private.purchase_ledger), which is the
// authority once server verification is enabled; this client copy keeps the
// device consistent and offline-safe.
//
// Rules:
//  * A purchase is applied once (duplicate deliveries: listener + purchase flow
//    + restore + Transaction.unfinished → one grant).
//  * A revoked (refunded / Family-Sharing-removed) transaction removes what it
//    granted. Coins are debited down to a floor of 0 (never negative).
//  * A revocation that arrives before its purchase blocks the later grant.

enum PurchaseProductKind: Equatable {
    case coins(Int)
    case removeAds
    case premiumItem(String)

    static func kind(for productID: String) -> PurchaseProductKind? {
        if let pack = CoinPackID(rawValue: productID) { return .coins(pack.coinAmount) }
        if productID == SpecialProductID.removeAds.rawValue { return .removeAds }
        if let item = ShopItem.item(productID: productID) { return .premiumItem(item.id) }
        return nil
    }
}

struct PurchaseEvent: Equatable {
    let transactionID: UInt64
    let productID: String
    let isRevoked: Bool
}

enum EntitlementEffect: Equatable {
    case creditCoins(Int)
    case debitCoins(Int)
    case grantNoAds
    case revokeNoAds
    case grantItem(String)
    case revokeItem(String)
}

struct EntitlementLedger: Codable, Equatable {
    private(set) var granted: Set<UInt64> = []
    private(set) var revoked: Set<UInt64> = []

    mutating func process(_ event: PurchaseEvent) -> [EntitlementEffect] {
        guard let kind = PurchaseProductKind.kind(for: event.productID) else { return [] }
        let id = event.transactionID
        if event.isRevoked {
            guard !revoked.contains(id) else { return [] }
            revoked.insert(id)
            // Never granted: just block a late grant.
            guard granted.contains(id) else { granted.insert(id); return [] }
            switch kind {
            case .coins(let n):          return [.debitCoins(n)]
            case .removeAds:             return [.revokeNoAds]
            case .premiumItem(let item): return [.revokeItem(item)]
            }
        }
        guard !granted.contains(id) else { return [] }
        granted.insert(id)
        switch kind {
        case .coins(let n):          return [.creditCoins(n)]
        case .removeAds:             return [.grantNoAds]
        case .premiumItem(let item): return [.grantItem(item)]
        }
    }

    func hasProcessed(_ transactionID: UInt64) -> Bool { granted.contains(transactionID) }

    // MARK: Persistence

    static let storageKey = "pt_entitlement_ledger_v1"
    /// Pre-1.2.0 list of credited transaction IDs (strings).
    static let legacyKey = "perfecttap_processed_iap_transaction_ids"

    static func load(from defaults: UserDefaults = .standard) -> EntitlementLedger {
        var ledger = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(EntitlementLedger.self, from: $0) } ?? EntitlementLedger()
        // Keep every transaction 1.1.x already credited, so nothing is credited twice.
        for raw in defaults.stringArray(forKey: legacyKey) ?? [] {
            if let id = UInt64(raw) { ledger.granted.insert(id) }
        }
        return ledger
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

// MARK: - Server verification seam

enum PurchaseVerification: Equatable {
    /// Server accepted the signed transaction (and granted it in its ledger).
    case verified
    /// Signature / bundle / environment invalid: never grant.
    case rejected(String)
    /// Server not reachable: keep the transaction unfinished and retry later.
    case unavailable
}

@MainActor
protocol PurchaseVerifying {
    func verify(jws: String) async -> PurchaseVerification
}

/// Used while server verification is not deployed: StoreKit has already
/// verified the JWS signature on device (`VerificationResult.verified`).
struct OnDeviceVerifier: PurchaseVerifying {
    func verify(jws: String) async -> PurchaseVerification { .verified }
}
