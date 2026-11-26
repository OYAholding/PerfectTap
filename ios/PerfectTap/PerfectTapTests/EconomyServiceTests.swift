import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

// MARK: - Test doubles

@MainActor
final class FakeEconomyRemote: EconomyRemote {
    var submitted: [EconomyEvent] = []
    var purchases: [(itemID: String, eventKey: UUID)] = []
    var stateLoads = 0
    var profileLoads = 0
    /// Responses consumed in order; the last one repeats.
    var submitResponses: [Result<EconomyRPCResult, EconomyRemoteFailure>] = [.success(.init(status: "applied"))]
    var purchaseResponse: Result<EconomyRPCResult, EconomyRemoteFailure> = .success(.init(status: "applied"))
    var state = EconomyStateSnapshot(confirmedBalance: 0, coinDebt: 0, configVersion: "balanced-premium-rc1",
                                     legacyStatus: "accepted")
    var serverProfile: PlayerProfile? = nil
    var onSubmit: ((EconomyEvent) -> Void)?

    var totalCalls: Int { submitted.count + purchases.count + stateLoads + profileLoads }

    func submit(_ event: EconomyEvent) async -> Result<EconomyRPCResult, EconomyRemoteFailure> {
        submitted.append(event)
        onSubmit?(event)
        let response = submitResponses.count > 1 ? submitResponses.removeFirst() : submitResponses[0]
        return response
    }

    func purchaseItem(_ itemID: String, eventKey: UUID) async -> Result<EconomyRPCResult, EconomyRemoteFailure> {
        purchases.append((itemID, eventKey))
        return purchaseResponse
    }

    func loadState() async -> Result<EconomyStateSnapshot, EconomyRemoteFailure> {
        stateLoads += 1
        return .success(state)
    }

    func loadProfile() async -> PlayerProfile? {
        profileLoads += 1
        return serverProfile
    }
}

/// In-memory profile store + configurable flag/user for `LedgerEconomyService`.
@MainActor
final class EconomyHarness {
    var authoritative: Bool
    var userID: String?
    var profile = PlayerProfile()
    var legacyPersists = 0
    var serverSaves = 0
    var clock = Date(timeIntervalSince1970: 1_795_000_000)
    let remote = FakeEconomyRemote()
    let directory: URL
    let defaults: UserDefaults
    lazy var service: LedgerEconomyService = makeService()

    init(authoritative: Bool, userID: String? = "11111111-1111-1111-1111-111111111111") {
        self.authoritative = authoritative
        self.userID = userID
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("economy-tests-\(UUID().uuidString)", isDirectory: true)
        defaults = UserDefaults(suiteName: "economy-tests-\(UUID().uuidString)")!
    }

    func makeService() -> LedgerEconomyService {
        LedgerEconomyService(
            authoritative: { [weak self] in self?.authoritative ?? false },
            currentUserID: { [weak self] in self?.userID },
            remote: remote,
            outboxDirectory: directory,
            loadProfile: { [weak self] in self?.profile ?? PlayerProfile() },
            saveProfile: { [weak self] in self?.profile = $0; self?.serverSaves += 1 },
            persistLegacy: { [weak self] in self?.profile = $0; self?.legacyPersists += 1 },
            defaults: defaults,
            now: { [weak self] in self?.clock ?? Date() },
            rewardedPollDelays: [],
            observeForeground: false)
    }

    func cleanUp() {
        service.cancelPendingWork()
        try? FileManager.default.removeItem(at: directory)
    }
}

private let userA = "11111111-1111-1111-1111-111111111111"
private let userB = "22222222-2222-2222-2222-222222222222"

private func sampleFacts() -> GameplayFacts {
    GameplayFacts(mode: .classic, score: 1_000, maxCombo: 10, perfects: 30, taps: 60, durationMs: 45_000,
                  playedAt: Date(timeIntervalSince1970: 1_795_000_000), sessionID: "session-1")
}

// MARK: - Flag OFF: identical legacy behaviour, no network

@MainActor
final class EconomyFlagOffParityTests: XCTestCase {
    func testShippingFlagIsOffAndManagerUsesLedgerService() {
        XCTAssertFalse(FeatureFlags.authoritativeEconomyEnabled)
        XCTAssertFalse(EconomyManager.shared.service.isAuthoritative)
        XCTAssertEqual(EconomyConfig.current, .legacy)
    }

    func testLegacyNumbersAreUnchanged() {
        let legacy = EconomyConfig.legacy
        XCTAssertEqual(legacy.dailyRewards, [25, 35, 50, 75, 100, 125, 250])
        XCTAssertEqual(legacy.wheelRewards, [25, 50, 10, 100, 35, 5, 250, 75])
        XCTAssertEqual(legacy.homeRewardedCoins, 25)
        XCTAssertEqual(legacy.seasonAdsRequired, 50)
        XCTAssertEqual(legacy.seasonCoinRewards.reduce(0, +), 5_850)
        XCTAssertEqual(legacy.starterItems, [])
        // Same formula as 1.1.0: score/50 + combo bonus + mode bonus, minimum 3.
        XCTAssertEqual(legacy.gameCoins(score: 1_000, maxCombo: 10, mode: .classic), 27)
        XCTAssertEqual(legacy.gameCoins(score: 1_000, maxCombo: 10, mode: .duel), 31)
        XCTAssertEqual(legacy.gameCoins(score: 0, maxCombo: 0, mode: .classic), 3)
        XCTAssertEqual(legacy.gameCoins(score: 2_500, maxCombo: 25, mode: .classic), 60)
        XCTAssertEqual(legacy.gameCoins(score: 999, maxCombo: 4, mode: .classic), 22)
        XCTAssertEqual(legacy.gameCoins(score: 5_000, maxCombo: 50, mode: .timed), 0)
        XCTAssertEqual(GameConfig.calcGameCoins(score: 1_000, maxCombo: 10, mode: .classic), 27)
        XCTAssertEqual(ShopItem.item(id: "avatar_dragon")?.price, 750)
    }

