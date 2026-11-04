import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Pure-logic tests for the core timing mechanic. No UI, no Firebase.
final class TimingEngineTests: XCTestCase {

    // MARK: Zone geometry must match what TapBarView draws
    // TapBarView draws PERFECT as [0.5 - 0.04, 0.5 + 0.04] of the bar width,
    // GREAT as ±0.10 and GOOD as ±0.20 (same as the original web Game.jsx).

    func testCenterIsPerfect() {
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5), .perfect)
    }

    func testDrawnZoneEdgesScoreAsDrawn() {
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.039), .perfect)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 - 0.039), .perfect)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.041), .great)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.099), .great)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.101), .good)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 - 0.199), .good)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 - 0.201), .miss)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.0), .miss)
        XCTAssertEqual(TimingEngine.accuracy(at: 1.0), .miss)
    }

    /// Regression: the Swift port divided by 0.5, so a tap visibly inside the
    /// yellow GOOD band (e.g. 35% across the bar) scored MISS and cost a life.
    func testInsideVisibleGoodBandIsNotMiss() {
        XCTAssertEqual(TimingEngine.accuracy(at: 0.35), .good)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.65), .good)
    }

    func testSymmetry() {
        for d in stride(from: 0.0, through: 0.5, by: 0.005) {
            XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + d), TimingEngine.accuracy(at: 0.5 - d), "d=\(d)")
        }
    }

    func testPerfectScaleShrinksOnlyPerfect() {
        // Tiny Window starts at half the PERFECT width.
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.019, perfectScale: 0.5), .perfect)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.021, perfectScale: 0.5), .great)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.15, perfectScale: 0.5), .good)
    }

    func testStrictPerfectOnly() {
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5, strictPerfectOnly: true), .perfect)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.05, strictPerfectOnly: true), .miss)
        XCTAssertEqual(TimingEngine.accuracy(at: 0.5 + 0.15, strictPerfectOnly: true), .miss)
    }

    func testBasePoints() {
        XCTAssertEqual(TimingEngine.basePoints(for: .perfect), 100)
        XCTAssertEqual(TimingEngine.basePoints(for: .great), 70)
        XCTAssertEqual(TimingEngine.basePoints(for: .good), 40)
        XCTAssertEqual(TimingEngine.basePoints(for: .miss), 0)
    }

    // MARK: Movement

    func testAdvanceMovesAtSpeed() {
        // speed = seconds per full sweep; 0.6s at 1.2s/sweep = half the bar.
        let r = TimingEngine.advance(position: 0, direction: 1, dt: 0.6, speed: 1.2)
        XCTAssertEqual(r.position, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.direction, 1)
    }

    func testAdvanceReflectsOvershootInsteadOfClamping() {
        // 0.9 + 0.2 = 1.1 → reflects to 0.9 moving left.
        let r = TimingEngine.advance(position: 0.9, direction: 1, dt: 0.2, speed: 1.0)
        XCTAssertEqual(r.position, 0.9, accuracy: 1e-9)
        XCTAssertEqual(r.direction, -1)

        let l = TimingEngine.advance(position: 0.05, direction: -1, dt: 0.1, speed: 1.0)
        XCTAssertEqual(l.position, 0.05, accuracy: 1e-9)
        XCTAssertEqual(l.direction, 1)
    }

    func testAdvanceBackwardsIsInverseOfForwards() {
        let start = (p: 0.3, d: 1.0)
        let fwd = TimingEngine.advance(position: start.p, direction: start.d, dt: 0.012, speed: 0.4)
        let back = TimingEngine.advance(position: fwd.position, direction: fwd.direction, dt: -0.012, speed: 0.4)
        XCTAssertEqual(back.position, start.p, accuracy: 1e-9)
        XCTAssertEqual(back.direction, start.d)
    }

    func testAdvanceBackwardsAcrossEdge() {
        // At 0.98 moving left (just bounced): 30 ms back at 1s/sweep was 0.99 moving right.
        let r = TimingEngine.advance(position: 0.98, direction: -1, dt: -0.03, speed: 1.0)
        XCTAssertEqual(r.position, 0.99, accuracy: 1e-9)
        XCTAssertEqual(r.direction, 1)
    }

    func testAdvanceStaysInBoundsForHugeDelta() {
        for dt in [0.5, 1.7, 3.3, 10.0, -2.2] {
            let r = TimingEngine.advance(position: 0.42, direction: 1, dt: dt, speed: 0.15)
            XCTAssert((0...1).contains(r.position), "dt=\(dt) pos=\(r.position)")
        }
    }

    func testAdvanceIgnoresInvalidInput() {
        let r = TimingEngine.advance(position: 0.4, direction: 1, dt: .nan, speed: 1)
        XCTAssertEqual(r.position, 0.4)
        let z = TimingEngine.advance(position: 0.4, direction: 1, dt: 0.1, speed: 0)
        XCTAssertEqual(z.position, 0.4)
    }

    // MARK: Combo multipliers (documented in SETUP.md)

    func testComboMultipliers() {
        XCTAssertEqual(GameConfig.comboMultiplier(combo: 0, isComboFrenzy: false), 1)
        XCTAssertEqual(GameConfig.comboMultiplier(combo: 3, isComboFrenzy: false), 1.5)
        XCTAssertEqual(GameConfig.comboMultiplier(combo: 5, isComboFrenzy: false), 2)
        XCTAssertEqual(GameConfig.comboMultiplier(combo: 20, isComboFrenzy: true), 6)
    }

    // MARK: Contract with the server (functions/src/scoring.ts MODES[*].ranked)

    func testRankedModesMatchServer() {
        let ranked = Set(GameMode.allCases.filter(\.isRanked).map(\.rawValue))
        XCTAssertEqual(ranked, [
            "classic", "endless", "timed", "sudden_death", "combo_frenzy", "precision",
            "chaos", "mirror", "invisible_zone", "rush", "hardcore_combo", "tiny_window",
        ])
    }
}
