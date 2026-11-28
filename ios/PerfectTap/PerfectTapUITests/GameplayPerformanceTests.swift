import XCTest

/// Reproducible gameplay workload for frame-pacing measurements.
///
/// The app runs with `-PTPerfProbe` (DEBUG-only frame monitor, writes
/// `Documents/perf-probe.json`), `-PTUITestNoAds` and
/// `-PTUITestOfflineBackend` (no network, nothing written to the real
/// Supabase project). Run through `scripts/perf-run.sh`, which uninstalls the
/// app first so every run starts from the same state and then copies the probe
/// JSON out of the simulator container.
///
/// Workload (identical for every build being compared):
///  1. Classic ×3 in a row via PLAY AGAIN (round-end → game-over → new game path)
///  2. Timed: a full 60 s round
///  3. Endless with a background/foreground transition mid-round
///
/// Gameplay taps use a precomputed screen coordinate so XCUITest does not
/// re-query the accessibility tree on every tap (those queries run on the
/// app's main thread and would pollute the measurement).
final class GameplayPerformanceTests: XCTestCase {

    private let app = XCUIApplication()
    private var tapPoint: XCUICoordinate?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_gameplay_workload() throws {
        app.launchArguments += ["-PTPerfProbe", "-PTUITestNoAds", "-PTUITestOfflineBackend"]
        // Optional premium skin for the run (TEST_RUNNER_PT_PERF_THEME=glitch).
        if let theme = ProcessInfo.processInfo.environment["PT_PERF_THEME"], !theme.isEmpty {
            app.launchArguments += ["-PTForceTheme", theme]
        }
        app.launch()
        completeOnboardingIfNeeded()
        dismissTutorialIfNeeded()
        XCTAssertTrue(app.buttons["PLAY"].waitForExistence(timeout: 20), "Home not reached")

        // 1. Classic, then PLAY AGAIN twice.
        XCTAssertTrue(openMode("CLASSIC"))
        playUntilGameOver(maxSeconds: 45)
        for _ in 0..<2 {
            let again = app.buttons["PLAY AGAIN"]
            XCTAssertTrue(again.waitForExistence(timeout: 8), "PLAY AGAIN missing")
            again.tap()
            playUntilGameOver(maxSeconds: 45)
        }
        goHome()

        // 2. Timed — full 60 s.
        XCTAssertTrue(openMode("TIMED"))
        playUntilGameOver(maxSeconds: 80)
        goHome()

        // 3. Endless with background / foreground mid-round.
        XCTAssertTrue(openMode("ENDLESS"))
        playFor(seconds: 8)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        playUntilGameOver(maxSeconds: 60)
        goHome()

        // Let the probe flush (every 2 s).
        sleep(4)
    }

    // MARK: - Gameplay

    private func resolveTapPoint() -> XCUICoordinate? {
        let button = app.buttons["TAP!"]
        guard button.waitForExistence(timeout: 10) else { return nil }
        let frame = button.frame
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        return origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }

    private func playFor(seconds: TimeInterval) {
        guard let point = resolveTapPoint() else { return }
        tapPoint = point
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            point.tap()
        }
    }

    /// Taps steadily; every ~3 s checks (one query) whether the round ended.
    /// A revive modal is declined so every build follows the same path.
    private func playUntilGameOver(maxSeconds: TimeInterval) {
        guard let point = tapPoint ?? resolveTapPoint() else {
            XCTFail("TAP! not found"); return
        }
        tapPoint = point
        let end = Date().addingTimeInterval(maxSeconds)
        var lastCheck = Date()
        while Date() < end {
            point.tap()
            if Date().timeIntervalSince(lastCheck) > 3 {
                lastCheck = Date()
                if app.staticTexts["CONTINUE?"].exists {
                    app.buttons["Give Up"].tap()
                }
                if app.buttons["HOME"].exists { break }
            }
        }
        if !app.buttons["HOME"].waitForExistence(timeout: 70) {
            // Self-paced modes can outlast the budget: quit cleanly.
            if app.buttons["QUIT"].exists {
                app.buttons["QUIT"].tap()
                app.alerts.buttons["Quit"].tap()
            }
            XCTAssertTrue(app.buttons["HOME"].waitForExistence(timeout: 10), "Game over not reached")
        }
        tapPoint = nil
    }

    private func goHome() {
        let home = app.buttons["HOME"]
        if home.waitForExistence(timeout: 5) { home.tap() }
        XCTAssertTrue(app.buttons["PLAY"].waitForExistence(timeout: 10))
    }

    // MARK: - Navigation (same helpers as ModeRuntimeQATests)

    private func openMode(_ title: String) -> Bool {
        guard app.buttons["PLAY"].waitForExistence(timeout: 12) else { return false }
        app.buttons["PLAY"].tap()
        guard app.staticTexts["SELECT MODE"].waitForExistence(timeout: 6) else { return false }
        for _ in 0..<8 {
            let card = app.buttons.containing(.staticText, identifier: title).firstMatch
            if card.exists { card.tap(); return true }
            let text = app.staticTexts[title]
            if text.exists { text.tap(); return true }
            app.swipeUp()
        }
        return false
    }

    private func completeOnboardingIfNeeded() {
        let chooseName = app.staticTexts["Choose Your Name"]
        let play = app.buttons["PLAY"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline && !chooseName.exists && !play.exists { _ = chooseName.waitForExistence(timeout: 1) }
        guard chooseName.exists else { return }
        let field = app.textFields.element(boundBy: 0)
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("perf_\(Int(Date().timeIntervalSince1970) % 100000)")
            if app.buttons["LET'S GO!"].exists { app.buttons["LET'S GO!"].tap() }
        }
    }

    private func dismissTutorialIfNeeded() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 4) { skip.tap() }
    }
}