    func testRecordGrantMutatesLocallyExactlyLikeLegacyCode() {
        let h = EconomyHarness(authoritative: false)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        profile.coins = 100

        let key1 = h.service.recordGrant(.gameplay(sampleFacts()), legacyCoins: 27,
                                         countsTowardTotalEarned: false, profile: &profile)
        let key2 = h.service.recordGrant(.achievement(id: "games_1"), legacyCoins: 25,
                                         countsTowardTotalEarned: false, profile: &profile)
        let key3 = h.service.recordGrant(.challenge(id: "c1"), legacyCoins: 50,
                                         countsTowardTotalEarned: true, profile: &profile)
        h.service.recordGrant(.quest(id: "q_games_3", difficulty: .easy, serverDay: "2026-11-25"),
                              legacyCoins: 0, countsTowardTotalEarned: true, profile: &profile)

        XCTAssertEqual(profile.coins, 202)
        XCTAssertEqual(profile.stats.totalCoinsEarned, 50)
        XCTAssertNil(key1); XCTAssertNil(key2); XCTAssertNil(key3)
        XCTAssertEqual(h.remote.totalCalls, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory.path), "no outbox file with flag OFF")
        XCTAssertEqual(h.service.status.pendingCoins, 0)
    }

    func testLegacyPurchaseRewardedAndStoreKitPathsAreLocalOnly() async {
        let h = EconomyHarness(authoritative: false)
        defer { h.cleanUp() }
        h.profile.coins = 100
        let neon = ShopItem.item(id: "theme_neon")!   // legacy price 75

        let bought = await h.service.purchaseItem(neon)
        XCTAssertTrue(bought)
        XCTAssertEqual(h.profile.coins, 25)
        XCTAssertTrue(h.profile.ownedItems.contains("theme_neon"))
        let again = await h.service.purchaseItem(neon)
        XCTAssertFalse(again, "already owned: no second deduction")
        XCTAssertEqual(h.profile.coins, 25)

        XCTAssertNil(h.service.rewardedVerification(for: .homeCoins, claimIndex: 1, referenceEventKey: nil))
        h.service.rewardedAdCompleted(.homeCoins, legacyCoins: 25)
        XCTAssertEqual(h.profile.coins, 50)
        XCTAssertEqual(h.profile.stats.totalCoinsEarned, 25)
        h.service.rewardedAdCompleted(.revive, legacyCoins: 0)
        XCTAssertEqual(h.profile.coins, 50)

        h.service.applyPurchasedCoins(500)
        XCTAssertEqual(h.profile.coins, 550)
        h.service.applyPurchasedCoins(-1_000)
        XCTAssertEqual(h.profile.coins, 0, "refund debit never goes below zero")

        XCTAssertEqual(h.service.spendableBalance(profile: h.profile), h.profile.coins)
        XCTAssertEqual(h.service.starterItemChoices(profile: PlayerProfile()).map(\.id), [])
        await h.service.flush(reason: .manual)
        await h.service.refreshConfirmedBalance()
        h.service.accountDidChange()
        XCTAssertEqual(h.remote.totalCalls, 0, "flag OFF makes no economy network calls")
    }

    func testEconomyManagerLegacyEntryPointsUnchanged() {
        let original = PlayerProfile.load()
        defer { if let original { original.save() } else { PlayerProfile.clearSaved() } }
        var p = PlayerProfile()
        p.coins = 10
        p.save()

        EconomyManager.shared.addCoins(40, source: .wheelSpin)
        XCTAssertEqual(EconomyManager.shared.coinBalance, 50)
        XCTAssertTrue(EconomyManager.shared.spendCoins(20))
        XCTAssertEqual(EconomyManager.shared.currentProfile().coins, 30)
        EconomyManager.shared.apply(.debitCoins(100))
        XCTAssertEqual(EconomyManager.shared.currentProfile().coins, 0)
    }
}

// MARK: - Outbox persistence

