import XCTest
import SwiftUI
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Cosmetics × gameplay: feedback classification after scoring, and proof that
/// the equipped loadout cannot change any competitive outcome.
@MainActor
final class CosmeticGameplayIntegrationTests: XCTestCase {

    // MARK: TapSoundOutcome (mirrors the pre-Studio if/else chain)

    private func outcome(_ accuracy: TapAccuracy, prev: Int, combo: Int,
                         hardcoreBreak: Bool = false, lives: Bool = true) -> TapSoundOutcome {
        GameViewModel.tapOutcome(accuracy: accuracy, prevCombo: prev, combo: combo,
                                 didHardcoreBreak: hardcoreBreak, usesLives: lives)
    }

    func testMissAfterComboOfThreeIsAComboBreak() {
        let o = outcome(.miss, prev: 3, combo: 0)
        XCTAssertTrue(o.comboBroken)
        XCTAssertTrue(o.lostLife)
        XCTAssertFalse(o.milestone)
    }

    func testMissWithSmallComboIsAPlainMiss() {
        let o = outcome(.miss, prev: 2, combo: 0)
        XCTAssertFalse(o.comboBroken)
        XCTAssertTrue(o.lostLife)
    }

    func testMissWithoutLivesDoesNotLoseALife() {
        XCTAssertFalse(outcome(.miss, prev: 0, combo: 0, lives: false).lostLife)
    }

    func testHardcoreBreakOnAGoodTapIsAComboBreakWithoutLifeLoss() {
        let o = outcome(.good, prev: 6, combo: 0, hardcoreBreak: true)
        XCTAssertTrue(o.comboBroken)
        XCTAssertFalse(o.lostLife)
    }

    func testMilestones() {
        for combo in [5, 10, 20] {
            XCTAssertTrue(outcome(.great, prev: combo - 1, combo: combo).milestone, "\(combo)")
        }
        for combo in [1, 4, 6, 15, 21] {
            XCTAssertFalse(outcome(.perfect, prev: combo - 1, combo: combo).milestone, "\(combo)")
        }
    }

    func testHitsNeverLoseLivesOrBreakCombos() {
        for accuracy in [TapAccuracy.good, .great, .perfect] {
            let o = outcome(accuracy, prev: 7, combo: 8)
            XCTAssertFalse(o.lostLife)
            XCTAssertFalse(o.comboBroken)
            XCTAssertEqual(o.accuracy, accuracy)
        }
    }

    func testEventMappingDrivesTheRightEffectSlots() {
        XCTAssertEqual(CosmeticEvent(accuracy: .good).effectSlot, .tapEffect)
        XCTAssertEqual(CosmeticEvent(accuracy: .great).effectSlot, .tapEffect)
        XCTAssertEqual(CosmeticEvent(accuracy: .perfect).effectSlot, .perfectEffect)
        XCTAssertEqual(CosmeticEvent(accuracy: .miss).effectSlot, .missEffect)
        XCTAssertEqual(CosmeticEvent.lifeLost.effectSlot, .lifeLostEffect)
        XCTAssertEqual(CosmeticEvent.gameOver.effectSlot, .gameOverEffect)
    }

    // MARK: Cosmetics never change scoring

    private struct RunResult: Equatable {
        var score: Int
        var lives: Int
        var combo: Int
        var speedLevel: Int
        var accuracies: [TapAccuracy]
        var phase: GamePhase
    }

    /// Plays the same synthetic round (same frame clock, same touch times) and
    /// records every competitive output.
    private func play(_ mode: GameMode, cosmetics: ResolvedCosmetics) -> RunResult {
        let vm = GameViewModel()
        vm.setup(mode: mode, profile: PlayerProfile(), cosmetics: cosmetics)
        vm.cleanup()   // frames are driven manually below
        defer { vm.cleanup() }

        var t: CFTimeInterval = 100
        for i in 0...3 { vm.step(now: t + Double(i)) }
        XCTAssertEqual(vm.phase, .playing)
        t += 3

        var accuracies: [TapAccuracy] = []
        for i in 0..<80 {
            let frames = 5 + (i * 7) % 23     // irregular rhythm → a mix of results
            for _ in 0..<frames {
                t += 1.0 / 60.0
                vm.step(now: t)
            }
            guard vm.phase == .playing else { break }
            vm.handleTap(touchTimestamp: t + 0.004)
            if let acc = vm.lastTapAccuracy { accuracies.append(acc) }
        }
        return RunResult(score: vm.score, lives: vm.lives, combo: vm.combo, speedLevel: vm.speedLevel,
                         accuracies: accuracies, phase: vm.phase)
    }

