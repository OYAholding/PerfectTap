import XCTest
import StoreKitTest
import StoreKit
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// 1.2.0: exactly-once purchase delivery, refunds, server-verification gate,
/// premium skins and cosmetic consolidation.
@MainActor
final class PurchaseAndCosmeticsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var savedProfile: PlayerProfile?

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "pt-tests-\(UUID().uuidString)")
        savedProfile = PlayerProfile.load()
        var p = PlayerProfile()
        p.coins = 100
        p.save()
    }

    override func tearDown() async throws {
        if let savedProfile { savedProfile.save() } else { PlayerProfile.clearSaved() }
    }

    private func coins() -> Int { EconomyManager.shared.currentProfile().coins }
    private func profile() -> PlayerProfile { EconomyManager.shared.currentProfile() }

    // MARK: Ledger

    func testLedgerGrantsOnceAndRevokes() {
        var ledger = EntitlementLedger()
        let buy = PurchaseEvent(transactionID: 1, productID: "com.perfecttap.coins.500", isRevoked: false)
        XCTAssertEqual(ledger.process(buy), [.creditCoins(500)])
        XCTAssertEqual(ledger.process(buy), [], "duplicate delivery (listener + flow + unfinished)")
        let refund = PurchaseEvent(transactionID: 1, productID: "com.perfecttap.coins.500", isRevoked: true)
        XCTAssertEqual(ledger.process(refund), [.debitCoins(500)])
        XCTAssertEqual(ledger.process(refund), [])
    }

    func testRevocationBeforePurchaseBlocksGrant() {
        var ledger = EntitlementLedger()
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 9, productID: "com.perfecttap.skin.glitchmode", isRevoked: true)), [])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 9, productID: "com.perfecttap.skin.glitchmode", isRevoked: false)), [])
    }

    func testUnknownProductIsIgnored() {
        var ledger = EntitlementLedger()
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 3, productID: "com.evil.free", isRevoked: false)), [])
        XCTAssertFalse(ledger.hasProcessed(3))
    }

    func testLedgerKeepsLegacyCreditedTransactions() {
        defaults.set(["42", "43"], forKey: EntitlementLedger.legacyKey)
        var ledger = EntitlementLedger.load(from: defaults)
        XCTAssertTrue(ledger.hasProcessed(42))
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 42, productID: "com.perfecttap.coins.500", isRevoked: false)), [],
                       "a 1.1.x purchase must not be credited again after the update")
        ledger.save(to: defaults)
        XCTAssertTrue(EntitlementLedger.load(from: defaults).hasProcessed(42))
    }

    // MARK: Delivery pipeline

    private struct FakeVerifier: PurchaseVerifying {
        let answer: PurchaseVerification
        func verify(jws: String) async -> PurchaseVerification { answer }
    }

    func testServerUnavailableDefersWithoutGranting() async {
        let pm = PurchaseManager(defaults: defaults, verifier: FakeVerifier(answer: .unavailable))
        let outcome = await pm.deliver(PurchaseEvent(transactionID: 7, productID: "com.perfecttap.coins.1200", isRevoked: false), jws: "x")
        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(coins(), 100, "nothing credited until the server confirms")

        pm.verifier = FakeVerifier(answer: .verified)
        let retry = await pm.deliver(PurchaseEvent(transactionID: 7, productID: "com.perfecttap.coins.1200", isRevoked: false), jws: "x")
        XCTAssertEqual(retry, .delivered([.creditCoins(1200)]))
        XCTAssertEqual(coins(), 1300)
    }

    func testRejectedPurchaseGrantsNothing() async {
        let pm = PurchaseManager(defaults: defaults, verifier: FakeVerifier(answer: .rejected("bad signature")))
        let outcome = await pm.deliver(PurchaseEvent(transactionID: 8, productID: "com.perfecttap.removeads", isRevoked: false), jws: "x")
        XCTAssertEqual(outcome, .rejected("bad signature"))
        XCTAssertFalse(profile().noAds)
    }

    func testRefundRemovesSkinAndCoinsNeverNegative() async {
        let pm = PurchaseManager(defaults: defaults, verifier: FakeVerifier(answer: .verified))
        _ = await pm.deliver(PurchaseEvent(transactionID: 20, productID: "com.perfecttap.skin.cosmicgold", isRevoked: false), jws: "x")
        XCTAssertTrue(profile().ownedItems.contains("theme_cosmicgold"))
        EconomyManager.shared.equipItem(ShopItem.item(id: "theme_cosmicgold")!)
        XCTAssertEqual(profile().equippedTheme, "cosmicgold")

        _ = await pm.deliver(PurchaseEvent(transactionID: 20, productID: "com.perfecttap.skin.cosmicgold", isRevoked: true), jws: "x")
        XCTAssertFalse(profile().ownedItems.contains("theme_cosmicgold"))
        XCTAssertEqual(profile().equippedTheme, "default")

        _ = await pm.deliver(PurchaseEvent(transactionID: 21, productID: "com.perfecttap.coins.500", isRevoked: false), jws: "x")
        EconomyManager.shared.updateProfile { $0.coins = 50 }   // spent most of it
        _ = await pm.deliver(PurchaseEvent(transactionID: 21, productID: "com.perfecttap.coins.500", isRevoked: true), jws: "x")
        XCTAssertEqual(coins(), 0)
    }

    // MARK: Cosmetics

    func testPremiumSkinsAreNotBuyableWithCoinsAndNotFree() {
        EconomyManager.shared.updateProfile { $0.coins = 1_000_000 }
        for item in ShopItem.premium {
            XCTAssertTrue(item.isPremium)
            XCTAssertFalse(item.isFree)
            XCTAssertFalse(EconomyManager.shared.ownsItem(item.id))
            XCTAssertFalse(EconomyManager.shared.buyItem(item))
            XCTAssertEqual(PurchaseProductKind.kind(for: item.premiumProductID!), .premiumItem(item.id))
        }
        XCTAssertEqual(coins(), 1_000_000)
    }

    func testPremiumThemesKeepZonesAndIndicatorGeometry() {
        // A skin may not change what the player sees of the scoring zones.
        for theme in AppTheme.premium {
            XCTAssertNotNil(ShopItem.item(id: ShopItem.themeID(forName: theme.name)), "\(theme.name) has a shop item")
            XCTAssertEqual(AppTheme.named(theme.name).name, theme.name)
        }
        XCTAssertEqual(GameConfig.perfectZone, 0.04)
    }

    func testThemeResolveFallsBackWhenNotOwned() {
        var p = PlayerProfile()
        p.equippedTheme = "glitch"
        XCTAssertEqual(ThemeManager.resolve("glitch", profile: p).name, "default")
        p.ownedItems.append("theme_glitch")
        XCTAssertEqual(ThemeManager.resolve("glitch", profile: p).name, "glitch")
        XCTAssertEqual(ThemeManager.resolve("default", profile: p).name, "default")
    }

    func testLookupHelpers() {
        XCTAssertEqual(ShopItem.themeID(forName: "fire"), "theme_fire")
        XCTAssertEqual(ShopItem.themeName(forID: "theme_fire"), "fire")
        XCTAssertEqual(ShopItem.avatarEmoji(for: "avatar_ninja"), "🥷")
        XCTAssertEqual(ShopItem.avatarEmoji(for: nil), "😊")
        XCTAssertEqual(ShopItem.avatarEmoji(for: "default"), "😊")
    }

    func testRealMoneyIsOffByDefault() {
        XCTAssertFalse(FeatureFlags.iapEnabled, "owner approval required before enabling")
        XCTAssertFalse(FeatureFlags.serverPurchaseVerification)
    }

    // MARK: StoreKitTest (local configuration, fake money)

    private var allProductIDs: Set<String> {
        Set(CoinPackID.allCases.map(\.rawValue) + SpecialProductID.allCases.map(\.rawValue) + ShopItem.premiumProductIDs)
    }

    /// The bundled .storekit file lists every product the code sells, with the
    /// right type (consumable coins, non-consumable Remove Ads and skins).
    func testStoreKitConfigurationFileMatchesCode() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PerfectTap", withExtension: "storekit"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        var types: [String: String] = [:]
        for p in products { types[p["productID"] as? String ?? ""] = p["type"] as? String }
        XCTAssertEqual(Set(types.keys), allProductIDs)
        for pack in CoinPackID.allCases { XCTAssertEqual(types[pack.rawValue], "Consumable") }
        XCTAssertEqual(types[SpecialProductID.removeAds.rawValue], "NonConsumable")
        for id in ShopItem.premiumProductIDs { XCTAssertEqual(types[id], "NonConsumable") }
    }

    /// Loads the products through a real StoreKitTest session. Skipped (not
    /// passed) when the simulator's StoreKit agent refuses the session, which
    /// happens in command-line runs (SKInternalErrorDomain 3); run from Xcode.
    func testLocalStoreKitSessionLoadsProducts() async throws {
        let session = try SKTestSession(configurationFileNamed: "PerfectTap")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let products = try await Product.products(for: allProductIDs)
        try XCTSkipIf(products.isEmpty, "StoreKitTest session unavailable in this environment")
        XCTAssertEqual(Set(products.map(\.id)), allProductIDs)
    }
}