@MainActor
final class EconomyOutboxTests: XCTestCase {
    func testEventsSurviveRelaunchWithTheSameEventKey() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let event = EconomyEvent(eventKey: UUID(), source: .quest,
                                 payload: ["quest_id": .string("q_games_3"), "server_day": .string("2026-11-25")],
                                 createdAt: Date(timeIntervalSince1970: 1_795_000_000), estimatedCoins: 25)
        do {
            let outbox = EconomyOutbox(userID: userA, directory: dir)
            XCTAssertTrue(outbox.enqueue(event))
            XCTAssertTrue(outbox.enqueue(event), "re-enqueue is idempotent")
            XCTAssertEqual(outbox.events.count, 1)
        }
        // "App kill": a brand-new instance reads the file.
        let reopened = EconomyOutbox(userID: userA, directory: dir)
        XCTAssertEqual(reopened.events, [event])
        XCTAssertEqual(reopened.pendingCoins, 25)
        XCTAssertTrue(reopened.fileURL.path.hasPrefix(dir.path))
        XCTAssertEqual(reopened.fileURL.lastPathComponent, "outbox-\(userA).json")

        XCTAssertTrue(EconomyOutbox(userID: userB, directory: dir).isEmpty, "outboxes are per user")

        reopened.remove(event.eventKey)
        XCTAssertTrue(EconomyOutbox(userID: userA, directory: dir).isEmpty)
    }

    func testDefaultLocationIsApplicationSupport() {
        XCTAssertTrue(EconomyOutbox.defaultDirectory.path.contains("Application Support"))
        XCTAssertEqual(EconomyOutbox.fileName(for: "../ETC/passwd"), "outbox-etcpasswd.json")
    }
}

// MARK: - Flag ON: authoritative behaviour

@MainActor
final class AuthoritativeEconomyTests: XCTestCase {
    func testGrantsEnqueueEventsAndNeverMutateCoins() {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        profile.coins = 300

        let key = h.service.recordGrant(.gameplay(sampleFacts()), legacyCoins: 19,
                                        countsTowardTotalEarned: false, profile: &profile)
        h.service.recordGrant(.challenge(id: "c9"), legacyCoins: 0, countsTowardTotalEarned: true, profile: &profile)
        h.service.recordGrant(.legacy(.wheelSpin), legacyCoins: 40, countsTowardTotalEarned: false, profile: &profile)

        XCTAssertEqual(profile.coins, 300, "no local authoritative coin mutation")
        XCTAssertNotNil(key)
        let outbox = EconomyOutbox(userID: userA, directory: h.directory)
        XCTAssertEqual(outbox.events.map(\.source), [.gameplay, .challenge])
        XCTAssertEqual(outbox.events.first?.eventKey, key)
        XCTAssertEqual(outbox.events.first?.payload["score"], .int(1_000))
        XCTAssertEqual(outbox.events.first?.payload["session_id"], .string("session-1"))
        XCTAssertNil(outbox.events.first?.payload["coins"], "the client never sends an amount")
        XCTAssertEqual(h.service.status.pendingCoins, 19)
        XCTAssertEqual(h.remote.totalCalls, 0, "enqueue does not hit the network")
    }

    func testFlushAppliesServerBalanceAndRetriesWithTheSameKey() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        let key = h.service.recordGrant(.achievement(id: "games_1"), legacyCoins: 25,
                                        countsTowardTotalEarned: false, profile: &profile)!

        h.remote.submitResponses = [.failure(.network)]
        await h.service.flush(reason: .manual)
        var queued = EconomyOutbox(userID: userA, directory: h.directory).events
        XCTAssertEqual(queued.map(\.eventKey), [key])
        XCTAssertEqual(queued.first?.attempts, 1)
        XCTAssertNotNil(queued.first?.nextAttemptAt, "backoff scheduled")

