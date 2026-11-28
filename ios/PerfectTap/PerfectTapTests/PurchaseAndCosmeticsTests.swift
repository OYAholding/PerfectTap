import XCTest
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

    func testRevokingOneOfTwoActiveNonConsumablesKeepsEntitlement() {
        var ledger = EntitlementLedger()
        let product = "com.perfecttap.skin.glitchmode"
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 31, productID: product, isRevoked: false)),
                       [.grantItem("theme_glitch")])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 32, productID: product, isRevoked: false)), [])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 31, productID: product, isRevoked: true)), [])
        XCTAssertEqual(ledger.process(PurchaseEvent(transactionID: 32, productID: product, isRevoked: true)),
                       [.revokeItem("theme_glitch")])
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
        defaults.set(["42", "43", "44"], forKey: EntitlementLedger.legacyKey)
        XCTAssertTrue(EntitlementLedger.load(from: defaults).hasProcessed(44),
                      "v2 must continue merging the immutable 1.1.x dedupe list")
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
        XCTAssertFalse(FeatureFlags.realMoneyPurchasesEnabled)
        // Recoverable server answers must not finish (and lose) a paid transaction.
        XCTAssertFalse(SupabaseService.definitiveRejections.contains("account_mismatch"))
        XCTAssertFalse(SupabaseService.definitiveRejections.contains("unknown_product"))
        XCTAssertTrue(SupabaseService.definitiveRejections.contains("invalid_signature"))
        XCTAssertTrue(SupabaseService.definitiveRejections.contains("missing_account_token"))
    }

    func testAnonymousPlayerCanBuyRestorableNonConsumablesButNotCoins() {
        let enabled = MonetizationConfiguration(
            catalog: true, serverVerification: true, coins: true,
            removeAds: true, premiumSkins: true)
        let token = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!

        XCTAssertEqual(
            MonetizationPolicy.availability(for: .removeAds, configuration: enabled,
                                              accountToken: token, isPermanentAccount: false),
            .available(accountToken: token))
        XCTAssertEqual(
            MonetizationPolicy.availability(for: .premiumSkins, configuration: enabled,
                                              accountToken: token, isPermanentAccount: false),
            .available(accountToken: token))
        XCTAssertEqual(
            MonetizationPolicy.availability(for: .coins, configuration: enabled,
                                              accountToken: token, isPermanentAccount: false),
            .blocked(.permanentAccountRequired))
        XCTAssertEqual(
            MonetizationPolicy.availability(for: .coins, configuration: enabled,
                                              accountToken: token, isPermanentAccount: true),
            .available(accountToken: token))
    }

    func testAppleNonceHashIsStableAndNotPlaintext() {
        XCTAssertEqual(AuthViewModel.sha256("perfecttap"),
                       "411f2fc961176a307cc08ea22717c0a8a84205d7ddc63b123e703b13eb3e4bd2")
        let nonce = AuthViewModel.randomNonce()
        XCTAssertEqual(nonce.count, 32)
        XCTAssertNotEqual(AuthViewModel.sha256(nonce), nonce)
    }
}
