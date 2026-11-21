import XCTest
import Combine
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Regression tests for the 1.1.1 stability fixes (docs/perf, hotfix/1.1.1-stability).
/// Each test fails on the 1.1.0 (4) code path it guards.
@MainActor
final class StabilityRegressionTests: XCTestCase {

    private var bag = Set<AnyCancellable>()

    override func tearDown() async throws {
        bag.removeAll()
        AdManager.shared.isGameplayActive = false
    }

    // MARK: Round end → Game Over navigation (H1)

    /// 1.1.0 popped to root (path = []) and pushed 50 ms later, which briefly
    /// re-mounted HomeView. The stack must go game → gameOver in one change.
    func testRoundEndReplacesStackWithoutExposingHome() {
        let router = AppRouter()
        router.push(.game(.classic))
        var seen: [[AppRoute]] = []
        router.$path.dropFirst().sink { seen.append($0) }.store(in: &bag)

        let result = GameResult(score: 1, maxCombo: 0, mode: .classic, coinsEarned: 0, xpEarned: 0,
                                leveledUp: nil, newAchievements: [], isNewBest: false)
        router.replaceStack(with: [.gameOver(result)])

        XCTAssertEqual(seen.count, 1, "exactly one navigation change")
        XCTAssertFalse(seen.contains { $0.isEmpty }, "Home (empty path) must never be shown in between")
        XCTAssertEqual(router.path, [.gameOver(result)])
        XCTAssertFalse(router.isGameOnStack)
    }

    func testIsGameOnStack() {
        let router = AppRouter()
        XCTAssertFalse(router.isGameOnStack)
        router.push(.modeSelect)
        router.push(.game(.timed))
        XCTAssertTrue(router.isGameOnStack)
    }

    // MARK: Profile cache (repeated main-thread JSON decodes)

    func testProfileCacheStaysInSyncWithSaveAndClear() {
        var p = PlayerProfile()
        p.coins = 4321
        p.save()
        XCTAssertEqual(PlayerProfile.load()?.coins, 4321)

        // A fresh read from UserDefaults gives the same data.
        PlayerProfile.resetCacheForTesting()
        XCTAssertEqual(PlayerProfile.load()?.coins, 4321)

        // Mutating a loaded copy must not change the cache until saved.
        var copy = PlayerProfile.load()!
        copy.coins = 1
        XCTAssertEqual(PlayerProfile.load()?.coins, 4321)
        copy.save()
        XCTAssertEqual(PlayerProfile.load()?.coins, 1)

        PlayerProfile.clearSaved()
        XCTAssertNil(PlayerProfile.load())
        PlayerProfile.resetCacheForTesting()
        XCTAssertNil(PlayerProfile.load(), "clearSaved also removes the persisted copy")
    }

    // MARK: Timed HUD publishes (whole GameView re-render per publish)

    func testTimedModePublishesTimeLeftOncePerDisplayedSecond() {
        let vm = GameViewModel()
        vm.setup(mode: .timed, profile: PlayerProfile())
        vm.cleanup()
        var publishes = 0
        vm.$timeLeft.dropFirst().sink { _ in publishes += 1 }.store(in: &bag)

        var t: CFTimeInterval = 100
        for _ in 0..<4 { vm.step(now: t); t += 1 }     // countdown → playing
        XCTAssertEqual(vm.phase, .playing)
        for _ in 0..<(60 * 5) { t += 1.0 / 60.0; vm.step(now: t) }   // 5 s of play at 60 fps

        // 1.1.0 published every ~0.09 s (~55 times in 5 s).
        XCTAssertLessThanOrEqual(publishes, 6)
        XCTAssertGreaterThanOrEqual(publishes, 4)
        vm.quit()
    }

    // MARK: Frozen clock after a full-screen cover (M4)