        // Relaunch: a new service instance reads the persisted event.
        let relaunched = h.makeService()
        h.remote.submitResponses = [.success(.init(status: "applied", granted: 25, balance: 125))]
        h.remote.state.confirmedBalance = 125
        await relaunched.flush(reason: .manual)
        XCTAssertEqual(h.remote.submitted.map(\.eventKey), [key, key], "retry reuses the event key")
        queued = EconomyOutbox(userID: userA, directory: h.directory).events
        XCTAssertTrue(queued.isEmpty)
        XCTAssertEqual(relaunched.status.confirmedBalance, 125)
        XCTAssertEqual(h.profile.coins, 125, "local balance = server confirmed balance")
        XCTAssertEqual(relaunched.status.pendingCoins, 0)
    }

    func testErrorDispositionsFollowTheContract() async {
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("duplicate")), .success)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("already_claimed")), .success)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("already_owned")), .success)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("rate_limited")), .retry)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("economy_disabled")), .retry)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("legacy_review_required")), .drop,
                       "terminal-with-message, no retry storm")
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("duel_score_pending")), .retry)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("duel_not_found")), .drop)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .network), .retry)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("Could not find the function")), .retry,
                       "unknown codes keep the earned event")
        for code in ["implausible_result", "invalid_payload", "claim_limit", "item_unavailable", "insufficient_coins"] {
            XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server(code)), .drop, code)
        }
        XCTAssertEqual(EconomyErrorPolicy.backoff(attempts: 1), 5)
        XCTAssertEqual(EconomyErrorPolicy.backoff(attempts: 3), 20)
        XCTAssertEqual(EconomyErrorPolicy.backoff(attempts: 40), 3_600)

        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        h.service.recordGrant(.achievement(id: "a"), legacyCoins: 1, countsTowardTotalEarned: false, profile: &profile)
        h.service.recordGrant(.achievement(id: "b"), legacyCoins: 1, countsTowardTotalEarned: false, profile: &profile)
        h.service.recordGrant(.achievement(id: "c"), legacyCoins: 1, countsTowardTotalEarned: false, profile: &profile)
        h.remote.submitResponses = [.failure(.server("duplicate")), .failure(.server("implausible_result")),
                                    .failure(.server("rate_limited"))]
        await h.service.flush(reason: .manual)
        let left = EconomyOutbox(userID: userA, directory: h.directory).events
        XCTAssertEqual(left.count, 1, "duplicate removed, terminal dropped, retryable kept")
        XCTAssertEqual(left.first?.payload["achievement_id"], .string("c"))
    }

    func testOutboxIsNeverReplayedUnderAnotherAccount() async {
        let h = EconomyHarness(authoritative: true, userID: userA)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        let keyA = h.service.recordGrant(.achievement(id: "games_1"), legacyCoins: 25,
                                         countsTowardTotalEarned: false, profile: &profile)!
        h.userID = userB
        h.service.accountDidChange()
        await h.service.flush(reason: .manual)
        XCTAssertTrue(h.remote.submitted.isEmpty, "user A's event is not sent while B is signed in")
        XCTAssertEqual(h.service.status.pendingCoins, 0, "B does not see A's pending coins")

        // Switch mid-flight: the response must not touch B's balance.
        h.userID = userA
        h.service.accountDidChange()
        h.remote.onSubmit = { _ in h.userID = userB }
        h.remote.submitResponses = [.success(.init(status: "applied", balance: 999))]
        h.remote.state.confirmedBalance = 7   // B's own server balance
        h.profile.coins = 7
        await h.service.flush(reason: .manual)
        XCTAssertEqual(h.remote.submitted.map(\.eventKey), [keyA])
        XCTAssertEqual(h.profile.coins, 7, "A's response (999) never lands on B")
        XCTAssertEqual(h.service.status.confirmedBalance, 7)
    }

    func testSpendingUsesConfirmedBalanceOnly() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        h.profile.coins = 200
        h.remote.state.confirmedBalance = 200
        await h.service.refreshConfirmedBalance()
        var profile = h.profile
        h.service.recordGrant(.gameplay(sampleFacts()), legacyCoins: 900, countsTowardTotalEarned: false, profile: &profile)
        XCTAssertEqual(h.service.status.pendingCoins, 900)
        XCTAssertEqual(h.service.spendableBalance(profile: h.profile), 200, "pending coins are not spendable")

        let dragon = ShopItem.item(id: "avatar_dragon")!
        XCTAssertGreaterThan(dragon.price, 200)
        XCTAssertLessThanOrEqual(dragon.price, 200 + 900, "affordable only if pending counted")
        let denied = await h.service.purchaseItem(dragon)
        XCTAssertFalse(denied)
        XCTAssertTrue(h.remote.purchases.isEmpty, "not sent without confirmed coins")

        h.remote.purchaseResponse = .success(.init(status: "applied", balance: 125, itemID: "fx_ripple"))
        let ripple = ShopItem.item(id: "fx_ripple")!
        XCTAssertLessThanOrEqual(ripple.price, 200)
        let ok = await h.service.purchaseItem(ripple)
        XCTAssertTrue(ok)
        XCTAssertEqual(h.profile.coins, 125)
        XCTAssertTrue(h.profile.ownedItems.contains("fx_ripple"))
    }

    func testWheelLandsOnServerSegmentAndDailyUsesServer() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        h.remote.submitResponses = [.success(.init(status: "applied", granted: 40, balance: 40, segmentIndex: 7))]
        let spin = await h.service.spinWheel()
        XCTAssertEqual(spin, .landed(segmentIndex: 7, coins: 40))
        XCTAssertEqual(h.remote.submitted.last?.source, .wheel)
        XCTAssertEqual(h.remote.submitted.last?.payload, [:])
        XCTAssertEqual(h.profile.coins, 40)

        h.remote.submitResponses = [.failure(.server("already_claimed"))]
        let again = await h.service.spinWheel()
        XCTAssertEqual(again, .alreadyClaimed)

        // A duplicate event_key answers with the original segment.
        h.remote.submitResponses = [.success(.init(status: "duplicate", granted: 40, balance: 40, segmentIndex: 7))]
        let replay = await h.service.spinWheel()
        XCTAssertEqual(replay, .landed(segmentIndex: 7, coins: 40))

        h.remote.submitResponses = [.failure(.network)]
        let offline = await h.service.spinWheel()
        XCTAssertEqual(offline, .queued)
        XCTAssertEqual(EconomyOutbox(userID: userA, directory: h.directory).events.map(\.source), [.wheel])

        var serverProfile = PlayerProfile()
        serverProfile.dailyRewardStreak = 1
        serverProfile.dailyRewardLastClaim = "2026-11-25"
        h.remote.serverProfile = serverProfile
        h.remote.submitResponses = [.success(.init(status: "applied", granted: 10, balance: 50))]
        let daily = await h.service.claimDailyReward(estimatedCoins: 10)
        XCTAssertEqual(daily, .claimed(coins: 10))
        XCTAssertEqual(h.remote.submitted.last?.source, .dailyReward)
        XCTAssertEqual(h.profile.coins, 50)
        XCTAssertEqual(h.profile.dailyRewardLastClaim, "2026-11-25")
    }

    func testRewardedAdsUseSSVAndNeverSelfGrant() {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        h.profile.coins = 60
        h.profile.noAds = true   // Remove Ads owner

        let reference = UUID()
        let ssv = h.service.rewardedVerification(for: .doubleCoins, claimIndex: 1, referenceEventKey: reference)
        XCTAssertNotNil(ssv, "Remove Ads does not suppress optional rewarded ads")
        XCTAssertEqual(ssv?.userIdentifier, userA)
        let data = ssv.flatMap { try? JSONSerialization.jsonObject(with: Data($0.customData.utf8)) as? [String: Any] }
        XCTAssertEqual(data?["source"] as? String, "double_coins")
        XCTAssertEqual(data?["claim_index"] as? Int, 1)
        XCTAssertEqual(data?["event_key"] as? String, ssv?.eventKey.uuidString.lowercased())
        XCTAssertEqual(data?["reference_event_key"] as? String, reference.uuidString.lowercased())
        XCTAssertEqual(h.service.rewardedVerification(for: .revive, claimIndex: 3, referenceEventKey: nil)?.source, "revive")

        h.service.rewardedAdCompleted(.homeCoins, legacyCoins: 15)
        XCTAssertEqual(h.profile.coins, 60, "client never self-grants a rewarded reward")
        XCTAssertEqual(h.legacyPersists, 0)
        XCTAssertEqual(h.service.status.pendingCoins, 15)

        h.service.applyPurchasedCoins(1_000)
        XCTAssertEqual(h.profile.coins, 60, "StoreKit coins are credited by the server ledger")
        XCTAssertEqual(h.legacyPersists, 0)
    }

    func testStarterCosmeticOnlyForNewPlayersAndOnce() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        let choices = h.service.starterItemChoices(profile: h.profile).map(\.id)
        XCTAssertEqual(choices, ["theme_neon", "fx_ripple", "avatar_cool"])
        XCTAssertTrue(h.service.starterItemChoices(profile: h.profile).allSatisfy { $0.rarity == .common })

        var owner = PlayerProfile()
        owner.ownedItems = ["theme_gold", "fx_spark"]
        XCTAssertEqual(h.service.starterItemChoices(profile: owner).map(\.id), [], "existing owners are not offered a starter")

        let rejected = await h.service.claimStarterItem("theme_gold")
        XCTAssertFalse(rejected, "only configured Common starter items")
        XCTAssertTrue(h.remote.submitted.isEmpty)

        h.remote.submitResponses = [.success(.init(status: "applied", balance: 0, itemID: "fx_ripple"))]
        let claimed = await h.service.claimStarterItem("fx_ripple")
        XCTAssertTrue(claimed)
        XCTAssertEqual(h.remote.submitted.last?.source, .starterItem)
        XCTAssertEqual(h.remote.submitted.last?.payload["item_id"], .string("fx_ripple"))
        XCTAssertEqual(h.profile.ownedItems, ["fx_ripple"])
        h.profile.ownedItems = []
        XCTAssertEqual(h.service.starterItemChoices(profile: h.profile).map(\.id), [], "claimed once per account")
    }
}

