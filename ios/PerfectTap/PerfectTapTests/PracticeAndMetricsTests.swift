import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// 1.2.0: Practice Session protocol, per-tap timing statistics, local store,
/// Effects setting, Minimal-mode rename.
@MainActor
final class PracticeAndMetricsTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "pt_practice_duration")
        super.tearDown()
    }

    // MARK: Signed error

    func testSignedErrorSignAndScale() {
        // Moving right, before centre → early (negative).
        XCTAssertEqual(SessionMetrics.signedErrorMs(position: 0.45, direction: 1, speed: 1.2), -60, accuracy: 1e-9)
        // Moving right, past centre → late.
        XCTAssertEqual(SessionMetrics.signedErrorMs(position: 0.55, direction: 1, speed: 1.2), 60, accuracy: 1e-9)
        // Moving left, right of centre → early.
        XCTAssertEqual(SessionMetrics.signedErrorMs(position: 0.55, direction: -1, speed: 1.2), -60, accuracy: 1e-9)
        XCTAssertEqual(SessionMetrics.signedErrorMs(position: 0.5, direction: 1, speed: 1.2), 0, accuracy: 1e-9)
        // Agrees with the EARLY/LATE hint the HUD shows.
        XCTAssertEqual(TimingEngine.timing(position: 0.45, direction: 1), .early)
        XCTAssertEqual(TimingEngine.timing(position: 0.55, direction: -1), .early)
    }

    // MARK: Statistics

    func testComputeStatistics() throws {
        let errors: [Double] = [-10, 10, -10, 10]
        let m = try XCTUnwrap(SessionMetrics.compute(mode: .practice, protocolKey: "k", durationSec: 60,
                                                     errorsMs: errors, hits: 3, perfects: 2, completed: true))
        XCTAssertEqual(m.taps, 4)
        XCTAssertEqual(m.meanSignedErrorMs, 0, accuracy: 1e-9)
        XCTAssertEqual(m.meanAbsErrorMs, 10, accuracy: 1e-9)
        XCTAssertEqual(m.sdErrorMs, (400.0 / 3).squareRoot(), accuracy: 1e-9)   // sample SD
        XCTAssertEqual(m.hitRate, 0.75, accuracy: 1e-9)
        XCTAssertEqual(m.lapses, 0, "fewer than 10 taps: no lapse count")
        XCTAssertNil(SessionMetrics.compute(mode: .practice, protocolKey: "k", durationSec: 1,
                                            errorsMs: [], hits: 0, perfects: 0, completed: false))
    }

    func testLapsesCountOutliers() throws {
        var errors = Array(repeating: 5.0, count: 10) + Array(repeating: -5.0, count: 10)
        errors.append(400)   // one very late tap
        let m = try XCTUnwrap(SessionMetrics.compute(mode: .practice, protocolKey: "k", durationSec: 60,
                                                     errorsMs: errors, hits: 20, perfects: 20, completed: true))
        XCTAssertEqual(m.lapses, 1)
    }

    // MARK: Practice protocol

    func testPracticeModeIsFixedUnrankedAndLifeless() {
        let m = GameMode.practice
        XCTAssertNil(m.initialLives)
        XCTAssertFalse(m.supportsRevive)
        XCTAssertFalse(m.isRanked, "must not hit the server leaderboard (no mode_rules row)")
        XCTAssertFalse(m.earnCoins)
        XCTAssertTrue(m.hasTimer)
        XCTAssertTrue(m.hasQuitButton)
        XCTAssertEqual(m.initialSpeed, PracticeSession.speed)
        XCTAssertTrue(GameMode.selectableModes.contains(.practice))
        XCTAssertEqual(GameConfig.maxScoreForMode(.practice), 0)
    }

    func testPracticeDurationSettingAndProtocolKey() {
        XCTAssertEqual(PracticeSession.selectedDuration, 180)
        PracticeSession.selectedDuration = 60
        XCTAssertEqual(GameMode.practice.timerDuration, 60)
        UserDefaults.standard.set(999, forKey: "pt_practice_duration")
        XCTAssertEqual(PracticeSession.selectedDuration, 180, "unknown values fall back to the default")
        XCTAssertEqual(PracticeSession.protocolKey(duration: 300), "practice:300:1.20")
    }

    /// Speed never changes during a Practice Session and the round ends
    /// exactly when its timer does, with metrics attached.
    func testPracticeRoundKeepsPaceAndReportsMetrics() {
        PracticeSession.selectedDuration = 60
        let vm = GameViewModel()
        var result: GameResult?
        vm.onGameFinished = { result = $0 }
        vm.setup(mode: .practice, profile: PlayerProfile())
        vm.cleanup()
        var t: CFTimeInterval = 100
        for _ in 0..<4 { vm.step(now: t); t += 1 }
        XCTAssertEqual(vm.phase, .playing)

        // Tap ~3×/s for 61 s at 60 fps.
        var frame = 0
        while vm.phase == .playing && frame < 61 * 60 {
            t += 1.0 / 60.0
            vm.step(now: t)
            if frame % 20 == 0 { vm.handleTap(touchTimestamp: t) }
            frame += 1
        }
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(vm.lives, 999, "no lives in practice")
        let metrics = result?.metrics
        XCTAssertNotNil(metrics)
        XCTAssertEqual(metrics?.protocolKey, "practice:60:1.20")
        XCTAssertEqual(metrics?.completed, true)
        XCTAssertGreaterThan(metrics?.taps ?? 0, 150)
        XCTAssertEqual(metrics?.durationSec ?? 0, 60, accuracy: 0.1)
        // Every tap error is within half a sweep at the fixed pace.
        XCTAssertLessThanOrEqual(metrics?.meanAbsErrorMs ?? .infinity, 600)
    }

    func testQuitMarksSessionIncomplete() {
        let vm = GameViewModel()
        var result: GameResult?
        vm.onGameFinished = { result = $0 }
        vm.setup(mode: .practice, profile: PlayerProfile())
        vm.cleanup()
        var t: CFTimeInterval = 100
        for _ in 0..<4 { vm.step(now: t); t += 1 }
        for _ in 0..<30 { t += 1.0 / 60.0; vm.step(now: t) }
        vm.handleTap(touchTimestamp: t)
        vm.quit()
        XCTAssertEqual(result?.metrics?.completed, false)
        XCTAssertEqual(result?.coinsEarned, 0)
    }

    // MARK: Store

    func testStoreIsBoundedNewestFirstAndPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("metrics-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SessionMetricsStore(fileURL: url)
        for i in 0..<(SessionMetricsStore.capacity + 5) {
            let m = try XCTUnwrap(SessionMetrics.compute(mode: .practice, protocolKey: "p\(i % 2)", durationSec: Double(i),
                                                         errorsMs: [1, 2], hits: 2, perfects: 1, completed: true))
            store.record(m)
        }
        store.waitForWrites()
        XCTAssertEqual(store.all().count, SessionMetricsStore.capacity)
        XCTAssertEqual(store.all().first?.durationSec, Double(SessionMetricsStore.capacity + 4))
        XCTAssertTrue(store.sessions(protocolKey: "p0").allSatisfy { $0.protocolKey == "p0" })

        let reloaded = SessionMetricsStore(fileURL: url)
        XCTAssertEqual(reloaded.all().count, SessionMetricsStore.capacity)
        reloaded.clearAll()
        reloaded.waitForWrites()
        XCTAssertTrue(SessionMetricsStore(fileURL: url).all().isEmpty)
    }

    // MARK: Effects / naming

    func testReduceMotionCapsEffects() {
        XCTAssertEqual(EffectsLevel.full.effective(reduceMotion: true), .reduced)
        XCTAssertEqual(EffectsLevel.off.effective(reduceMotion: true), .off)
        XCTAssertEqual(EffectsLevel.full.effective(reduceMotion: false), .full)
        XCTAssertTrue(EffectsLevel.full.showsParticles)
        XCTAssertFalse(EffectsLevel.reduced.showsParticles)
        XCTAssertEqual(EffectsLevel.off.glowStrength, 0)
    }

    func testModeNamesAvoidAttentionClaims() {
        XCTAssertEqual(GameMode.focus.rawValue, "focus", "raw value kept for saved data")
        for mode in GameMode.allCases {
            let text = (mode.displayName + " " + mode.description + " " + (mode.tip ?? "")).lowercased()
            for word in ["focus", "attention", "adhd", "concentrat", "therap", "treat"] {
                XCTAssertFalse(text.contains(word), "\(mode): '\(word)' in player-facing copy")
            }
        }
    }

    func testPracticeErrorFormatting() {
        XCTAssertEqual(GameView.formatError(-8.4), "8 ms EARLY")
        XCTAssertEqual(GameView.formatError(12.6), "13 ms LATE")
        XCTAssertEqual(GameView.formatError(0.3), "ON TIME")
        XCTAssertEqual(PracticeSummary.biasText(-4.2), "Average 4 ms early")
    }
}
