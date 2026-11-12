import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Transition tests for the GameViewModel phase machine, driven with
/// synthetic timestamps via `step(now:)` (no display link, no UI).
@MainActor
final class GamePhaseTests: XCTestCase {

    private var vm: GameViewModel!
    private var finishedCount = 0

    override func setUp() async throws {
        vm = GameViewModel()
        finishedCount = 0
        vm.onGameFinished = { [weak self] _ in self?.finishedCount += 1 }
    }

    override func tearDown() async throws {
        vm.cleanup()
        vm = nil
    }

    private func start(_ mode: GameMode) {
        vm.setup(mode: mode, profile: PlayerProfile())
        vm.cleanup()   // tests drive frames manually; no real display link
    }

    /// Advance through the 3-second countdown into `.playing`.
    private func runCountdown(from t: CFTimeInterval = 100) {
        vm.step(now: t)
        vm.step(now: t + 1)
        vm.step(now: t + 2)
        vm.step(now: t + 3)
    }

    func testCountdownTicksDownToPlaying() {
        start(.classic)
        XCTAssertEqual(vm.phase, .countdown(3))
        vm.step(now: 100)
        XCTAssertEqual(vm.phase, .countdown(3))
        vm.step(now: 101)
        XCTAssertEqual(vm.phase, .countdown(2))
        vm.step(now: 102)
        XCTAssertEqual(vm.phase, .countdown(1))
        vm.step(now: 103)
        XCTAssertEqual(vm.phase, .playing)
    }

    /// Regression: the countdown used to keep running in the background.
    func testCountdownFreezesWhileSuspended() {
        start(.classic)
        vm.step(now: 100)
        vm.step(now: 101)
        XCTAssertEqual(vm.phase, .countdown(2))

        vm.appDidMoveToBackground()
        vm.step(now: 150)
        XCTAssertEqual(vm.phase, .countdown(2))

        vm.appDidBecomeActive()
        vm.step(now: 500)                     // first frame after resume: delta 0
        XCTAssertEqual(vm.phase, .countdown(2))
        vm.step(now: 501)
        XCTAssertEqual(vm.phase, .countdown(1))
    }

    /// Regression: time spent in the background must not drain the mode timer.
    func testTimerDoesNotRunWhileSuspended() {
        start(.timed)
        runCountdown()
        XCTAssertEqual(vm.phase, .playing)
        vm.step(now: 113)                     // 10s of play
        let before = vm.timeLeft

        vm.appDidMoveToBackground()
        vm.appDidBecomeActive()
        // Resuming shows a 3-2-1 first; the mode timer stays frozen during it.
        XCTAssertEqual(vm.phase, .countdown(3))
        vm.step(now: 1_000)                   // long gap, delta 0
        XCTAssertEqual(vm.timeLeft, before, accuracy: 0.001)
        for i in 1...3 { vm.step(now: 1_000 + Double(i)) }
        XCTAssertEqual(vm.phase, .playing)
        XCTAssertEqual(vm.timeLeft, before, accuracy: 0.001)
    }

    func testTimerExpiryFinishesExactlyOnce() {
        start(.timed)
        runCountdown()
        var t: CFTimeInterval = 103
        for _ in 0..<Int(GameMode.timed.timerDuration) + 2 {
            t += 1
            vm.step(now: t)
        }
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(finishedCount, 1)
    }

    func testQuitIsIdempotent() {
        start(.classic)
        runCountdown()
        vm.quit()
        vm.quit()
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(finishedCount, 1)
    }

    func testQuitDuringCountdownFinishes() {
        start(.classic)
        vm.quit()
        XCTAssertEqual(vm.phase, .finished)
        XCTAssertEqual(finishedCount, 1)
        vm.step(now: 200)                     // nothing advances after finish
        XCTAssertEqual(vm.phase, .finished)
    }

    func testReviveTransitionsAreNoOpsOutsideRevive() {
        start(.classic)
        vm.acceptRevive()
        vm.declineRevive()
        XCTAssertEqual(vm.phase, .countdown(3))
        runCountdown()
        vm.acceptRevive()
        vm.declineRevive()
        XCTAssertEqual(vm.phase, .playing)
        XCTAssertEqual(finishedCount, 0)
        XCTAssertFalse(vm.showReviveModal)
    }

    func testTapsIgnoredOutsidePlaying() {
        start(.classic)
        vm.handleTap()
        XCTAssertEqual(vm.tapSequence, 0)
        runCountdown()
        vm.appDidMoveToBackground()
        vm.handleTap()
        XCTAssertEqual(vm.tapSequence, 0)
        vm.appDidBecomeActive()
        vm.handleTap()
        XCTAssertEqual(vm.tapSequence, 0, "taps ignored during the resume countdown")
        for i in 1...4 { vm.step(now: 500 + Double(i)) }
        XCTAssertEqual(vm.phase, .playing)
        vm.handleTap()
        XCTAssertEqual(vm.tapSequence, 1)
    }

    /// Regression: two fingers landing together scored twice.
    func testSimultaneousTapsCountOnce() {
        start(.classic)
        runCountdown()
        vm.handleTap(touchTimestamp: 200.000)
        vm.handleTap(touchTimestamp: 200.005)          // second finger, same instant
        XCTAssertEqual(vm.tapSequence, 1)
        vm.handleTap(touchTimestamp: 200.000 + GameViewModel.minTapInterval + 0.01)
        XCTAssertEqual(vm.tapSequence, 2)
    }
}