// MARK: - Profile merge

@MainActor
final class EconomyProfileMergeTests: XCTestCase {
    func testAuthoritativeMergeNeverTakesMaxCoins() {
        XCTAssertEqual(AuthViewModel.mergedCoins(local: 9_000, cloud: 120, authoritative: true), 120)
        XCTAssertEqual(AuthViewModel.mergedCoins(local: 9_000, cloud: 120, authoritative: false), 9_000)
    }

    func testAuthoritativeOwnedItemsNeedEvidence() {
        let premium = ShopItem.premium.first?.id ?? "theme_glitch"
        let local = ["theme_gold", premium, "theme_neon"]
        let cloud = ["theme_neon", "fx_spark"]
        XCTAssertEqual(AuthViewModel.mergedOwnedItems(local: local, cloud: cloud, authoritative: false),
                       ["theme_gold", premium, "theme_neon", "fx_spark"])
        let authoritative = AuthViewModel.mergedOwnedItems(local: local, cloud: cloud, authoritative: true)
        XCTAssertFalse(authoritative.contains("theme_gold"), "local-only coin item has no server evidence")
        XCTAssertTrue(authoritative.contains(premium) == (ShopItem.item(id: premium)?.isPremium == true))
        XCTAssertTrue(authoritative.contains("theme_neon"))
        XCTAssertTrue(authoritative.contains("fx_spark"))
    }
}

// MARK: - Contract pin + season schedule

