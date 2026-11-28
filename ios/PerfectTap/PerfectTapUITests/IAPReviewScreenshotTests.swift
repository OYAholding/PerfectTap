import XCTest

final class IAPReviewScreenshotTests: XCTestCase {
    func test_openCompleteIAPCatalogForReviewScreenshot() {
        let app = XCUIApplication()
        app.launchArguments += ["-PTIAPPreview", "-PTUITestOfflineBackend", "-PTUITestNoAds"]
        app.launch()

        let chooseName = app.staticTexts["Choose Your Name"]
        if chooseName.waitForExistence(timeout: 8) {
            let field = app.textFields.element(boundBy: 0)
            field.tap()
            field.typeText("AppReview")
            app.buttons["LET'S GO!"].tap()
        }
        if app.buttons["Skip"].waitForExistence(timeout: 2) { app.buttons["Skip"].tap() }
        XCTAssertTrue(app.buttons["SHOP"].waitForExistence(timeout: 12))
        app.buttons["SHOP"].tap()
        XCTAssertTrue(app.buttons["BUY COINS"].waitForExistence(timeout: 5))
        app.buttons["BUY COINS"].tap()
        XCTAssertTrue(app.staticTexts["Remove Forced Ads"].waitForExistence(timeout: 8))

        let priceIdentifiers = [
            "iap.com.perfecttap.coins.500.price",
            "iap.com.perfecttap.coins.1200.price",
            "iap.com.perfecttap.coins.3000.price",
            "iap.com.perfecttap.coins.8000.price",
            "iap.removeAds.price"
        ]
        guard app.staticTexts[priceIdentifiers[0]].waitForExistence(timeout: 15) else {
            let diagnostic = XCTAttachment(screenshot: app.screenshot())
            diagnostic.name = "StoreKit prices failed to load"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            XCTFail("StoreKit prices did not load; review screenshot must not use placeholders")
            return
        }
        for identifier in priceIdentifiers.dropFirst() {
            if identifier == "iap.removeAds.price" {
                let removeAds = app.buttons[identifier]
                XCTAssertTrue(removeAds.waitForExistence(timeout: 8))
                XCTAssertTrue(removeAds.label.contains("$"), "Remove Ads is still showing a StoreKit placeholder")
            } else {
                XCTAssertTrue(app.staticTexts[identifier].waitForExistence(timeout: 8),
                              "Missing StoreKit price: \(identifier)")
            }
        }

        keepScreenshot(app, name: "coin-packs")

        app.buttons["BUY COINS"].tap()
        app.buttons["Premium"].tap()
        let premiumItems = [
            ("theme_neonpulse", "skin-neonpulse"),
            ("theme_chrome", "skin-liquidchrome"),
            ("theme_glitch", "skin-glitchmode"),
            ("theme_cosmicgold", "skin-cosmicgold")
        ]
        for (itemID, screenshotName) in premiumItems {
            let item = app.buttons["shop.item.\(itemID)"]
            XCTAssertTrue(item.waitForExistence(timeout: 8), "Missing premium item: \(itemID)")
            let priceLoaded = NSPredicate(format: "label CONTAINS %@", "$")
            expectation(for: priceLoaded, evaluatedWith: item)
            waitForExpectations(timeout: 12)
            item.tap()
            keepScreenshot(app, name: screenshotName)
        }
    }

    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
