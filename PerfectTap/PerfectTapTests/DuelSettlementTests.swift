import XCTest
@testable import PerfectTap

/// Durable duel submission + exactly-once result counting (PendingDuelStore).
@MainActor
final class DuelSettlementTests: XCTestCase {
    private let uid = "00000000-0000-4000-8000-000000000001"

    override func setUp() {
        super.setUp()
        PendingDuelStore.clear()
        OfflineBackend.shared.submitDuelScoreResult = true
        var p = PlayerProfile(); p.uid = uid; p.save()
    }

    private func run(_ id: String) -> PendingDuel {
        PendingDuel(duelId: id, role: "host", score: 500, maxCombo: 4, taps: 10, perfects: 3,
                    sessionId: nil, submitted: false, playedAt: Date().timeIntervalSince1970)
    }

    private func completedDuel(_ id: String, host: Int, guest: Int) -> Duel {
        var d = Duel(); d.id = id; d.hostId = uid; d.guestId = "other"
        d.hostScore = host; d.guestScore = guest; d.status = .completed
        return d
    }

    func testUnitTestsNeverUseARealBackend() {
        XCTAssertTrue(Backend.shared is OfflineBackend)
    }

    func testFailedSubmissionStaysQueuedForRetry() async {
        OfflineBackend.shared.submitDuelScoreResult = false
        let ok = await DuelSettlement.submit(run("d-fail"))
        XCTAssertFalse(ok)
        XCTAssertEqual(PendingDuelStore.all().first?.submitted, false, "kept for retry")

        OfflineBackend.shared.submitDuelScoreResult = true
        await DuelSettlement.settle()
        XCTAssertEqual(PendingDuelStore.all().first?.submitted, true, "retry succeeded")
    }

    func testResultCountedExactlyOnce() {
        let before = PlayerProfile.load()?.stats.duelWins ?? 0
        let duel = completedDuel("d-win", host: 900, guest: 100)
        XCTAssertTrue(DuelSettlement.recordStatsIfNeeded(duel, uid: uid))
        XCTAssertFalse(DuelSettlement.recordStatsIfNeeded(duel, uid: uid), "second call is a no-op")
        XCTAssertEqual(PlayerProfile.load()?.stats.duelWins, before + 1)
    }

    func testUnfinishedDuelIsNotCounted() {
        var duel = completedDuel("d-open", host: 900, guest: 0)
        duel.guestScore = nil; duel.status = .inProgress
        XCTAssertFalse(DuelSettlement.recordStatsIfNeeded(duel, uid: uid))
        XCTAssertFalse(PendingDuelStore.isStatsRecorded(duelId: "d-open"))
    }
}