final class EconomyContractPinTests: XCTestCase {
    func testBalancedPremiumRC1MatchesContractKeys() {
        let values = EconomyConfig.balancedPremiumRC1.contractValues
        XCTAssertEqual(values["daily_rewards"] as? [Int], [10, 15, 20, 25, 30, 40, 60])
        XCTAssertEqual(values["wheel_rewards"] as? [Int], [5, 5, 10, 10, 15, 15, 20, 40])
        XCTAssertEqual(values["quest_rewards"] as? [String: Int], ["easy": 25, "medium": 45, "hard": 75])
        XCTAssertEqual(values["home_rewarded_coins"] as? Int, 15)
        XCTAssertEqual(values["season_ads_required"] as? Int, 20)
        XCTAssertEqual(values["season_coin_cycle"] as? [Int], [25, 50, 75, 100, 125])
        XCTAssertEqual(values["score_coin_divisor"] as? Int, 80)
        XCTAssertEqual(values["minimum_game_coins"] as? Int, 4)
        XCTAssertEqual(values["starter_items"] as? [String], ["theme_neon", "fx_ripple", "avatar_cool"])
        XCTAssertEqual(values["gameplay_daily_cap"] as? Int, 1_500)
        XCTAssertNil(values["active_season"], "single placeholder season replaced by the calendar rule")
        // Same JSON as season_calendar.test.sql ("season_calendar rule pinned").
        let season = values["season_calendar"] as? [String: Any]
        XCTAssertEqual(season?["anchor"] as? String, "2026-03-01")
        XCTAssertEqual(season?["length_months"] as? Int, 3)
        XCTAssertEqual(season?["id_format"] as? String, "season_<n>")
        XCTAssertEqual(season?["tiers"] as? Int, 30)
        XCTAssertEqual(season?["max_tiers_per_day"] as? Int, 15)
        XCTAssertEqual(season?["grace_hours"] as? Int, 72)
        XCTAssertEqual(EconomyConfig.legacy.seasonCalendar, EconomyConfig.balancedPremiumRC1.seasonCalendar,
                       "one calendar whatever the flag")
        XCTAssertEqual(Achievement.all.count, 36)
        XCTAssertEqual(EconomyConfig.achievementRewards.count, 36)
        XCTAssertEqual(EconomyConfig.comboBonusTable.map(\.minCombo), [20, 10, 5, 0])
        XCTAssertEqual(EconomyConfig.comboBonusTable.map(\.bonus), [8, 5, 3, 1])
        XCTAssertEqual(EconomyConfig.modeBonus[.classic], 2)
        XCTAssertEqual(EconomyConfig.modeBonus[.duel], 6)
        // Seeded in supabase/migrations/20261125130443 (economy_shop_items).
        XCTAssertEqual(EconomyConfig.balancedPremiumRC1.shopPrices.count, 23)
        XCTAssertEqual(EconomyConfig.balancedPremiumRC1.shopPrices.values.reduce(0, +), 26_300)
        XCTAssertEqual(EconomyConfig.balancedPremiumRC1.seasonCoinRewards.count, 30)
        for id in EconomyConfig.balancedPremiumRC1.starterItems {
            XCTAssertEqual(ShopItem.item(id: id)?.rarity, .common, id)
        }
        XCTAssertEqual(EconomyConfig.achievementRewards["games_1"], 25)
        XCTAssertEqual(EconomyConfig.challengeRewards["c9"]?.item, "theme_fire")
        XCTAssertEqual(EconomyConfig.challengeRewards["c1"]?.coins, 50)
    }

    func testExpiredSeasonRollsToCurrentCycle() {
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(secondsFromGMT: 0)!
            return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        }
        let s1 = SeasonSchedule.current(now: date(2026, 4, 10))
        XCTAssertEqual(s1.number, 1)
        XCTAssertEqual(s1.displayRange, "Mar 1 – May 31, 2026")
        XCTAssertEqual(s1.title, "Season 1: Neon Nights")

        let today = SeasonSchedule.current(now: date(2026, 11, 25))
        XCTAssertEqual(today.number, 3)
        XCTAssertEqual(today.id, "season_3")
        XCTAssertEqual(today.displayRange, "Sep 1 – Nov 30, 2026")
        XCTAssertTrue(today.contains(date(2026, 11, 25)))

        // The calendar rule names every season the same way the server does.
        let winter = SeasonSchedule.current(now: date(2027, 1, 15))
        XCTAssertEqual(winter.number, 4)
        XCTAssertEqual(winter.id, "season_4")
        XCTAssertEqual(winter.title, "Season 4")
        XCTAssertEqual(winter.displayRange, "Dec 1 – Feb 28, 2027")
        XCTAssertEqual(SeasonSchedule.current(now: date(2027, 3, 2)).id, "season_5")
        // A device clock before the anchor still shows Season 1 (UI only).
        XCTAssertEqual(SeasonSchedule.current(now: date(2025, 12, 1)).id, "season_1")
        XCTAssertNil(SeasonSchedule.season(at: date(2025, 12, 1)), "server parity: no season before the anchor")

        // Rolling the cycle is a pure date computation: earned tiers stay.
        var profile = PlayerProfile()
        profile.seasonTier = 12
        profile.seasonClaimedTiers = [1, 2, 3]
        _ = SeasonSchedule.current(now: date(2027, 6, 1))
        XCTAssertEqual(profile.seasonTier, 12)
        XCTAssertEqual(profile.seasonClaimedTiers, [1, 2, 3])
    }
}

// MARK: - Season calendar shared with the server

/// Mirrors supabase/tests/database/season_calendar.test.sql one-to-one: same
/// UTC instants → same ids / boundaries / claim verdicts. Change both together.
@MainActor
final class SeasonCalendarAlignmentTests: XCTestCase {
    private let rule = EconomyConfig.SeasonCalendarRule.balancedPremiumRC1

