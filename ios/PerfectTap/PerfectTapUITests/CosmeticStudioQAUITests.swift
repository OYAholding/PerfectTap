import XCTest

/// Independent QA (Agent E) for the Cosmetic Studio: screenshots, accessibility
/// spot checks and a cold-launch metric. ALWAYS offline: `-PTUITestOfflineBackend`
/// (no Supabase traffic, no anonymous user) and `-PTUITestNoAds`.
///
/// Screenshots are attached (lifetime .keepAlways) and exported from the
/// .xcresult into docs/cosmetics/qa/screenshots/ (docs/cosmetics/QA_REPORT.md).
/// Gameplay shots use the DEBUG-only `-PTForceCosmeticCollection <id>`.
final class CosmeticStudioQAUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["-PTUITestOfflineBackend", "-PTUITestNoAds"] + extra
        app.launch()
        completeOnboardingIfNeeded()
        dismissTutorialIfNeeded()
        XCTAssertTrue(app.buttons["PLAY"].waitForExistence(timeout: 20), "Home not reached")
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // MARK: Gameplay per collection (themed button + lives, one depleted)

    func test_gameplay_quack_attack() { gameplay("quack_attack") }
    func test_gameplay_purrfect_tap() { gameplay("purrfect_tap") }
    func test_gameplay_boom_mode() { gameplay("boom_mode") }

    private func gameplay(_ collection: String) {
        launch(["-PTForceCosmeticCollection", collection])
        XCTAssertTrue(openMode("CLASSIC"))
        let tap = app.buttons["TAP!"]
        XCTAssertTrue(tap.waitForExistence(timeout: 10))
        XCTAssertEqual(tap.frame.height, 80, accuracy: 0.5, "hit area height unchanged")
        XCTAssertEqual(tap.frame.width, app.windows.firstMatch.frame.width - 48, accuracy: 1, "full width minus 24 pt padding")
        let lives = app.otherElements["Lives"].exists ? app.otherElements["Lives"] : app.descendants(matching: .any)["Lives"]
        XCTAssertTrue(lives.waitForExistence(timeout: 5), "lives element has an accessibility label")
        XCTAssertEqual(lives.value as? String, "3 of 3 lives")
        sleep(4) // countdown
        shot("gameplay-\(collection)-start")
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tap.frame.midX, dy: tap.frame.midY))
        var caughtLifeLost = false
        for _ in 0..<60 {
            point.tap()
            if let v = lives.value as? String, v.hasPrefix("2 of") || v.hasPrefix("1 of") {
                shot("gameplay-\(collection)-lifelost")
                caughtLifeLost = true
                break
            }
            usleep(150_000)
        }
        XCTAssertTrue(caughtLifeLost, "no life lost within 60 taps")
        sleep(2)
        shot("gameplay-\(collection)-depleted")
    }

    /// Rush = score + 5 themed lives + timer: the widest HUD. Run on the narrowest
    /// phone (iPhone 16e) — no overlap, nothing off screen.
    func test_hud_rush_five_themed_lives_layout() {
        launch(["-PTForceCosmeticCollection", "boom_mode"])
        XCTAssertTrue(openMode("RUSH"))
        XCTAssertTrue(app.buttons["TAP!"].waitForExistence(timeout: 10))
        let lives = app.descendants(matching: .any)["Lives"]
        XCTAssertTrue(lives.waitForExistence(timeout: 5))
        XCTAssertEqual(lives.value as? String, "5 of 5 lives")
        let window = app.windows.firstMatch.frame
        let score = app.staticTexts["SCORE"].frame
        let time = app.staticTexts["TIME"].frame
        XCTAssertTrue(window.contains(lives.frame), "lives off screen: \(lives.frame) in \(window)")
        XCTAssertFalse(lives.frame.intersects(time), "lives overlap timer: \(lives.frame) vs \(time)")
        XCTAssertFalse(lives.frame.intersects(score), "lives overlap score: \(lives.frame) vs \(score)")
        shot("hud-rush-boom-5-lives-\(Int(window.width))pt")
    }

    /// Zen has no lives: tap until a PERFECT lands and grab the effect frame.
    func test_perfect_effect_frame() {
        launch(["-PTForceCosmeticCollection", "quack_attack"])
        XCTAssertTrue(openMode("ZEN"))
        let tap = app.buttons["TAP!"]
        XCTAssertTrue(tap.waitForExistence(timeout: 10))
        sleep(4)
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tap.frame.midX, dy: tap.frame.midY))
        // "PERFECT" is always on screen (zone label, Zen stat label): wait for
        // one MORE element — the accuracy feedback of a PERFECT tap.
        let perfectTexts = app.staticTexts.matching(identifier: "PERFECT")
        let idleCount = perfectTexts.count
        var caught = false
        for i in 0..<150 {
            point.tap()
            if perfectTexts.count > idleCount {
                shot("effect-perfect-quack_attack")
                caught = true
                break
            }
            usleep(UInt32(90_000 + (i % 7) * 37_000))
        }
        if !caught { shot("effect-perfect-not-caught") }
    }

    // MARK: Shop Studio

    func test_shop_studio_screens() {
        launch()
        openStudio()
        shot("shop-studio-collections")
        let quackCard = app.descendants(matching: .any)["studio.collection.quack_attack"]
        XCTAssertTrue(quackCard.waitForExistence(timeout: 5))
        if let v = quackCard.value as? String { XCTAssertTrue(v.contains("of 9 owned"), "collection card value: \(v)") }

        // Item grid + action bar.
        app.buttons["Tap Buttons"].tap()
        let duck = app.buttons["studio.item.quack_attack.tapButton"]
        XCTAssertTrue(duck.waitForExistence(timeout: 5))
        duck.tap()
        sleep(1)
        shot("shop-studio-item-actionbar")

        // Preview Studio with a themed loadout.
        app.buttons["Collections"].tap()
        let preview = app.buttons["studio.openPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let tryBoom = app.buttons["Try the whole Boom Mode collection"]
        if tryBoom.waitForExistence(timeout: 5) { tryBoom.tap() }
        sleep(1)
        let previewButton = app.buttons["Tap button preview"]
        if previewButton.exists { previewButton.tap(); usleep(200_000) }
        shot("preview-studio-boom-loadout")
    }

    func test_shop_studio_largest_dynamic_type() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openStudio()
        shot("shop-studio-a11y-xxxl")
        app.swipeUp()
        shot("shop-studio-a11y-xxxl-scrolled")
    }

    // MARK: Cold launch (comparable with the baseline: same test, same args)

    func test_cold_launch_metric() {
        let app = XCUIApplication()
        app.launchArguments += ["-PTUITestOfflineBackend", "-PTUITestNoAds"]
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

    // MARK: Navigation helpers (same as ModeRuntimeQATests)

    private func openStudio() {
        XCTAssertTrue(app.buttons["SHOP"].waitForExistence(timeout: 10))
        app.buttons["SHOP"].tap()
        let studio = app.buttons["Studio"]
        XCTAssertTrue(studio.waitForExistence(timeout: 8), "Studio tab missing (flag should be ON in Debug)")
        studio.tap()
        sleep(1)
    }

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
            field.typeText("qa_\(Int(Date().timeIntervalSince1970) % 100000)")
            if app.buttons["LET'S GO!"].exists { app.buttons["LET'S GO!"].tap() }
        }
    }

    private func dismissTutorialIfNeeded() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 4) { skip.tap() }
    }
}
