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
//  * A refund reversal (same transaction re-signed later without
//    revocationDate) reinstates what the refund removed, exactly once.
//  * A non-consumable may be granted before the server acknowledged it (server
//    unreachable); it stays flagged until acknowledged. Coins never are.

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

    var isConsumable: Bool {
        if case .coins = self { return true }
        return false
    }
}

struct PurchaseEvent: Equatable {
    let transactionID: UInt64
    let productID: String
    let isRevoked: Bool
    let appAccountToken: UUID?
    /// JWS `signedDate`: orders a refund against a later refund reversal.
    let signedDate: Date?

    init(transactionID: UInt64, productID: String, isRevoked: Bool, appAccountToken: UUID? = nil,
         signedDate: Date? = nil) {
        self.transactionID = transactionID
        self.productID = productID
        self.isRevoked = isRevoked
        self.appAccountToken = appAccountToken
        self.signedDate = signedDate
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
        /// Newest Apple `signedDate` applied to this record (refund / reversal ordering).
        var lastSignedDate: Date?
        /// False while a non-consumable is granted locally from Apple's signed
        /// StoreKit history but the server has not acknowledged it yet. Coins
        /// are never recorded unacknowledged.
        var serverAcknowledged: Bool

        init(productID: String, isRevoked: Bool, lastSignedDate: Date? = nil, serverAcknowledged: Bool = true) {
            self.productID = productID
            self.isRevoked = isRevoked
            self.lastSignedDate = lastSignedDate
            self.serverAcknowledged = serverAcknowledged
        }

        // v2 records (1.2.0 candidates) predate the last two fields.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            productID = try c.decode(String.self, forKey: .productID)
            isRevoked = try c.decode(Bool.self, forKey: .isRevoked)
            lastSignedDate = try c.decodeIfPresent(Date.self, forKey: .lastSignedDate)
            serverAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .serverAcknowledged) ?? true
        }
    }

    private(set) var records: [UInt64: Record] = [:]
    /// IDs credited by 1.1.x / ledger v1. Their product was not persisted, so
    /// they remain immutable dedupe markers rather than guessed entitlements.
    private(set) var legacyProcessed: Set<UInt64> = []

    /// Applies a signed StoreKit state exactly once per transaction ID.
    /// `serverAcknowledged: false` is only used for non-consumables delivered
    /// while the server could not be reached (see PurchaseManager).
    mutating func process(_ event: PurchaseEvent, serverAcknowledged: Bool = true) -> [EntitlementEffect] {
        guard let kind = PurchaseProductKind.kind(for: event.productID) else { return [] }
        let id = event.transactionID
        if legacyProcessed.contains(id) { return [] }
        if event.isRevoked {
            guard var record = records[id] else {
                // Refund before delivery: a tombstone blocks a late grant.
                records[id] = Record(productID: event.productID, isRevoked: true, lastSignedDate: event.signedDate)
                return []
            }
            guard !record.isRevoked else { return [] }
            if let applied = record.lastSignedDate, let signed = event.signedDate, signed < applied {
                return []   // stale refund older than an applied reversal
            }
            record.isRevoked = true
            record.lastSignedDate = event.signedDate ?? record.lastSignedDate
            records[id] = record
            return revocationEffects(kind, productID: event.productID)
        }
        if var record = records[id] {
            // Refund reversal (REFUND_REVERSED): Apple re-signs the same
            // transaction without revocationDate and with a newer signedDate.
            // An undated or older non-revoked copy stays blocked by the tombstone.
            guard isReinstatement(event) else { return [] }
            record.isRevoked = false
            record.lastSignedDate = event.signedDate
            let alreadyEntitled = hasActiveGrant(for: event.productID)
            records[id] = record
            return grantEffects(kind, alreadyEntitled: alreadyEntitled)
        }
        let acknowledged: Bool
        if case .coins = kind { acknowledged = true } else { acknowledged = serverAcknowledged }
        let alreadyEntitled = hasActiveGrant(for: event.productID)
        records[id] = Record(productID: event.productID, isRevoked: false, lastSignedDate: event.signedDate,
                             serverAcknowledged: acknowledged)
        return grantEffects(kind, alreadyEntitled: alreadyEntitled)
    }

    /// A non-revoked, newer-signed copy of a transaction this ledger revoked.
    func isReinstatement(_ event: PurchaseEvent) -> Bool {
        guard !event.isRevoked, let record = records[event.transactionID], record.isRevoked,
              let signed = event.signedDate, let revokedAt = record.lastSignedDate else { return false }
        return signed > revokedAt
    }

    func hasProcessed(_ transactionID: UInt64) -> Bool {
        records[transactionID] != nil || legacyProcessed.contains(transactionID)
    }

    func needsServerAcknowledgement(_ transactionID: UInt64) -> Bool {
        guard let record = records[transactionID] else { return false }
        return !record.isRevoked && !record.serverAcknowledged
    }

    mutating func markServerAcknowledged(_ transactionID: UInt64) {
        records[transactionID]?.serverAcknowledged = true
    }

    /// The server definitively rejected a provisionally granted non-consumable:
    /// remove the local grant (fail closed) and keep a tombstone.
    mutating func rejectProvisional(_ transactionID: UInt64) -> [EntitlementEffect] {
        guard var record = records[transactionID], !record.isRevoked, !record.serverAcknowledged,
              let kind = PurchaseProductKind.kind(for: record.productID) else { return [] }
        record.isRevoked = true
        record.serverAcknowledged = true
        records[transactionID] = record
        return revocationEffects(kind, productID: record.productID)
    }

    /// Idempotent re-application of an active non-consumable for whichever
    /// account is signed in now (Restore Purchases / launch reconcile). Coins
    /// are never re-applied: a consumable is credited once, to its own account.
    func restoreEffects(for event: PurchaseEvent) -> [EntitlementEffect] {
        guard !event.isRevoked, let record = records[event.transactionID], !record.isRevoked,
              let kind = PurchaseProductKind.kind(for: event.productID) else { return [] }
        switch kind {
        case .coins:                 return []
        case .removeAds:             return [.grantNoAds]
        case .premiumItem(let item): return [.grantItem(item)]
        }
    }

    private func grantEffects(_ kind: PurchaseProductKind, alreadyEntitled: Bool) -> [EntitlementEffect] {
        switch kind {
        case .coins(let n):          return [.creditCoins(n)]
        case .removeAds:             return alreadyEntitled ? [] : [.grantNoAds]
        case .premiumItem(let item): return alreadyEntitled ? [] : [.grantItem(item)]
        }
    }

    private func revocationEffects(_ kind: PurchaseProductKind, productID: String) -> [EntitlementEffect] {
        switch kind {
        case .coins(let n):          return [.debitCoins(n)]
        case .removeAds:             return hasActiveGrant(for: productID) ? [] : [.revokeNoAds]
        case .premiumItem(let item): return hasActiveGrant(for: productID) ? [] : [.revokeItem(item)]
        }
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
