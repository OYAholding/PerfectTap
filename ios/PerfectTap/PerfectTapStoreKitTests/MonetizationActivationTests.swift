import XCTest
@testable import PerfectTap

/// Fail-closed activation: build ceiling × server sales gate × StoreKit
/// environment, plus the ledger rules that must hold whatever the gate says.
@MainActor
final class MonetizationActivationTests: XCTestCase {

    private let token = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    private let appStoreCeiling = MonetizationConfiguration(
        catalog: true, serverVerification: true, coins: true, removeAds: true, premiumSkins: true)
    private let localCeiling = MonetizationConfiguration(
        catalog: true, serverVerification: false, coins: true, removeAds: true, premiumSkins: true,
        localStoreKitTesting: true)
    private var allIDs: Set<String> { Set(MonetizationCategory.allCases.flatMap(\.productIDs)) }

    private func status(sandbox: Bool, production: Bool, products: Set<String>? = nil,
                        age: TimeInterval = 0) -> ServerSalesStatus {
        ServerSalesStatus(sandboxSalesEnabled: sandbox, productionSalesEnabled: production,
                          enabledProductIDs: products ?? allIDs, fetchedAt: Date().addingTimeInterval(-age))
    }

    private func availability(_ category: MonetizationCategory, productID: String? = nil,
                              config: MonetizationConfiguration, env: StoreEnvironment,
                              status: ServerSalesStatus?, permanent: Bool = true) -> MonetizationAvailability {
        MonetizationPolicy.availability(for: category, productID: productID, configuration: config,
                                        gate: SalesGate(environment: env, status: status),
                                        accountToken: token, isPermanentAccount: permanent)
    }

    // MARK: Build ceiling (this test target builds with the Debug configuration)

    func testDefaultBuildCeilingIsOff() {
        XCTAssertEqual(FeatureFlags.monetizationProfile, "Off")
        XCTAssertFalse(FeatureFlags.iapEnabled)
        XCTAssertFalse(FeatureFlags.serverPurchaseVerification)
        XCTAssertFalse(FeatureFlags.coinPacksEnabled)
        XCTAssertFalse(FeatureFlags.removeAdsEnabled)
        XCTAssertFalse(FeatureFlags.premiumSkinsEnabled)
        XCTAssertFalse(FeatureFlags.localStoreKitTesting)
        XCTAssertFalse(FeatureFlags.authoritativeEconomyEnabled)
        XCTAssertFalse(FeatureFlags.anyCategoryWithinCeiling)
        XCTAssertEqual(FeatureFlags.monetizationConfiguration, .off)
        for category in MonetizationCategory.allCases {
            XCTAssertEqual(FeatureFlags.monetizationAvailability(for: category), .blocked(.catalogDisabled))
        }
    }

    func testCeilingOffBlocksEvenWhenServerOpensEverything() {
        let open = status(sandbox: true, production: true)
        for env in [StoreEnvironment.sandbox, .production, .xcode, .unknown] {
            XCTAssertEqual(availability(.removeAds, config: .off, env: env, status: open), .blocked(.catalogDisabled))
        }
        let noCoins = MonetizationConfiguration(catalog: true, serverVerification: true, coins: false,
                                                removeAds: true, premiumSkins: true)
        XCTAssertEqual(availability(.coins, config: noCoins, env: .sandbox, status: open), .blocked(.categoryDisabled))
        let noServer = MonetizationConfiguration(catalog: true, serverVerification: false, coins: true,
                                                 removeAds: true, premiumSkins: true)
        XCTAssertEqual(availability(.removeAds, config: noServer, env: .production, status: open),
                       .blocked(.serverVerificationDisabled))
    }

    func testOffProfileMakesNoServerCall() async {
        let provider = CountingProvider(answer: status(sandbox: true, production: true))
        let pm = PurchaseManager(defaults: UserDefaults(suiteName: "pt-gate-\(UUID())")!,
                                 verifier: OnDeviceVerifier(), salesStatusProvider: provider)
        await pm.refreshSalesGate(force: true)
        XCTAssertEqual(provider.calls, 0, "flag-OFF builds keep the 1.1.x network profile")
        XCTAssertEqual(pm.salesGate, .closed)
    }

