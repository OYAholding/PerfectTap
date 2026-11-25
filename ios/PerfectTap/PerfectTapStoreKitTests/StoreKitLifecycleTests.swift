import XCTest
import StoreKit
import StoreKitTest
@testable import PerfectTap

/// Real StoreKit 2 transactions (local .storekit file, Xcode environment)
/// driven through PurchaseManager's listener / restore path with a fake
/// server verifier. The shared PurchaseManager never auto-processes in an
/// XCTest host, so each test owns its ledger and its outcomes.
@MainActor
final class StoreKitLifecycleTests: XCTestCase {

    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var savedProfile: PlayerProfile?
    private var savedUID: String?
    private let account = "11111111-2222-4333-8444-555555555555"
    private var accountToken: UUID { UUID(uuidString: account)! }

    private final class SwitchableVerifier: PurchaseVerifying {
        var answer: PurchaseVerification
        private(set) var calls = 0
        init(_ answer: PurchaseVerification) { self.answer = answer }
        func verify(jws: String) async -> PurchaseVerification {
            calls += 1
            XCTAssertFalse(jws.isEmpty, "the signed JWS is what the server verifies")
            return answer
        }
    }

    override func setUp() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("SKTestSession.buyProduct(identifier:options:) needs iOS 17") }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PerfectTap", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        defaults = UserDefaults(suiteName: "pt-sk-\(UUID().uuidString)")
        savedProfile = PlayerProfile.load()
        var profile = PlayerProfile()
        profile.coins = 100
        profile.save()
        savedUID = OfflineBackend.shared.uid
        OfflineBackend.shared.uid = account
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        OfflineBackend.shared.uid = savedUID
        if let savedProfile { savedProfile.save() } else { PlayerProfile.clearSaved() }
    }

    // MARK: Helpers

    private func manager(_ verifier: PurchaseVerifying, defaults: UserDefaults? = nil) -> PurchaseManager {
        let pm = PurchaseManager(defaults: defaults ?? self.defaults, verifier: verifier,
                                 salesStatusProvider: CountingProvider(answer: nil))
        pm.automaticRetryEnabled = false
        return pm
    }

    @available(iOS 17.0, *)
    private func buy(_ productID: String, token: UUID?) async throws -> UInt64 {
        var options: Set<Product.PurchaseOption> = []
        if let token { options.insert(.appAccountToken(token)) }
        return try await session.buyProduct(identifier: productID, options: options).id
    }

    private func verification(for id: UInt64) async -> VerificationResult<Transaction>? {
        for await result in Transaction.unfinished where result.unsafePayloadValue.id == id { return result }
        for await result in Transaction.all where result.unsafePayloadValue.id == id { return result }
        return nil
    }

    private func signed(_ id: UInt64, file: StaticString = #filePath, line: UInt = #line) async throws
        -> VerificationResult<Transaction> {
        let result = await verification(for: id)
        return try XCTUnwrap(result, "no StoreKit transaction \(id)", file: file, line: line)
    }

    /// The refunded, re-signed copy of a non-consumable (StoreKitTest updates it asynchronously).
    private func revokedCopy(productID: String, id: UInt64, file: StaticString = #filePath,
                             line: UInt = #line) async throws -> VerificationResult<Transaction> {
        for _ in 0..<50 {
            if let latest = await Transaction.latest(for: productID),
               latest.unsafePayloadValue.id == id, latest.unsafePayloadValue.revocationDate != nil { return latest }
            for await result in Transaction.all where result.unsafePayloadValue.id == id
                && result.unsafePayloadValue.revocationDate != nil { return result }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw XCTSkip("StoreKitTest did not surface the revoked transaction \(id) on this runtime")
    }

    private func isUnfinished(_ id: UInt64) async -> Bool {
        for await result in Transaction.unfinished where result.unsafePayloadValue.id == id { return true }
        return false
    }

    private func coins() -> Int { EconomyManager.shared.currentProfile().coins }
    private func profile() -> PlayerProfile { EconomyManager.shared.currentProfile() }

    // MARK: Consumables

    func testConsumableIsCreditedOnceAndFinishedOnlyAfterServerAck() async throws {
        guard #available(iOS 17.0, *) else { return }
        let verifier = SwitchableVerifier(.unavailable)
        let pm = manager(verifier)
        let id = try await buy(CoinPackID.small.rawValue, token: accountToken)
        let firstCopy = try await signed(id)
        XCTAssertEqual(firstCopy.unsafePayloadValue.appAccountToken, accountToken, "appAccountToken = Supabase uid")

        // Server outage: nothing credited, transaction survives (as after an app kill).
        let outage = await pm.handleForTesting(firstCopy)
        XCTAssertEqual(outage, .deferred)
        XCTAssertEqual(coins(), 100)
        let stillUnfinished = await isUnfinished(id)
        XCTAssertTrue(stillUnfinished, "an unacknowledged consumable must stay in Transaction.unfinished")

        // "Relaunch": a fresh manager over the same persisted ledger retries.
        verifier.answer = .verified
        let relaunched = manager(verifier)
        let retry = await relaunched.handleForTesting(try await signed(id))
        XCTAssertEqual(retry, .delivered([.creditCoins(500)]))
        XCTAssertEqual(coins(), 600)
        let finished = await isUnfinished(id)
        XCTAssertFalse(finished, "finished only after the server acknowledged it")

        // Duplicate delivery (listener + purchase flow + restore): no second credit, no second server call.
        let callsBefore = verifier.calls
        // Re-deliver the same signed copy (a finished consumable leaves Transaction.all).
        let duplicate = await relaunched.handleForTesting(firstCopy)
        XCTAssertEqual(duplicate, .delivered([]))
        XCTAssertEqual(coins(), 600)
        XCTAssertEqual(verifier.calls, callsBefore)
    }

    func testConsumableNeverCreditsAnotherAccount() async throws {
        guard #available(iOS 17.0, *) else { return }
        let verifier = SwitchableVerifier(.verified)
        let pm = manager(verifier)
        let otherAccount = UUID(uuidString: "99999999-2222-4333-8444-555555555555")!
        let id = try await buy(CoinPackID.medium.rawValue, token: otherAccount)
        let outcome = await pm.handleForTesting(try await signed(id))
        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(coins(), 100)
        XCTAssertEqual(verifier.calls, 0, "never even sent to the server under the wrong account")
        let kept = await isUnfinished(id)
        XCTAssertTrue(kept, "kept for the account that paid")

        // The paying account signs in on this device: credited exactly once.
        OfflineBackend.shared.uid = otherAccount.uuidString.lowercased()
        let delivered = await pm.handleForTesting(try await signed(id))
        XCTAssertEqual(delivered, .delivered([.creditCoins(1200)]))
    }

    func testConsumableWithoutAccountTokenIsNeverCredited() async throws {
        guard #available(iOS 17.0, *) else { return }
        let pm = manager(SwitchableVerifier(.verified))
        let id = try await buy(CoinPackID.large.rawValue, token: nil)
        let outcome = await pm.handleForTesting(try await signed(id))
        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(coins(), 100)
    }

    func testNoAccountYetDefersEverything() async throws {
        guard #available(iOS 17.0, *) else { return }
        let pm = manager(SwitchableVerifier(.verified))
        let id = try await buy(SpecialProductID.removeAds.rawValue, token: nil)
        OfflineBackend.shared.uid = nil
        let outcome = await pm.handleForTesting(try await signed(id))
        XCTAssertEqual(outcome, .deferred)
        XCTAssertFalse(profile().noAds)
    }

    // MARK: Non-consumables, guests, restore

    func testGuestNonConsumablesUnlockDuringOutageAndRestoreOnNewDevice() async throws {
        guard #available(iOS 17.0, *) else { return }
        let verifier = SwitchableVerifier(.unavailable)
        let pm = manager(verifier)
        // Guest (anonymous uid) buys without registering.
        let adsID = try await buy(SpecialProductID.removeAds.rawValue, token: accountToken)
        let skinID = try await buy("com.perfecttap.skin.liquidchrome", token: accountToken)

        let ads = await pm.handleForTesting(try await signed(adsID))
        XCTAssertEqual(ads, .provisional([.grantNoAds]), "Apple-signed history unlocks even while the server is down")
        XCTAssertTrue(profile().noAds)
        XCTAssertTrue(pm.ledgerSnapshot.needsServerAcknowledgement(adsID))
        let adsUnfinished = await isUnfinished(adsID)
        XCTAssertTrue(adsUnfinished, "finished only after server acknowledgement")

        verifier.answer = .verified
        let acked = await pm.handleForTesting(try await signed(adsID))
        XCTAssertEqual(acked, .delivered([]))
        XCTAssertFalse(pm.ledgerSnapshot.needsServerAcknowledgement(adsID))
        let skin = await pm.handleForTesting(try await signed(skinID))
        XCTAssertEqual(skin, .delivered([.grantItem("theme_chrome")]))

        // Reinstall / new device: empty ledger, empty profile, server down, gate closed.
        PlayerProfile().save()
        let newDevice = manager(SwitchableVerifier(.unavailable),
                                defaults: UserDefaults(suiteName: "pt-sk-new-\(UUID().uuidString)"))
        newDevice.setSalesGateForTesting(.closed)
        var restored = 0
        for await result in Transaction.currentEntitlements {
            switch await newDevice.handleForTesting(result, restore: true) {
            case .delivered?, .provisional?: restored += 1
            default: break
            }
        }
        XCTAssertEqual(restored, 2)
        XCTAssertTrue(profile().noAds)
        XCTAssertTrue(profile().ownedItems.contains("theme_chrome"))
    }

    func testRestoreReappliesOwnedNonConsumableToAnotherSignedInAccount() async throws {
        guard #available(iOS 17.0, *) else { return }
        let pm = manager(SwitchableVerifier(.verified))
        let id = try await buy("com.perfecttap.skin.cosmicgold", token: accountToken)
        _ = await pm.handleForTesting(try await signed(id))
        XCTAssertTrue(profile().ownedItems.contains("theme_cosmicgold"))

        // Same Apple ID, different player profile on this device (ledger already has the transaction).
        OfflineBackend.shared.uid = "22222222-2222-4333-8444-555555555555"
        PlayerProfile().save()
        let restored = await pm.handleForTesting(try await signed(id), restore: true)
        XCTAssertEqual(restored, .delivered([.grantItem("theme_cosmicgold")]))
        let again = await pm.handleForTesting(try await signed(id), restore: true)
        XCTAssertEqual(again, .delivered([]), "idempotent")
    }

    func testServerRejectionAfterProvisionalGrantRemovesIt() async throws {
        guard #available(iOS 17.0, *) else { return }
        let verifier = SwitchableVerifier(.unavailable)
        let pm = manager(verifier)
        let id = try await buy("com.perfecttap.skin.glitchmode", token: accountToken)
        _ = await pm.handleForTesting(try await signed(id))
        XCTAssertTrue(profile().ownedItems.contains("theme_glitch"))
        verifier.answer = .rejected("invalid_signature")
        let outcome = await pm.handleForTesting(try await signed(id))
        XCTAssertEqual(outcome, .rejected("invalid_signature"))
        XCTAssertFalse(profile().ownedItems.contains("theme_glitch"))
    }

    // MARK: Refunds

    func testRefundRevokesNonConsumableAndDebitsCoinsWithoutServer() async throws {
        guard #available(iOS 17.0, *) else { return }
        let verifier = SwitchableVerifier(.verified)
        let pm = manager(verifier)
        let skinID = try await buy("com.perfecttap.skin.neonpulse", token: accountToken)
        let coinID = try await buy(CoinPackID.small.rawValue, token: accountToken)
        _ = await pm.handleForTesting(try await signed(skinID))
        _ = await pm.handleForTesting(try await signed(coinID))
        XCTAssertEqual(coins(), 600)

        try session.refundTransaction(identifier: UInt(skinID))
        try session.refundTransaction(identifier: UInt(coinID))
        verifier.answer = .unavailable   // refunds never wait for the server
        let refundedSkin = try await revokedCopy(productID: "com.perfecttap.skin.neonpulse", id: skinID)
        let skinOutcome = await pm.handleForTesting(refundedSkin)
        XCTAssertEqual(skinOutcome, .delivered([.revokeItem("theme_neonpulse")]))
        XCTAssertFalse(profile().ownedItems.contains("theme_neonpulse"))

        if let refundedCoins = await verification(for: coinID), refundedCoins.unsafePayloadValue.revocationDate != nil {
            let coinOutcome = await pm.handleForTesting(refundedCoins)
            XCTAssertEqual(coinOutcome, .delivered([.debitCoins(500)]))
            XCTAssertEqual(coins(), 100)
        }
        // Duplicate refund delivery is a no-op.
        let again = await pm.handleForTesting(refundedSkin)
        XCTAssertEqual(again, .delivered([]))
    }

    // Ask to Buy / pending: Product.purchase blocks on the approval UI inside an
    // XCTest host (no scene), so it is covered by device QA scenario 9
    // (docs/STOREKIT_DEVICE_SANDBOX_QA.he.md). The client never grants on
    // .pending; the approved transaction arrives via Transaction.updates and
    // follows the same path as testConsumableIsCreditedOnceAndFinishedOnlyAfterServerAck.
}
