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
    let appAccountToken: UUID?

    init(transactionID: UInt64, productID: String, isRevoked: Bool, appAccountToken: UUID? = nil) {
        self.transactionID = transactionID
        self.productID = productID
        self.isRevoked = isRevoked
        self.appAccountToken = appAccountToken
    }
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
    struct Record: Codable, Equatable {
        let productID: String
        var isRevoked: Bool
    }

    private(set) var records: [UInt64: Record] = [:]
    /// IDs credited by 1.1.x / ledger v1. Their product was not persisted, so
    /// they remain immutable dedupe markers rather than guessed entitlements.
    private(set) var legacyProcessed: Set<UInt64> = []

    mutating func process(_ event: PurchaseEvent) -> [EntitlementEffect] {
        guard let kind = PurchaseProductKind.kind(for: event.productID) else { return [] }
        let id = event.transactionID
        if legacyProcessed.contains(id) { return [] }
        if event.isRevoked {
            guard var record = records[id] else {
                // Refund before delivery: a tombstone blocks a late grant.
                records[id] = Record(productID: event.productID, isRevoked: true)
                return []
            }
            guard !record.isRevoked else { return [] }
            record.isRevoked = true
            records[id] = record
            switch kind {
            case .coins(let n):          return [.debitCoins(n)]
            case .removeAds:
                return hasActiveGrant(for: event.productID) ? [] : [.revokeNoAds]
            case .premiumItem(let item):
                return hasActiveGrant(for: event.productID) ? [] : [.revokeItem(item)]
            }
        }
        guard records[id] == nil else { return [] }
        let alreadyEntitled = hasActiveGrant(for: event.productID)
        records[id] = Record(productID: event.productID, isRevoked: false)
        switch kind {
        case .coins(let n):          return [.creditCoins(n)]
        case .removeAds:             return alreadyEntitled ? [] : [.grantNoAds]
        case .premiumItem(let item): return alreadyEntitled ? [] : [.grantItem(item)]
        }
    }

    func hasProcessed(_ transactionID: UInt64) -> Bool {
        records[transactionID] != nil || legacyProcessed.contains(transactionID)
    }

    private func hasActiveGrant(for productID: String) -> Bool {
        records.values.contains { $0.productID == productID && !$0.isRevoked }
    }

    // MARK: Persistence

    static let storageKey = "pt_entitlement_ledger_v2"
    static let v1StorageKey = "pt_entitlement_ledger_v1"
    /// Pre-1.2.0 list of credited transaction IDs (strings).
    static let legacyKey = "perfecttap_processed_iap_transaction_ids"

    static func load(from defaults: UserDefaults = .standard) -> EntitlementLedger {
        var ledger = EntitlementLedger()
        if let data = defaults.data(forKey: storageKey),
           let current = try? JSONDecoder().decode(EntitlementLedger.self, from: data) {
            ledger = current
        } else {
            struct V1: Decodable { let granted: Set<UInt64>; let revoked: Set<UInt64> }
            if let data = defaults.data(forKey: v1StorageKey), let old = try? JSONDecoder().decode(V1.self, from: data) {
                ledger.legacyProcessed.formUnion(old.granted)
                ledger.legacyProcessed.formUnion(old.revoked)
            }
        }
        // Keep every transaction 1.1.x already credited, so nothing is credited twice.
        for raw in defaults.stringArray(forKey: legacyKey) ?? [] {
            if let id = UInt64(raw) { ledger.legacyProcessed.insert(id) }
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
