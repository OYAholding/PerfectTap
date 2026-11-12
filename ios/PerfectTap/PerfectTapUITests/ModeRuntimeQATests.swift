import XCTest

final class ModeRuntimeQATests: XCTestCase {

    private let app = XCUIApplication()

    struct ModeCase {
        let name: String
        let cardTitle: String
        let expectsScoreHUD: Bool
        let expectsTimerHUD: Bool
        let hidesHUD: Bool
        let expectsZenStatsHUD: Bool
        let expectsRevive: Bool
        let expectsModeLabel: Bool
        let expectsStrictPerfectUI: Bool
        let expectsHiddenZoneLabels: Bool
        let expectsTimedGameOverTitle: String?
    }

    private let modes: [ModeCase] = [
        .init(name: "Classic", cardTitle: "CLASSIC", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: false, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Endless", cardTitle: "ENDLESS", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Timed", cardTitle: "TIMED", expectsScoreHUD: true, expectsTimerHUD: true, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: false, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: "TIME'S UP!"),
        .init(name: "Sudden Death", cardTitle: "SUDDEN DEATH", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: false, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Combo Frenzy", cardTitle: "COMBO FRENZY", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Zen", cardTitle: "ZEN", expectsScoreHUD: false, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: true, expectsRevive: false, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Precision", cardTitle: "PRECISION", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: true, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Chaos", cardTitle: "CHAOS", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Mirror", cardTitle: "MIRROR", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Invisible Zone", cardTitle: "INVISIBLE ZONE", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: true, expectsTimedGameOverTitle: nil),
        .init(name: "Rush", cardTitle: "RUSH", expectsScoreHUD: true, expectsTimerHUD: true, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: "TIME'S UP!"),
        .init(name: "Hardcore Combo", cardTitle: "HARDCORE COMBO", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Tiny Window", cardTitle: "TINY WINDOW", expectsScoreHUD: true, expectsTimerHUD: false, hidesHUD: false, expectsZenStatsHUD: false, expectsRevive: true, expectsModeLabel: true, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil),
        .init(name: "Focus", cardTitle: "FOCUS", expectsScoreHUD: false, expectsTimerHUD: false, hidesHUD: true, expectsZenStatsHUD: false, expectsRevive: false, expectsModeLabel: false, expectsStrictPerfectUI: false, expectsHiddenZoneLabels: false, expectsTimedGameOverTitle: nil)
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func test_mode_runtime_matrix() {
        // Real full-screen ads cannot be dismissed by XCUITest; real-ad revive is a
        // manual TestFlight check (docs/RELEASE_PLAN_1.1.0.he.md §6 #7).
        app.launchArguments += ["-PTUITestNoAds"]
        app.launch()
        completeOnboardingIfNeeded()
        dismissTutorialIfNeeded()
        XCTAssertTrue(waitForHome(), "Failed to reach Home screen")

        for mode in modes {
            runMode(mode)
        }
    }

    private func runMode(_ mode: ModeCase) {
        var failures: [String] = []

        if !openModeCard(mode.cardTitle) {
            failures.append("entry_path_failed")
            emitResult(mode: mode.name, pass: false, notes: failures)
            return
        }

        let tapButton = app.buttons["TAP!"]
        if !tapButton.waitForExistence(timeout: 8) {
            failures.append("gameplay_not_started")
            emitResult(mode: mode.name, pass: false, notes: failures)
            return
        }

        verifyHUD(mode, failures: &failures)

        // Basic gameplay interaction so scoring/combo/life logic is actually exercised.
        tapMany(count: mode.name == "Sudden Death" ? 12 : 20)

        if mode.name == "Rush" {
            verifyRushReviveAndTimerEnd(failures: &failures)
        } else if mode.name == "Timed" {
            verifyTimedModeRun(failures: &failures)
        } else if mode.expectsRevive {
            verifyLifeModesRevivePolicy(modeName: mode.name, failures: &failures)
        } else if mode.name == "Zen" || mode.name == "Focus" {
            // No fail pressure modes: quit intentionally to complete run
            if !exitPressureFreeMode() {
                failures.append("pressure_free_mode_exit_failed")
            }
        } else if mode.name == "Sudden Death" {
            if app.staticTexts["CONTINUE?"].waitForExistence(timeout: 2) {
                failures.append("unexpected_revive_modal_in_sudden_death")
                app.buttons["Give Up"].tap()
            }
            if !waitForGameOver(timeout: 10) {
                failures.append("sudden_death_did_not_end_after_misses")
            }
        }

        // Solo-vs-duel guard: solo runs should never route to duel results CTA.
        if app.buttons["SEE DUEL RESULTS"].exists {
            failures.append("stale_duel_context_leaked_into_solo")
        }

        // Ensure return-home path works to validate carryover between modes.
        if app.buttons["HOME"].exists {
            app.buttons["HOME"].tap()
        }
        if !waitForHome() {
            failures.append("failed_to_return_home")
        }

        emitResult(mode: mode.name, pass: failures.isEmpty, notes: failures)
    }

    private func verifyHUD(_ mode: ModeCase, failures: inout [String]) {
        if mode.hidesHUD {
            if app.staticTexts["SCORE"].exists { failures.append("focus_should_hide_score_hud") }
            if app.staticTexts["TIME"].exists { failures.append("focus_should_hide_timer_hud") }
            if !app.buttons["QUIT"].exists { failures.append("focus_missing_quit_button") }
            return
        }

        if mode.expectsScoreHUD {
            if !app.staticTexts["SCORE"].exists { failures.append("score_hud_missing") }
        } else {
            if app.staticTexts["SCORE"].exists { failures.append("score_hud_unexpected") }
        }

        if mode.expectsTimerHUD {
            if !app.staticTexts["TIME"].exists { failures.append("timer_hud_missing") }
        } else if app.staticTexts["TIME"].exists {
            failures.append("timer_hud_unexpected")
        }

        if mode.expectsZenStatsHUD {
            if !app.staticTexts["PERFECT"].exists || !app.staticTexts["GREAT"].exists || !app.staticTexts["TOTAL"].exists {
                failures.append("zen_stats_hud_missing")
            }
            if app.staticTexts["×3"].exists || app.staticTexts["COMBO"].exists {
                failures.append("zen_combo_pressure_visible")
            }
        }

        if mode.expectsModeLabel {
            let expected = "\(mode.cardTitle) MODE"
            if !app.staticTexts[expected].exists {
                failures.append("mode_label_missing_\(mode.cardTitle.lowercased().replacingOccurrences(of: " ", with: "_"))")
            }
        }

        if mode.expectsStrictPerfectUI {
            if app.staticTexts["GOOD"].exists || app.staticTexts["GREAT"].exists {
                failures.append("precision_should_not_show_good_or_great_zones")
            }
            let missCount = app.staticTexts.matching(identifier: "MISS").count
            if missCount < 4 {
                failures.append("precision_strict_zone_labels_not_applied")
            }
        }

        if mode.expectsHiddenZoneLabels {
            if app.staticTexts["PERFECT"].exists || app.staticTexts["GOOD"].exists || app.staticTexts["GREAT"].exists {
                failures.append("invisible_zone_labels_should_be_hidden")
            }
        }
    }

    private func verifyTimedModeRun(failures: inout [String]) {
        // Spam taps to ensure misses don't end the run
        tapMany(count: 45)
        if app.staticTexts["CONTINUE?"].exists {
            failures.append("timed_should_not_show_revive")
            app.buttons["Give Up"].tap()
        }
        if app.buttons["HOME"].exists {
            failures.append("timed_ended_early_before_timer")
            return
        }

        if !waitForGameOver(timeout: 75) {
            failures.append("timed_did_not_reach_game_over_at_timer_end")
            return
        }
        if !app.staticTexts["TIME'S UP!"].exists {
            failures.append("timed_game_over_title_mismatch")
        }
    }

    private func verifyRushReviveAndTimerEnd(failures: inout [String]) {
        let timerBefore = currentTimerSeconds()
        // Force misses until revive appears
        for _ in 0..<220 {
            if app.staticTexts["CONTINUE?"].exists || app.buttons["HOME"].exists { break }
            app.buttons["TAP!"].tap()
        }

        if app.staticTexts["CONTINUE?"].exists {
            let desc = app.staticTexts["Restore lives and keep rushing. No time bonus."]
            if !desc.exists {
                failures.append("rush_revive_copy_missing_no_time_bonus")
            }
            let continueButton = app.buttons["CONTINUE — FREE"].exists ? app.buttons["CONTINUE — FREE"] : app.buttons["WATCH AD TO CONTINUE"]
            if continueButton.exists {
                continueButton.tap()
                _ = app.buttons["TAP!"].waitForExistence(timeout: 6)
            } else {
                failures.append("rush_revive_continue_button_missing")
            }

            if let before = timerBefore, let after = currentTimerSeconds(), after > before + 2 {
                failures.append("rush_revive_time_bonus_detected_unexpected")
            }
        } else {
            failures.append("rush_revive_not_reached_for_policy_check")
        }

        if !waitForGameOver(timeout: 45) {
            failures.append("rush_did_not_end")
            return
        }
        if !app.staticTexts["TIME'S UP!"].exists {
            failures.append("rush_game_over_title_mismatch")
        }
    }

    private func verifyLifeModesRevivePolicy(modeName: String, failures: inout [String]) {
        var sawRevive = false
        for _ in 0..<260 {
            if app.staticTexts["CONTINUE?"].exists { sawRevive = true; break }
            if app.buttons["HOME"].exists { break }
            app.buttons["TAP!"].tap()
        }

        if sawRevive {
            app.buttons["Give Up"].tap()
            if !waitForGameOver(timeout: 8) {
                failures.append("did_not_reach_game_over_after_decline_revive")
            }
        } else if !app.buttons["HOME"].exists {
            failures.append("could_not_reach_terminal_state_for_life_mode")
        }
    }

    // MARK: - Navigation helpers

    private func waitForHome(timeout: TimeInterval = 12) -> Bool {
        return app.buttons["PLAY"].waitForExistence(timeout: timeout)
    }

    private func openModeCard(_ title: String) -> Bool {
        if !waitForHome() {
            return false
        }
        app.buttons["PLAY"].tap()

        guard app.staticTexts["SELECT MODE"].waitForExistence(timeout: 6) else {
            return false
        }

        // Scroll until the mode card is visible.
        for _ in 0..<8 {
            let cardButton = app.buttons.containing(.staticText, identifier: title).firstMatch
            if cardButton.exists {
                cardButton.tap()
                return true
            }
            let cardText = app.staticTexts[title]
            if cardText.exists {
                cardText.tap()
                return true
            }
            app.swipeUp()
        }
        return false
    }

    private func completeOnboardingIfNeeded() {
        let chooseName = app.staticTexts["Choose Your Name"]
        guard chooseName.waitForExistence(timeout: 4) else { return }

        let usernameField = app.textFields.element(boundBy: 0)
        if usernameField.waitForExistence(timeout: 3) {
            usernameField.tap()
            usernameField.typeText("qa_runtime_\(Int(Date().timeIntervalSince1970) % 100000)")
            let goButton = app.buttons["LET'S GO!"]
            if goButton.exists { goButton.tap() }
        }
    }

    private func dismissTutorialIfNeeded() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 4) {
            skip.tap()
        }
    }

