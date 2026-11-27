import XCTest
import UIKit
import SwiftUI
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Cosmetic effect renderers and art assets (Agent B): every catalog style is
/// drawn, every referenced asset ships (or is on the documented allow-list), and
/// bursts stay within CosmeticEffectBounds.
final class CosmeticEffectsTests: XCTestCase {

    /// Asset names the catalog references but that are intentionally not produced
    /// (docs/cosmetics/ASSET_MANIFEST.md, "Not produced"): the tap-button body is
    /// rendered natively by CosmeticTapButtonSkin; the sheet's buttons have baked text.
    static let intentionallyNotProduced: Set<String> = [
        "cos_quack_button", "cos_quack_button_pressed",
        "cos_paw_button", "cos_paw_button_pressed",
        "cos_boom_button", "cos_boom_button_pressed",
    ]

    private let sampleProgress: [Double] = stride(from: 0.0, to: 1.0, by: 0.02).map { $0 }

    private var catalogEffectItems: [CosmeticItem] {
        CosmeticCatalog.items.filter { CosmeticSlot.effectSlots.contains($0.slot) && $0.assets.effectStyle != nil }
    }

    private func spec(for item: CosmeticItem, mode: CosmeticEffectMode, sequence: Int = 7) -> CosmeticBurstSpec? {
        let event: CosmeticEvent
        switch item.slot {
        case .perfectEffect:  event = .perfect
        case .missEffect:     event = .miss
        case .lifeLostEffect: event = .lifeLost
        case .gameOverEffect: event = .gameOver
        default:              event = .tap
        }
        return CosmeticEffectPlanner.spec(style: item.assets.effectStyle!, event: event, palette: item.assets.palette,
                                          spriteName: item.assets.imageName, mode: mode, sequence: sequence)
    }

    // MARK: Renderer coverage

    func testEveryCatalogEffectStyleHasARenderer() {
        let styles = Set(catalogEffectItems.compactMap { $0.assets.effectStyle })
        XCTAssertFalse(styles.isEmpty)
        for style in styles where style != .none && style != .legacyParticles {
            XCTAssertTrue(CosmeticEffectPlanner.rendersNatively(style), "\(style) has no renderer")
        }
        XCTAssertFalse(CosmeticEffectPlanner.rendersNatively(.none))
        XCTAssertFalse(CosmeticEffectPlanner.rendersNatively(.legacyParticles))
    }

    func testEveryCatalogEffectItemDrawsSomething() {
        for item in catalogEffectItems {
            let style = item.assets.effectStyle!
            guard CosmeticEffectPlanner.rendersNatively(style) else {
                XCTAssertNil(spec(for: item, mode: .full), "\(item.id) must not draw")
                continue
            }
            for mode in [CosmeticEffectMode.full, .reduced] {
                guard let s = spec(for: item, mode: mode) else { return XCTFail("\(item.id) \(mode): no burst") }
                let drawn = sampleProgress.map { CosmeticEffectFrames.primitives(for: s, progress: $0).count }.reduce(0, +)
                XCTAssertGreaterThan(drawn, 0, "\(item.id) \(mode) draws nothing")
            }
        }
    }

    // MARK: Assets

    func testCatalogAssetNamesExistInBundle() {
        var checked = 0
        for item in CosmeticCatalog.items where !item.isDefault {
            var names: [String] = []
            switch item.slot {
            case .tapButton:
                names = [item.assets.imageName, item.assets.secondaryImageName, item.assets.emblemImageName].compactMap { $0 }
            case .lifeIcon:
                names = [item.assets.imageName, item.assets.secondaryImageName].compactMap { $0 }
            case .tapEffect, .perfectEffect, .missEffect, .lifeLostEffect, .gameOverEffect:
                names = [item.assets.imageName].compactMap { $0 }
            case .tapSound, .haptics:
                names = []
            }
            for name in names where !Self.intentionallyNotProduced.contains(name) {
                checked += 1
                let image = UIImage(named: name)
                XCTAssertNotNil(image, "missing asset \(name) (\(item.id))")
                if let image { XCTAssertGreaterThanOrEqual(image.size.width * image.scale, 48, "\(name) too small") }
            }
        }
        XCTAssertEqual(checked, 13, "life icons (6) + emblems (3) + sprites (4)")
    }