    private var quackEverything: ResolvedCosmetics {
        var loadout = CosmeticLoadout()
        loadout.apply(collection: CosmeticCatalog.collection(id: "quack_attack")!)
        return CosmeticLoadoutStore.previewResolved(loadout)
    }

    func testQuackLoadoutProducesIdenticalScoreAndLivesInClassic() {
        let quack = quackEverything
        XCTAssertEqual(quack.item(for: .tapButton).id, "quack_attack.tapButton")

        let plain = play(.classic, cosmetics: .defaults)
        let themed = play(.classic, cosmetics: quack)
        XCTAssertEqual(plain, themed)
        // The run must actually exercise scoring, otherwise equality proves nothing.
        XCTAssertGreaterThan(Set(plain.accuracies).count, 1, "need a mix of results: \(plain.accuracies)")
        XCTAssertGreaterThan(plain.accuracies.count, 3)
    }

    func testBoomLoadoutProducesIdenticalResultsInTimedAndRush() {
        var loadout = CosmeticLoadout()
        loadout.apply(collection: CosmeticCatalog.collection(id: "boom_mode")!)
        let boom = CosmeticLoadoutStore.previewResolved(loadout)
        for mode in [GameMode.timed, .rush] {
            XCTAssertEqual(play(mode, cosmetics: .defaults), play(mode, cosmetics: boom), "\(mode)")
        }
    }

    // MARK: Rendering never crashes on missing art

    /// Agent B's art is not on this branch, so every themed lookup misses:
    /// the views must still render (native button, default dots).
    func testThemedViewsRenderWithMissingAssets() {
        XCTAssertNil(CosmeticImageCache.shared.image(named: "cos_definitely_missing_asset"))
        XCTAssertNil(CosmeticImageCache.shared.image(named: nil))
        CosmeticImageCache.shared.preload(quackEverything)

        let colors = [Color.purple, Color.cyan]
        for collection in ["default", "quack_attack", "purrfect_tap", "boom_mode"] {
            let button = CosmeticCatalog.item(id: "\(collection).tapButton")!
            let lives = CosmeticCatalog.item(id: "\(collection).lifeIcon")!
            for pressed in [false, true] {
                let renderer = ImageRenderer(content:
                    CosmeticTapButtonSkin(item: button, fallbackColors: colors, isPressed: pressed)
                        .frame(width: 345))
                let image = renderer.uiImage
                XCTAssertNotNil(image, "\(collection) pressed=\(pressed)")
                XCTAssertEqual(image?.size.height ?? 0, 80, accuracy: 0.5, "skin must keep the 80 pt height")
            }
            let livesImage = ImageRenderer(content: CosmeticLivesView(item: lives, maxLives: 5, lives: 2)).uiImage
            XCTAssertNotNil(livesImage, collection)
            XCTAssertLessThanOrEqual(livesImage?.size.width ?? .infinity, 100.5, "lives row is width-capped")
        }
    }

    // MARK: Themed button layout (QA-09 emblem cut, QA-10 emblem over label)

    private let layoutHeights: [CGFloat] = [28, 30, 36, 40, 48, 56, 64, 80, 96]
    private let layoutWidths: [CGFloat] = [60, 75, 83, 100, 120, 160, 200, 280, 345, 354, 600, 1000]

    func testEmblemNeverCoversTheLabelAtAnySize() {
        for label in ["TAP!", "TAP"] {
            for h in layoutHeights {
                for w in layoutWidths {
                    let layout = ThemedTapButtonLayout.make(size: CGSize(width: w, height: h), hasEmblem: true,
                                                            labelWidth: { ThemedTapButtonLayout.labelWidth(label, fontSize: $0) })
                    let where_ = "\(label) \(w)×\(h)"
                    XCTAssertGreaterThanOrEqual(layout.fontSize, ThemedTapButtonLayout.minFontSize, where_)
                    XCTAssertLessThanOrEqual(layout.fontSize, ThemedTapButtonLayout.maxFontSize, where_)
                    XCTAssertEqual(layout.labelFrame.width, ThemedTapButtonLayout.labelWidth(label, fontSize: layout.fontSize), where_)
                    guard let frame = layout.emblemFrame else { continue }
                    let art = ThemedTapButtonLayout.artBox(emblemFrame: frame, buttonHeight: h)
                    XCTAssertFalse(art.intersects(layout.labelFrame), "emblem art over the label at \(where_)")
                    XCTAssertLessThanOrEqual(art.maxX + ThemedTapButtonLayout.gap(height: h) - 0.001, layout.labelFrame.minX, where_)
                    XCTAssertLessThanOrEqual(layout.labelFrame.maxX, w, where_)
                    // QA-09: square (never stretched) and the flat cut lies exactly on the bottom edge.
                    XCTAssertEqual(frame.width, frame.height, where_)
                    XCTAssertEqual(frame.minY + frame.height * ThemedTapButtonLayout.artCutFraction, h, accuracy: 0.001, where_)
                    XCTAssertGreaterThanOrEqual(art.minY, 0, "art stays inside the capsule height at \(where_)")
                }
            }
        }
    }