    private func t(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func describe(_ s: SeasonSchedule?) -> String? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return "\(s.id) \(f.string(from: s.startsAt)) \(f.string(from: s.endsAt))"
    }

    func testDateToSeasonTableMatchesServer() {
        let table: [(String, String?)] = [
            ("2026-03-01T00:00:00Z", "season_1 2026-03-01 2026-06-01"),
            ("2026-05-31T23:59:59Z", "season_1 2026-03-01 2026-06-01"),
            ("2026-06-01T00:00:00Z", "season_2 2026-06-01 2026-09-01"),
            ("2026-11-26T12:00:00Z", "season_3 2026-09-01 2026-12-01"),
            ("2026-11-30T23:59:59Z", "season_3 2026-09-01 2026-12-01"),
            ("2026-12-01T00:00:00Z", "season_4 2026-12-01 2027-03-01"),
            ("2027-02-28T23:59:59Z", "season_4 2026-12-01 2027-03-01"),
            ("2027-03-01T00:00:00Z", "season_5 2027-03-01 2027-06-01"),
            ("2028-02-29T12:00:00Z", "season_8 2027-12-01 2028-03-01"),
            ("2026-02-28T23:59:59Z", nil),
            ("2026-12-01T03:00:00+05:00", "season_3 2026-09-01 2026-12-01"),
        ]
        for (instant, expected) in table {
            XCTAssertEqual(describe(SeasonSchedule.season(at: t(instant), rule: rule)), expected, instant)
        }
    }

    func testClaimWindowTableMatchesServer() {
        let table: [(String, Int, String, String?)] = [
            ("season_3", 1, "2026-11-26T12:00:00Z", nil),
            ("season_3", 1, "2026-12-01T00:00:00Z", nil),
            ("season_3", 1, "2026-12-03T23:59:59Z", nil),
            ("season_3", 1, "2026-12-04T00:00:00Z", "invalid_payload"),
            ("season_4", 1, "2026-11-30T23:59:59Z", "invalid_payload"),
            ("season_4", 1, "2026-12-01T00:00:00Z", nil),
            ("season_2", 1, "2026-11-26T12:00:00Z", "invalid_payload"),
            ("season_2", 1, "2026-09-02T00:00:00Z", nil),
            ("season_1_neon_nights", 1, "2026-12-15T00:00:00Z", "invalid_payload"),
        ]
        for (id, tier, instant, expected) in table {
            XCTAssertEqual(SeasonSchedule.claimVerdict(seasonID: id, tier: tier, now: t(instant), rule: rule),
                           expected, "\(id) tier \(tier) @ \(instant)")
        }
        // Tier bound + per-season claim rate: (claims already made for this
        // season id) + 1 ≤ (days since that season began + 1) × maxTiersPerDay.
        let rate: [(String, Int, String, Int, String?)] = [
            ("season_4", 26, "2026-12-01T00:00:00Z", 0, nil),   // carried over: tier 25 → 26 on Dec 1
            ("season_4", 30, "2026-12-01T10:00:00Z", 14, nil),
            ("season_4", 16, "2026-12-01T10:00:00Z", 15, "implausible_result"),
            ("season_4", 16, "2026-12-02T00:00:00Z", 15, nil),
            ("season_4", 5, "2026-12-02T00:00:00Z", 30, "implausible_result"),
            ("season_3", 30, "2026-12-02T00:00:00Z", 29, nil),
            ("season_3", 31, "2026-11-26T12:00:00Z", 0, "invalid_payload"),
        ]
        for (id, tier, instant, claimed, expected) in rate {
            XCTAssertEqual(SeasonSchedule.claimVerdict(seasonID: id, tier: tier, claimedThisSeason: claimed,
                                                       now: t(instant), rule: rule),
                           expected, "\(id) tier \(tier) claimed \(claimed) @ \(instant)")
        }
        // Owner-tunable values behave like the server's.
        let grace24 = EconomyConfig.SeasonCalendarRule(anchor: "2026-03-01", lengthMonths: 3, idFormat: "season_<n>",
                                                      tiers: 30, maxTiersPerDay: 15, graceHours: 24)
        XCTAssertNil(SeasonSchedule.claimVerdict(seasonID: "season_3", tier: 1, now: t("2026-12-01T23:59:59Z"),
                                                 rule: grace24))
        XCTAssertEqual(SeasonSchedule.claimVerdict(seasonID: "season_3", tier: 1, now: t("2026-12-02T00:00:00Z"),
                                                   rule: grace24), "invalid_payload")
        let monthly = EconomyConfig.SeasonCalendarRule(anchor: "2026-03-01", lengthMonths: 1, idFormat: "season_<n>",
                                                      tiers: 30, maxTiersPerDay: 15, graceHours: 24)
        XCTAssertEqual(describe(SeasonSchedule.season(at: t("2026-11-26T12:00:00Z"), rule: monthly)),
                       "season_9 2026-11-01 2026-12-01")
        let malformed = EconomyConfig.SeasonCalendarRule(anchor: "2026-03-15", lengthMonths: 1, idFormat: "season_<n>",
                                                        tiers: 30, maxTiersPerDay: 15, graceHours: 24)
        XCTAssertEqual(SeasonSchedule.claimVerdict(seasonID: "season_9", tier: 1, now: t("2026-11-26T12:00:00Z"),
                                                   rule: malformed), "invalid_payload")
    }