    func testAllowListOnlyNamesCatalogReferences() {
        let referenced = Set(CosmeticCatalog.items.flatMap {
            [$0.assets.imageName, $0.assets.secondaryImageName, $0.assets.emblemImageName].compactMap { $0 }
        })
        XCTAssertTrue(Self.intentionallyNotProduced.isSubset(of: referenced))
    }

    // MARK: Bounds

    func testBurstsStayWithinBounds() {
        for item in catalogEffectItems {
            for mode in [CosmeticEffectMode.full, .reduced] {
                for seq in [1, 2, 99, 12_345] {
                    guard let s = spec(for: item, mode: mode, sequence: seq) else { continue }
                    XCTAssertLessThanOrEqual(s.lifetime, CosmeticEffectBounds.lifetimeCap(for: s.event), item.id)
                    XCTAssertLessThanOrEqual(s.lifetime, CosmeticEffectBounds.maxGameOverLifetime)
                    if s.event != .gameOver { XCTAssertLessThanOrEqual(s.lifetime, CosmeticEffectBounds.maxLifetime, item.id) }
                    XCTAssertLessThanOrEqual(s.particles.count, CosmeticEffectBounds.maxPrimitivesPerBurst)
                    for t in sampleProgress {
                        let prims = CosmeticEffectFrames.primitives(for: s, progress: t)
                        XCTAssertLessThanOrEqual(prims.count, CosmeticEffectBounds.maxPrimitivesPerBurst, "\(item.id) t=\(t)")
                        for p in prims {
                            XCTAssertLessThanOrEqual(p.extent, CosmeticEffectBounds.maxExtent + 1e-9, "\(item.id) \(p.kind) t=\(t)")
                            XCTAssertTrue((0...1).contains(p.opacity), "\(item.id) opacity \(p.opacity)")
                        }
                    }
                    XCTAssertTrue(CosmeticEffectFrames.primitives(for: s, progress: 1).isEmpty)
                }
            }
        }
    }

    func testBurstRadiusIsAtMost45PercentOfWidth() {
        for w in [320.0, 390.0, 430.0, 1024.0] {
            let r = CosmeticEffectBounds.radius(for: CGSize(width: w, height: 800))
            XCTAssertLessThanOrEqual(2 * r * CGFloat(CosmeticEffectBounds.maxExtent), 0.45 * w + 0.001)
        }
    }

    func testReducedModeHasNoMovement() {
        for item in catalogEffectItems {
            guard let s = spec(for: item, mode: .reduced) else { continue }
            XCTAssertTrue(s.particles.isEmpty)
            var first: CosmeticPrimitive?
            for t in sampleProgress {
                let prims = CosmeticEffectFrames.primitives(for: s, progress: t)
                XCTAssertLessThanOrEqual(prims.count, 1, item.id)
                guard let p = prims.first else { continue }
                if let f = first {
                    XCTAssertEqual(p.x, f.x); XCTAssertEqual(p.y, f.y)
                    XCTAssertEqual(p.size, f.size); XCTAssertEqual(p.rotation, f.rotation)
                } else { first = p }
            }
        }
    }

    func testOffProducesNoBursts() {
        var loadout = CosmeticLoadout()
        for c in CosmeticCatalog.collections { loadout.apply(collection: c) }
        let resolved = ResolvedCosmetics.resolve(loadout, isOwned: { _ in true })
        for event in CosmeticEvent.allCases {
            XCTAssertNil(CosmeticEffectPlanner.spec(resolved: resolved, trigger: CosmeticEffectTrigger(event: event, sequence: 1), level: .off))
        }
        XCTAssertNil(CosmeticEffectPlanner.mode(for: .off))
    }