    func testGameplayButtonKeepsFullSizeEmblemAndLabel() {
        // 402-pt iPhone minus 2×24 padding; 80 pt gameplay height.
        let layout = ThemedTapButtonLayout.make(size: CGSize(width: 354, height: 80), hasEmblem: true,
                                                labelWidth: { ThemedTapButtonLayout.labelWidth("TAP!", fontSize: $0) })
        XCTAssertEqual(layout.fontSize, 26)
        XCTAssertEqual(layout.emblemFrame?.width ?? 0, 80 * ThemedTapButtonLayout.emblemScales[0], accuracy: 0.001)
        // Studio hero card (56 pt) keeps an emblem too.
        let hero = ThemedTapButtonLayout.make(size: CGSize(width: 300, height: 56), hasEmblem: true,
                                              labelWidth: { ThemedTapButtonLayout.labelWidth("TAP!", fontSize: $0) })
        XCTAssertNotNil(hero.emblemFrame)
    }

    func testNoEmblemCentresTheLabel() {
        let layout = ThemedTapButtonLayout.make(size: CGSize(width: 200, height: 56), hasEmblem: false,
                                                labelWidth: { ThemedTapButtonLayout.labelWidth("TAP!", fontSize: $0) })
        XCTAssertNil(layout.emblemFrame)
        XCTAssertEqual(layout.labelFrame.midX, 100, accuracy: 0.5)
        XCTAssertEqual(layout.labelFrame.midY, 28, accuracy: 0.5)
    }

    /// Opt-in visual check (QA-09/QA-10): TEST_RUNNER_PT_BUTTON_SHEET_DIR=<dir> writes
    /// tap-button-sheet.png with every themed skin at gameplay, Studio hero and chip sizes.
    func testRenderTapButtonSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["PT_BUTTON_SHEET_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_PT_BUTTON_SHEET_DIR to render the tap-button sheet")
        }
        let sizes: [(CGFloat, CGFloat, String)] = [(80, 354, "TAP!"), (56, 300, "TAP!"), (40, 83, "TAP"), (30, 83, "TAP")]
        let sheet = VStack(alignment: .leading, spacing: 14) {
            ForEach(["quack_attack", "purrfect_tap", "boom_mode"], id: \.self) { collection in
                let button = CosmeticCatalog.item(id: "\(collection).tapButton")!
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
                        HStack(spacing: 16) {
                            CosmeticTapButtonSkin(item: button, fallbackColors: [.purple], label: size.2, height: size.0)
                                .frame(width: size.1)
                            CosmeticTapButtonSkin(item: button, fallbackColors: [.purple], isPressed: true, label: size.2, height: size.0)
                                .frame(width: size.1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.05, green: 0.05, blue: 0.08))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("tap-button-sheet.png"))
    }

    func testThemedSkinsRenderAtStudioAndChipHeights() {
        CosmeticImageCache.shared.preload(quackEverything)
        for collection in ["quack_attack", "purrfect_tap", "boom_mode"] {
            let button = CosmeticCatalog.item(id: "\(collection).tapButton")!
            for (h, w, label) in [(CGFloat(30), CGFloat(83), "TAP"), (40, 83, "TAP"), (56, 300, "TAP!"), (80, 354, "TAP!")] {
                let image = ImageRenderer(content: CosmeticTapButtonSkin(item: button, fallbackColors: [.purple], label: label, height: h)
                    .frame(width: w)).uiImage
                XCTAssertEqual(image?.size.height ?? 0, h, accuracy: 0.5, "\(collection) \(h)")
                XCTAssertEqual(image?.size.width ?? 0, w, accuracy: 0.5, "\(collection) \(w)")
            }
        }
    }
}
