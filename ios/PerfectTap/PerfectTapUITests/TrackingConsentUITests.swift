import XCTest

/// Guideline 5.1.2(i): the ATT prompt must appear before any tracking, and the app must
/// keep working whatever the user answers. Runs the real system prompt (Springboard).
/// Real ads stay off (`-PTUITestNoAds`); `-PTUITestConsentFlow` enables the consent flow.
/// Uses the Debug backend like ModeRuntimeQATests (one anonymous test player).
final class TrackingConsentUITests: XCTestCase {

    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.resetAuthorizationStatus(for: .userTracking)
        app.launchArguments += ["-PTUITestNoAds", "-PTUITestConsentFlow"]
    }

    func test_deny_tracking_gameplay_still_available() {
        app.launch()
        answerTrackingPrompt(allow: false)
        reachHome()
        XCTAssertTrue(trackingStatusText().contains("Not allowed"), trackingStatusText())
    }

    func test_allow_tracking() {
        app.launch()
        answerTrackingPrompt(allow: true)
        reachHome()
        XCTAssertTrue(trackingStatusText().contains("Allowed"), trackingStatusText())
    }

    func test_prompt_not_shown_again_after_answer() {
        app.launch()
        answerTrackingPrompt(allow: false)
        app.terminate()
        app.launch()
        let again = springboard.buttons["Ask App Not to Track"].waitForExistence(timeout: 5)
        XCTAssertFalse(again, "ATT must be asked only once")
    }

    // MARK: - Helpers

    private func answerTrackingPrompt(allow: Bool) {
        let button = springboard.buttons[allow ? "Allow" : "Ask App Not to Track"]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "ATT prompt did not appear")
        button.tap()
    }

    private func reachHome() {
        if app.staticTexts["Choose Your Name"].waitForExistence(timeout: 6) {
            let field = app.textFields.element(boundBy: 0)
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.tap()
            field.typeText("qa_att_\(Int(Date().timeIntervalSince1970) % 100000)")
            app.buttons["LET'S GO!"].tap()
        }
        if app.buttons["Skip"].waitForExistence(timeout: 4) { app.buttons["Skip"].tap() }
        XCTAssertTrue(app.buttons["PLAY"].waitForExistence(timeout: 15), "Home not reached")
    }

    private func trackingStatusText() -> String {
        app.buttons["SETTINGS"].firstMatch.tap()
        let row = app.buttons["settings.privacy.tracking"]
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Privacy row missing")
        return row.label
    }
}