    func testDefaultLoadoutDrawsNothing() {
        for event in CosmeticEvent.allCases {
            XCTAssertNil(CosmeticEffectPlanner.spec(resolved: .defaults, trigger: CosmeticEffectTrigger(event: event, sequence: 3), level: .full),
                         "default loadout must keep the pre-Studio look (\(event))")
        }
    }

    func testDeterministicPerTrigger() {
        let item = CosmeticCatalog.item(id: "boom_mode.perfectEffect")!
        XCTAssertEqual(spec(for: item, mode: .full, sequence: 5), spec(for: item, mode: .full, sequence: 5))
        XCTAssertNotEqual(spec(for: item, mode: .full, sequence: 5)?.particles, spec(for: item, mode: .full, sequence: 6)?.particles)
    }

    // MARK: Queue

    func testQueueKeepsAtMostTwoBurstsDroppingOldest() {
        let item = CosmeticCatalog.item(id: "quack_attack.tapEffect")!
        var q = CosmeticBurstQueue()
        for i in 1...5 { q.push(spec(for: item, mode: .full, sequence: i)!, id: i, at: 100 + Double(i) * 0.05) }
        XCTAssertEqual(q.bursts.count, CosmeticEffectBounds.maxConcurrentBursts)
        XCTAssertEqual(q.bursts.map(\.id), [4, 5])
        XCTAssertFalse(q.isExpired(at: 100.3))
        XCTAssertTrue(q.isExpired(at: 110))
        q.prune(at: 110)
        XCTAssertTrue(q.isEmpty)
    }

    func testFlashesAreRateLimited() {
        let item = CosmeticCatalog.item(id: "boom_mode.perfectEffect")!
        var q = CosmeticBurstQueue()
        var flashes: [Double] = []
        // 10 taps per second for 2 s.
        for i in 0..<20 {
            let now = 50 + Double(i) * 0.1
            q.push(spec(for: item, mode: .full, sequence: i + 1)!, id: i, at: now)
            if q.bursts.last!.spec.allowsFlash { flashes.append(now) }
        }
        for (a, b) in zip(flashes, flashes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, CosmeticEffectBounds.minFlashInterval - 1e-9)
        }
        XCTAssertLessThanOrEqual(flashes.count, 7)
    }

    // MARK: Visual QA (opt-in)

    /// Renders a filmstrip per collection when TEST_RUNNER_PT_EFFECT_FILMSTRIP_DIR is set
    /// (xcodebuild passes TEST_RUNNER_-prefixed variables to the test process).
    @MainActor
    func testRenderEffectFilmstrips() throws {
        guard let dir = ProcessInfo.processInfo.environment["PT_EFFECT_FILMSTRIP_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_PT_EFFECT_FILMSTRIP_DIR to render filmstrips")
        }
        let progress: [Double] = [0.04, 0.12, 0.25, 0.4, 0.6, 0.8, 0.95]
        let frame = CGSize(width: 390, height: 260)
        for collection in ["quack_attack", "purrfect_tap", "boom_mode"] {
            let items = catalogEffectItems.filter { $0.collectionID == collection }
            let specs = items.compactMap { spec(for: $0, mode: .full) } + items.filter { $0.slot == .gameOverEffect }.compactMap { spec(for: $0, mode: .reduced) }
            let view = VStack(spacing: 2) {
                ForEach(Array(specs.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: 2) {
                        ForEach(progress, id: \.self) { t in
                            Canvas { ctx, size in
                                CosmeticEffectPainter.draw(spec: s, progress: t, in: &ctx, size: size, origin: UnitPoint(x: 0.5, y: 0.5))
                            }
                            .frame(width: frame.width, height: frame.height)
                            .background(Color(red: 0.08, green: 0.07, blue: 0.15))
                        }
                    }
                }
            }
            .background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("filmstrip_\(collection).png"))
        }
    }
}
