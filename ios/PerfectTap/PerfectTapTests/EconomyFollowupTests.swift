import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Follow-ups after the StoreKit merge: revoked verification, post-merge
/// entitlement reconciliation, economy_disabled safety, no IAP double credit.
@MainActor
final class EconomyFollowupTests: XCTestCase {

    // MARK: verify-purchase status mapping

    func testRevokedVerificationIsNeverGranted() {
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "revoked", reason: nil), .rejected("revoked"))
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "already_revoked", reason: "refund"),
                       .rejected("revoked"))
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "granted", reason: nil), .verified)
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "already_granted", reason: nil), .verified)
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "verified_local_restore", reason: nil), .verified)
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "weird", reason: "why"), .rejected("why"))
        XCTAssertEqual(SupabaseService.purchaseVerification(status: "weird", reason: nil), .rejected("weird"))
    }

    // MARK: profile merge keeps Apple-owned entitlements

    func testMergedProfileIsReconciledWithStoreKitAfterSave() async {
        let auth = AuthViewModel.shared
        let originalProfile = PlayerProfile.load()
        let originalUID = auth.currentUID
        let originalHook = auth.reconcileOwnedEntitlements
        defer {
            auth.reconcileOwnedEntitlements = originalHook
            auth.currentUID = originalUID
            if let originalProfile { originalProfile.save() } else { PlayerProfile.clearSaved() }
        }

        var cloudMerged = PlayerProfile()
        cloudMerged.uid = "33333333-3333-3333-3333-333333333333"
        cloudMerged.noAds = false   // cloud copy lost Remove Forced Ads
        var reconcileCalls = 0
        var noAdsSeenByReconciler: Bool?
        auth.reconcileOwnedEntitlements = {
            reconcileCalls += 1
            noAdsSeenByReconciler = PlayerProfile.load()?.noAds
            // StoreKit says the Apple ID owns Remove Forced Ads: re-apply it.
            EconomyManager.shared.grantNoAds()
        }

        await auth.adoptMergedProfile(cloudMerged, uid: cloudMerged.uid)

        XCTAssertEqual(reconcileCalls, 1)
        XCTAssertEqual(noAdsSeenByReconciler, false, "reconcile runs after the merged copy is saved")
        XCTAssertEqual(PlayerProfile.load()?.noAds, true, "merge never wipes an owned entitlement")
        XCTAssertEqual(auth.currentUID, cloudMerged.uid)
    }

    // MARK: flag ON: IAP coins never double credited

    func testCreditCoinsWithFlagOnRefreshesInsteadOfAddingLocally() {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        let original = EconomyManager.shared.service
        EconomyManager.shared.service = h.service
        defer { EconomyManager.shared.service = original }
        h.profile.coins = 100

        EconomyManager.shared.apply(.creditCoins(500))
        XCTAssertEqual(h.profile.coins, 100, "server ledger credits IAP coins; no local add")
        XCTAssertEqual(h.legacyPersists, 0)
        XCTAssertEqual(h.service.status.pendingCoins, 500, "shown as pending until confirmed")

        EconomyManager.shared.apply(.debitCoins(50))
        XCTAssertEqual(h.profile.coins, 100, "refund debit is server side too")
    }

    func testCreditCoinsWithFlagOffIsUnchanged() {
        let h = EconomyHarness(authoritative: false)
        defer { h.cleanUp() }
        let original = EconomyManager.shared.service
        EconomyManager.shared.service = h.service
        defer { EconomyManager.shared.service = original }
        h.profile.coins = 100

        EconomyManager.shared.apply(.creditCoins(500))
        XCTAssertEqual(h.profile.coins, 600)
        XCTAssertEqual(h.profile.stats.totalCoinsEarned, 500)
        EconomyManager.shared.apply(.debitCoins(1_000))
        XCTAssertEqual(h.profile.coins, 0)
        XCTAssertEqual(h.remote.totalCalls, 0)
    }

    // MARK: flag ON: economy_disabled keeps events, never self-grants

    func testEconomyDisabledKeepsEventsAndNeverSelfGrants() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        h.profile.coins = 40
        var profile = h.profile
        let key = h.service.recordGrant(.gameplay(GameplayFacts(
            mode: .classic, score: 800, maxCombo: 6, perfects: 10, taps: 30, durationMs: 30_000,
            playedAt: h.clock, sessionID: UUID().uuidString.lowercased())),
            legacyCoins: 15, countsTowardTotalEarned: false, profile: &profile)!
        XCTAssertEqual(profile.coins, 40)

        h.remote.submitResponses = [.failure(.server("economy_disabled"))]
        h.remote.state.confirmedBalance = 0   // stale ledger mirror while no config is active
        await h.service.flush(reason: .manual)
        XCTAssertNil(h.service.status.confirmedBalance, "stale ledger mirror is not adopted")
        var queued = EconomyOutbox(userID: h.userID!, directory: h.directory).events
        XCTAssertEqual(queued.map(\.eventKey), [key], "event kept, not lost")
        XCTAssertEqual(queued.first?.attempts, 1)
        XCTAssertNotNil(queued.first?.nextAttemptAt, "backoff, no retry storm")
        XCTAssertTrue(h.service.status.serverEconomyDisabled)
        XCTAssertEqual(h.service.status.pendingCoins, 15)
        XCTAssertEqual(h.profile.coins, 40, "no self-grant while the server economy is off")

        // Interactive claims are queued too, never granted locally.
        let daily = await h.service.claimDailyReward(estimatedCoins: 10)
        XCTAssertEqual(daily, .queued)
        let spin = await h.service.spinWheel()
        XCTAssertEqual(spin, .queued)
        h.service.applyPurchasedCoins(1_000)
        XCTAssertEqual(h.profile.coins, 40, "paid coins wait server side (pending_iap_coins)")
        queued = EconomyOutbox(userID: h.userID!, directory: h.directory).events
        XCTAssertEqual(queued.map(\.source), [.gameplay, .dailyReward, .wheel])

        // Config activated: the same keys are delivered and the flag clears.
        h.remote.submitResponses = [.success(.init(status: "applied", granted: 15, balance: 55))]
        h.remote.state.confirmedBalance = 55
        await h.service.flush(reason: .manual)
        XCTAssertFalse(h.service.status.serverEconomyDisabled)
        XCTAssertTrue(h.remote.submitted.map(\.eventKey).contains(key))
        XCTAssertEqual(h.profile.coins, 55)
    }
}