    func testGameResumesAfterViewReappearsWithStoppedClock() {
        let vm = GameViewModel()
        vm.setup(mode: .classic, profile: PlayerProfile())
        var t: CFTimeInterval = 100
        vm.cleanup()
        for _ in 0..<4 { vm.step(now: t); t += 1 }
        XCTAssertEqual(vm.phase, .playing)

        // A cover made GameView disappear → cleanup() stopped the display link.
        vm.cleanup()
        XCTAssertTrue(vm.needsLoopRestart, "unfinished round with no clock = frozen screen")

        vm.resumeAfterViewReappeared()
        XCTAssertFalse(vm.needsLoopRestart)
        XCTAssertEqual(vm.phase, .countdown(3), "mid-play resume uses the short 3-2-1")
        vm.cleanup()
        for _ in 0..<4 { vm.step(now: t); t += 1 }
        XCTAssertEqual(vm.phase, .playing)
        vm.quit()
        XCTAssertFalse(vm.needsLoopRestart, "finished rounds never restart")
    }

    // MARK: Mirror difficulty must not depend on frame rate

    func testMirrorFlipProbabilityIsFrameRateIndependent() {
        let p = 0.02
        XCTAssertEqual(GameViewModel.mirrorFlipProbability(perFrameAt60Hz: p, delta: 1.0 / 60.0), p, accuracy: 1e-12)
        // Two 120 Hz frames must equal one 60 Hz frame.
        let q = GameViewModel.mirrorFlipProbability(perFrameAt60Hz: p, delta: 1.0 / 120.0)
        XCTAssertEqual(1 - (1 - q) * (1 - q), p, accuracy: 1e-12)
        // A long (dropped) frame covers proportionally more time.
        XCTAssertGreaterThan(GameViewModel.mirrorFlipProbability(perFrameAt60Hz: p, delta: 0.1), p)
        XCTAssertEqual(GameViewModel.mirrorFlipProbability(perFrameAt60Hz: p, delta: 0), 0)
    }

    // MARK: Ad reloads wait for the round to end (M3)

    func testAdReloadIsDeferredWhileGameplayIsActive() {
        let ads = AdManager.shared
        ads.isGameplayActive = true
        var loaded = 0
        ads.loadWhenIdle("test.rewarded") { loaded += 1 }
        XCTAssertEqual(loaded, 0, "no SDK load during a round")
        ads.isGameplayActive = false
        XCTAssertEqual(loaded, 1, "runs when the round ends")
    }

    func testInterstitialReloadWaitsForNextRoundEnd() {
        let ads = AdManager.shared
        ads.isGameplayActive = false
        var loaded = 0
        ads.loadWhenIdle("test.interstitial", untilRoundEnds: true) { loaded += 1 }
        XCTAssertEqual(loaded, 0)
        ads.isGameplayActive = true     // next round starts — still not loaded
        XCTAssertEqual(loaded, 0)
        ads.isGameplayActive = false    // round ends
        XCTAssertEqual(loaded, 1)
    }

    func testRoundLifecycleDrivesAdGameplayFlag() {
        let vm = GameViewModel()
        vm.setup(mode: .classic, profile: PlayerProfile())
        XCTAssertTrue(AdManager.shared.isGameplayActive)
        vm.quit()
        XCTAssertFalse(AdManager.shared.isGameplayActive)
        vm.cleanup()
    }

    // MARK: Consent prompts never cover a running round (M4)

    func testConsentFlowDoesNotPromptWhileBlockedAndRetriesLater() async {
        let env = FakeConsentEnvironment(tracking: .notDetermined, answer: .denied)
        let manager = ConsentManager(environment: env)
        var blocked = true
        manager.isPresentationBlocked = { blocked }

        await manager.gatherConsentIfNeeded()
        XCTAssertFalse(env.calls.contains("presentForm"))
        XCTAssertFalse(env.calls.contains("requestATT"))
        XCTAssertFalse(env.calls.contains("apply"))

        blocked = false
        await manager.gatherConsentIfNeeded()
        XCTAssertTrue(env.calls.contains("presentForm"))
        XCTAssertTrue(env.calls.contains("requestATT"))
        XCTAssertTrue(env.calls.contains("apply"))
    }
}