    // MARK: Server gate

    func testServerGateFailsClosed() {
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .sandbox, status: nil),
                       .blocked(.salesPaused), "unreachable / RPC missing")
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .sandbox,
                                    status: status(sandbox: true, production: true, age: ServerSalesStatus.maxAge + 1)),
                       .blocked(.salesPaused), "stale answer")
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .sandbox,
                                    status: status(sandbox: false, production: false)),
                       .blocked(.salesPaused))
    }

    func testAppReviewSandboxOpenWhileProductionStaysClosed() {
        let reviewWindow = status(sandbox: true, production: false)
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .sandbox, status: reviewWindow),
                       .available(accountToken: token))
        XCTAssertEqual(availability(.coins, config: appStoreCeiling, env: .sandbox, status: reviewWindow),
                       .available(accountToken: token))
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .production, status: reviewWindow),
                       .blocked(.salesPaused))
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .unknown, status: reviewWindow),
                       .blocked(.salesPaused), "unknown environment uses the stricter Production switch")
        let launched = status(sandbox: true, production: true)
        XCTAssertEqual(availability(.premiumSkins, config: appStoreCeiling, env: .production, status: launched),
                       .available(accountToken: token))
    }

    func testPerProductServerCatalog() {
        let onlySkins = status(sandbox: true, production: true, products: Set(ShopItem.premiumProductIDs))
        XCTAssertEqual(availability(.premiumSkins, productID: ShopItem.premiumProductIDs[0], config: appStoreCeiling,
                                    env: .production, status: onlySkins), .available(accountToken: token))
        XCTAssertEqual(availability(.coins, productID: CoinPackID.small.rawValue, config: appStoreCeiling,
                                    env: .production, status: onlySkins), .blocked(.salesPaused))
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .production, status: onlySkins),
                       .blocked(.salesPaused))
    }

    func testLocalStoreKitTestingOnlyInXcodeEnvironment() {
        XCTAssertEqual(availability(.removeAds, config: localCeiling, env: .xcode, status: nil),
                       .available(accountToken: token))
        let open = status(sandbox: true, production: true)
        XCTAssertEqual(availability(.removeAds, config: localCeiling, env: .sandbox, status: open),
                       .blocked(.serverVerificationDisabled), "a Debug-StoreKit binary can never sell in Sandbox")
        XCTAssertEqual(availability(.removeAds, config: localCeiling, env: .production, status: open),
                       .blocked(.serverVerificationDisabled))
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .xcode, status: open),
                       .blocked(.salesPaused), "the App Store ceiling never sells against a local .storekit file")
    }

    func testCoinsStillNeedPermanentAccountBehindAnOpenGate() {
        let open = status(sandbox: true, production: true)
        XCTAssertEqual(availability(.coins, config: appStoreCeiling, env: .production, status: open, permanent: false),
                       .blocked(.permanentAccountRequired))
        XCTAssertEqual(availability(.removeAds, config: appStoreCeiling, env: .production, status: open, permanent: false),
                       .available(accountToken: token))
        XCTAssertEqual(MonetizationPolicy.availability(for: .removeAds, productID: nil, configuration: appStoreCeiling,
                                                       gate: SalesGate(environment: .production, status: open),
                                                       accountToken: nil, isPermanentAccount: false),
                       .blocked(.invalidAccount))
    }

    func testSalesStatusDecoderIsStrict() {
        let good = #"{"schemaVersion":1,"sandbox":{"salesEnabled":true},"production":{"salesEnabled":false},"enabledProducts":["com.perfecttap.removeads"]}"#
        let decoded = ServerSalesStatus.decode(Data(good.utf8))
        XCTAssertEqual(decoded?.sandboxSalesEnabled, true)
        XCTAssertEqual(decoded?.productionSalesEnabled, false)
        XCTAssertEqual(decoded?.enabledProductIDs, ["com.perfecttap.removeads"])
        for bad in [
            #"{"schemaVersion":2,"sandbox":{"salesEnabled":true},"production":{"salesEnabled":true},"enabledProducts":[]}"#,
            #"{"schemaVersion":1,"sandbox":{"salesEnabled":"yes"},"production":{"salesEnabled":true},"enabledProducts":[]}"#,
            #"{"schemaVersion":1,"sandbox":{"salesEnabled":true},"enabledProducts":[]}"#,
            #"{"schemaVersion":1,"sandbox":{"salesEnabled":true},"production":{"salesEnabled":true}}"#,
            "null", "", "[]",
        ] {
            XCTAssertNil(ServerSalesStatus.decode(Data(bad.utf8)), bad)
        }
    }

    func testFutureDatedStatusIsNotFresh() {
        let future = ServerSalesStatus(sandboxSalesEnabled: true, productionSalesEnabled: true,
                                       enabledProductIDs: allIDs, fetchedAt: Date().addingTimeInterval(3600))
        XCTAssertFalse(future.isFresh())
    }

    // MARK: Transaction checks (bundle, product, type, account)

    func testTransactionCheckRejectsForeignBundleProductAndType() {
        let other = UUID()
        func check(_ id: String, bundle: String = "com.perfecttap.app", consumable: Bool,
                   token: UUID?) -> PurchaseManager.TransactionCheck {
            PurchaseManager.check(productID: id, bundleID: bundle, expectedBundleID: "com.perfecttap.app",
                                  isConsumableType: consumable, appAccountToken: token, currentAccount: self.token)
        }
        XCTAssertEqual(check(CoinPackID.small.rawValue, consumable: true, token: token), .accept(.coins(500)))
        XCTAssertEqual(check(CoinPackID.small.rawValue, bundle: "com.evil.app", consumable: true, token: token), .ignore)
        XCTAssertEqual(check("com.evil.coins", consumable: true, token: token), .ignore)
        XCTAssertEqual(check(CoinPackID.small.rawValue, consumable: false, token: token), .ignore, "type mismatch")
        XCTAssertEqual(check(SpecialProductID.removeAds.rawValue, consumable: true, token: token), .ignore)
        XCTAssertEqual(check(CoinPackID.small.rawValue, consumable: true, token: other), .accountMismatch)
        XCTAssertEqual(check(CoinPackID.small.rawValue, consumable: true, token: nil), .accountMismatch)
        XCTAssertEqual(check(SpecialProductID.removeAds.rawValue, consumable: false, token: nil), .accept(.removeAds),
                       "guest non-consumables restore from Apple history without a token")
        XCTAssertEqual(PurchaseManager.check(productID: CoinPackID.small.rawValue, bundleID: "com.perfecttap.app",
                                             expectedBundleID: nil, isConsumableType: true,
                                             appAccountToken: token, currentAccount: token), .ignore)
    }

    // MARK: Ledger: refund reversal, provisional grants, persistence

    func testRefundReversalReinstatesOnceAndStaleCopiesStayBlocked() {
        var ledger = EntitlementLedger()
        let id = "com.perfecttap.skin.neonpulse"
        let t0 = Date(timeIntervalSince1970: 1_000), t1 = t0.addingTimeInterval(60), t2 = t1.addingTimeInterval(60)
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: false, signedDate: t0)),
                       [.grantItem("theme_neonpulse")])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: true, signedDate: t1)),
                       [.revokeItem("theme_neonpulse")])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: false, signedDate: t0)),
                       [], "an older non-revoked copy must not undo the refund")
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: false)), [])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: false, signedDate: t2)),
                       [.grantItem("theme_neonpulse")], "REFUND_REVERSED")
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: false, signedDate: t2)), [])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 50, productID: id, isRevoked: true, signedDate: t1)),
                       [], "the stale refund copy cannot revoke again")
    }

    func testCoinRefundReversalRecreditsOnce() {
        var ledger = EntitlementLedger()
        let t0 = Date(timeIntervalSince1970: 5_000)
        let pack = CoinPackID.medium.rawValue
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 60, productID: pack, isRevoked: false, signedDate: t0)),
                       [.creditCoins(1200)])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 60, productID: pack, isRevoked: true,
                                                    signedDate: t0.addingTimeInterval(1))), [.debitCoins(1200)])
        let reversal = PurchaseEvent(transactionID: 60, productID: pack, isRevoked: false, signedDate: t0.addingTimeInterval(2))
        XCTAssertTrue(ledger.isReinstatement(reversal))
        XCTAssertEqual(ledger.process(reversal), [.creditCoins(1200)])
        XCTAssertEqual(ledger.process(reversal), [])
    }

    func testProvisionalNonConsumableAndCoinsAreNeverProvisional() {
        var ledger = EntitlementLedger()
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 70, productID: SpecialProductID.removeAds.rawValue,
                                                    isRevoked: false), serverAcknowledged: false), [.grantNoAds])
        XCTAssertTrue(ledger.needsServerAcknowledgement(70))
        ledger.markServerAcknowledged(70)
        XCTAssertFalse(ledger.needsServerAcknowledgement(70))
        _ = ledger.process(PurchaseEvent(transactionID: 71, productID: CoinPackID.small.rawValue, isRevoked: false),
                           serverAcknowledged: false)
        XCTAssertFalse(ledger.needsServerAcknowledgement(71))
        _ = ledger.process(PurchaseEvent(transactionID: 72, productID: "com.perfecttap.skin.glitchmode", isRevoked: false),
                           serverAcknowledged: false)
        XCTAssertEqual(ledger.rejectProvisional(72), [.revokeItem("theme_glitch")])
        XCTAssertEqual(ledger.rejectProvisional(72), [])
        XCTAssertEqual(ledger.rejectProvisional(70), [], "acknowledged grants are not undone by a late rejection")
    }

    func testRestoreEffectsReapplyNonConsumablesNeverCoins() {
        var ledger = EntitlementLedger()
        let ads = PurchaseEvent(transactionID: 80, productID: SpecialProductID.removeAds.rawValue, isRevoked: false)
        let coins = PurchaseEvent(transactionID: 81, productID: CoinPackID.small.rawValue, isRevoked: false)
        _ = ledger.process(ads)
        _ = ledger.process(coins)
        XCTAssertEqual(ledger.restoreEffects(for: ads), [.grantNoAds])
        XCTAssertEqual(ledger.restoreEffects(for: coins), [])
        _ = ledger.process(PurchaseEvent(transactionID: 80, productID: SpecialProductID.removeAds.rawValue, isRevoked: true))
        XCTAssertEqual(ledger.restoreEffects(for: ads), [])
    }

    func testV2LedgerRecordsWithoutNewFieldsDecodeAsAcknowledged() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pt-ledger-\(UUID())"))
        let v2 = #"{"records":[90,{"productID":"com.perfecttap.removeads","isRevoked":false}],"legacyProcessed":[]}"#
        defaults.set(Data(v2.utf8), forKey: EntitlementLedger.storageKey)
        let ledger = EntitlementLedger.load(from: defaults)
        XCTAssertTrue(ledger.hasProcessed(90))
        XCTAssertFalse(ledger.needsServerAcknowledgement(90))
        var copy = ledger
        _ = copy.process(PurchaseEvent(transactionID: 91, productID: SpecialProductID.removeAds.rawValue, isRevoked: false,
                                       signedDate: Date(timeIntervalSince1970: 42)), serverAcknowledged: false)
        copy.save(to: defaults)
        let reloaded = EntitlementLedger.load(from: defaults)
        XCTAssertTrue(reloaded.needsServerAcknowledgement(91))
        XCTAssertEqual(reloaded, copy)
    }
}

@MainActor
final class CountingProvider: SalesStatusProviding {
    private(set) var calls = 0
    let answer: ServerSalesStatus?
    init(answer: ServerSalesStatus?) { self.answer = answer }
    func fetchSalesStatus() async -> ServerSalesStatus? {
        calls += 1
        return answer
    }
}