    private func tapMany(count: Int) {
        for _ in 0..<count {
            let tapButton = app.buttons["TAP!"]
            guard tapButton.exists else { break }
            tapButton.tap()
        }
    }

    private func waitForGameOver(timeout: TimeInterval) -> Bool {
        return app.buttons["HOME"].waitForExistence(timeout: timeout)
    }

    private func exitPressureFreeMode() -> Bool {
        // Zen should expose EXIT directly to home.
        if app.buttons["EXIT"].waitForExistence(timeout: 2) {
            app.buttons["EXIT"].tap()
            return waitForHome()
        }

        // Focus currently has (hidden) lives: misses can end the run in the revive
        // modal, which covers QUIT. Give up there instead (open product question:
        // docs/RELEASE_PLAN_1.1.0.he.md — should Focus be fail-free like Zen?).
        if app.staticTexts["CONTINUE?"].exists, app.buttons["Give Up"].exists {
            print("QA_NOTE|Focus|revive_modal_reached_hidden_lives")
            app.buttons["Give Up"].tap()
            return waitForGameOver(timeout: 8) || waitForHome()
        }

        // Focus (and fallback) uses QUIT -> confirmation alert -> Quit.
        if app.buttons["QUIT"].waitForExistence(timeout: 2) {
            app.buttons["QUIT"].tap()
            // The alert can take a moment right after a burst of taps.
            if app.buttons["Quit"].waitForExistence(timeout: 6) {
                app.buttons["Quit"].tap()
            }
            return waitForGameOver(timeout: 8) || waitForHome()
        }

        return false
    }

    private func currentTimerSeconds() -> Int? {
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        for label in labels {
            guard label.hasSuffix("s") else { continue }
            let digits = label.dropLast()
            if let value = Int(digits) {
                return value
            }
        }
        return nil
    }

    private func emitResult(mode: String, pass: Bool, notes: [String]) {
        let status = pass ? "PASS" : "FAIL"
        let detail = notes.isEmpty ? "ok" : notes.joined(separator: ",")
        print("QA_RESULT|\(mode)|\(status)|\(detail)")
    }
}