    private func seasonEvent(_ id: String) -> EconomyEvent {
        EconomyEvent(eventKey: UUID(), source: .seasonTier,
                     payload: ["season_id": .string(id), "tier": .int(3)], createdAt: t("2026-11-30T20:00:00Z"))
    }

    func testRejectedSeasonClaimIsDroppedOnlyOutsideTheGraceWindow() {
        let refused = EconomyRemoteFailure.server("invalid_payload")
        // Previous season inside the grace window, or a season the server has
        // not opened yet (client clock ahead): kept, never blocks the outbox.
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: refused, event: seasonEvent("season_3"),
                                                      now: t("2026-12-02T00:00:00Z"), rule: rule), .retryNonBlocking)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: refused, event: seasonEvent("season_4"),
                                                      now: t("2026-12-01T00:00:05Z"), rule: rule), .retryNonBlocking)
        // Outside the window: terminal, dropped like before.
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: refused, event: seasonEvent("season_3"),
                                                      now: t("2026-12-04T00:00:00Z"), rule: rule), .drop)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: refused, event: seasonEvent("season_1_neon_nights"),
                                                      now: t("2026-12-02T00:00:00Z"), rule: rule), .drop)
        // Other codes and other sources are unchanged.
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("implausible_result"), event: seasonEvent("season_3"),
                                                      now: t("2026-11-30T21:00:00Z"), rule: rule), .drop)
        let achievement = EconomyEvent(eventKey: UUID(), source: .achievement,
                                       payload: ["achievement_id": .string("games_1"), "season_id": .string("season_3")],
                                       createdAt: t("2026-11-30T20:00:00Z"))
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: refused, event: achievement,
                                                      now: t("2026-11-30T21:00:00Z"), rule: rule), .drop)
        XCTAssertEqual(EconomyErrorPolicy.disposition(for: .server("already_claimed"), event: seasonEvent("season_3"),
                                                      now: t("2026-12-10T00:00:00Z"), rule: rule), .success)
    }

    func testFlagOnFlushKeepsInGraceSeasonClaimAndDropsExpiredOne() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        h.clock = t("2026-11-30T23:00:00Z")
        let season = SeasonSchedule.current(now: h.clock, rule: rule)
        XCTAssertEqual(season.id, "season_3")
        let key = h.service.recordGrant(.seasonTier(seasonID: season.id, tier: 3), legacyCoins: 75,
                                        countsTowardTotalEarned: true, profile: &profile)!
        h.service.recordGrant(.achievement(id: "games_1"), legacyCoins: 25,
                              countsTowardTotalEarned: false, profile: &profile)
        XCTAssertEqual(EconomyOutbox(userID: userA, directory: h.directory).events.first?.payload["season_id"],
                       .string("season_3"))

        // Delivered after the boundary but inside the grace window: a refusal
        // keeps the tier and does not hold up the achievement behind it.
        h.clock = t("2026-12-01T00:00:10Z")
        h.remote.submitResponses = [.failure(.server("invalid_payload")),
                                    .success(.init(status: "applied", granted: 25, balance: 25))]
        await h.service.flush(reason: .manual)
        var left = EconomyOutbox(userID: userA, directory: h.directory).events
        XCTAssertEqual(left.map(\.eventKey), [key], "season claim kept, achievement delivered")
        XCTAssertEqual(h.remote.submitted.count, 2)

        // Retry after the grace window: the same refusal is terminal.
        h.clock = t("2026-12-04T00:00:00Z")
        h.remote.submitResponses = [.failure(.server("invalid_payload"))]
        await h.service.flush(reason: .manual)
        left = EconomyOutbox(userID: userA, directory: h.directory).events
        XCTAssertTrue(left.isEmpty, "outside the grace window the claim is dropped")
        XCTAssertEqual(h.remote.submitted.last?.eventKey, key, "same event key on retry")
    }

    func testFlagOffSeasonClaimIsLocalAndUnchanged() {
        let h = EconomyHarness(authoritative: false)
        defer { h.cleanUp() }
        var profile = PlayerProfile()
        profile.coins = 100
        profile.seasonTier = 12
        profile.seasonClaimedTiers = [1, 2]
        let season = SeasonSchedule.current(now: t("2026-11-26T12:00:00Z"))
        XCTAssertEqual(season.id, "season_3")
        let key = h.service.recordGrant(.seasonTier(seasonID: season.id, tier: 3), legacyCoins: 75,
                                        countsTowardTotalEarned: true, profile: &profile)
        XCTAssertNil(key)
        XCTAssertEqual(profile.coins, 175, "flag OFF credits the tier locally exactly as before")
        XCTAssertEqual(profile.stats.totalCoinsEarned, 75)
        XCTAssertEqual(profile.seasonTier, 12, "earned tiers are never reset")
        XCTAssertEqual(profile.seasonClaimedTiers, [1, 2])
        XCTAssertEqual(h.remote.totalCalls, 0, "no network with flag OFF")
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory.path), "no outbox with flag OFF")
    }
}
