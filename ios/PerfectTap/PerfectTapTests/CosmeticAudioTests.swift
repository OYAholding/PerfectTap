import AVFoundation
import QuartzCore
import UIKit
import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Cosmetic Studio audio + haptics (Agent C): pack catalog completeness, the
/// one-primary-voice policy (incl. default parity with the pre-Studio
/// dispatch), decoding into the engine format, preview isolation, file
/// durations, and main-thread cost of the tap path.
final class CosmeticAudioTests: XCTestCase {

    private var savedSoundSetting: Any?

    override func setUp() {
        super.setUp()
        savedSoundSetting = UserDefaults.standard.object(forKey: "perfecttap_sound")
        UserDefaults.standard.set(true, forKey: "perfecttap_sound")
        SoundEngine.shared.refreshSettings()
    }

    override func tearDown() {
        SoundEngine.shared.setActiveSoundPack(SoundPackCatalog.defaultPackID)
        if let savedSoundSetting {
            UserDefaults.standard.set(savedSoundSetting, forKey: "perfecttap_sound")
        } else {
            UserDefaults.standard.removeObject(forKey: "perfecttap_sound")
        }
        SoundEngine.shared.refreshSettings()
        super.tearDown()
    }

    private var themedPacks: [SoundPack] { SoundPackCatalog.all.filter { !$0.isBuiltIn } }

    /// Every TapSoundOutcome the game can produce (and a few it can't).
    private var allOutcomes: [TapSoundOutcome] {
        var out: [TapSoundOutcome] = []
        for acc in [TapAccuracy.perfect, .great, .good, .miss] {
            for lost in [false, true] {
                for broken in [false, true] {
                    for milestone in [false, true] {
                        out.append(TapSoundOutcome(accuracy: acc, lostLife: lost, comboBroken: broken, milestone: milestone))
                    }
                }
            }
        }
        return out
    }

    private func waitReady(_ packID: String, timeout: TimeInterval = 10) -> Bool {
        let exp = expectation(description: "pack \(packID) ready")
        var ok = false
        SoundEngine.shared.whenSoundPackReady(packID) { ready in
            ok = ready
            exp.fulfill()
        }
        wait(for: [exp], timeout: timeout)
        return ok
    }

    /// A themed pack that is not cached right now (at most the active + one
    /// preview pack are cached, so with the default active one is always free).
    private func coldPackID() -> String {
        let cached = SoundEngine.shared.cachedSoundPackIDs()
        return themedPacks.map(\.id).first { !cached.contains($0) }!
    }

    // MARK: Catalog

    func testEveryThemedPackDefinesAllEventsAndFilesExistInBundle() {
        XCTAssertEqual(themedPacks.map(\.id).sorted(), ["boom_mode", "purrfect_tap", "quack_attack"])
        for pack in themedPacks {
            for event in CosmeticEvent.allCases {
                let names = pack.files[event] ?? []
                XCTAssertFalse(names.isEmpty, "\(pack.id) has no sound for \(event)")
                for name in names {
                    XCTAssertNotNil(SoundPackLoader.url(forFile: name, packID: pack.id, bundle: .main),
                                    "\(name).caf missing from the app bundle")
                }
            }
        }
        let allNames = SoundPackCatalog.all.flatMap(\.allFileNames)
        XCTAssertEqual(allNames.count, Set(allNames).count, "file names must be unique (flat bundle)")
    }

    func testDefaultPackIsBuiltInAndEveryCatalogSoundPackResolves() {
        XCTAssertTrue(SoundPackCatalog.pack(id: "default")?.isBuiltIn == true)
        for item in CosmeticCatalog.items(in: .tapSound) {
            let id = item.assets.soundPackID ?? "<nil>"
            XCTAssertNotNil(SoundPackCatalog.pack(id: id), "\(item.id) references unknown pack \(id)")
        }
        for item in CosmeticCatalog.items(in: .haptics) {
            let id = item.assets.hapticStyleID ?? "<nil>"
            XCTAssertTrue(CosmeticHapticPolicy.styleIDs.contains(id), "\(item.id) references unknown haptic style \(id)")
        }
        XCTAssertEqual(SoundPackCatalog.resolvedPackID("no_such_pack"), "default")
        XCTAssertEqual(CosmeticHapticPolicy.resolvedStyleID("no_such_style"), "default")
    }

    // MARK: Sound policy

    /// Verbatim logic of the pre-Studio GameViewModel `// Sound + haptics` block,
    /// expressed on TapSoundOutcome (comboBroken = hardcore break or miss with combo ≥ 3).
    private func legacySound(_ o: TapSoundOutcome) -> SoundType {
        if o.comboBroken { return .comboBreak }
        if o.accuracy == .miss { return .miss }
        if o.milestone { return .comboMilestone }
        return o.accuracy == .perfect ? .perfect : o.accuracy == .great ? .great : .good
    }

    private func legacyHaptic(_ o: TapSoundOutcome) -> UIImpactFeedbackGenerator.FeedbackStyle {
        if o.comboBroken { return .heavy }
        if o.accuracy == .miss { return .rigid }
        if o.milestone { return .medium }
        return o.accuracy == .perfect ? .light : .soft
    }

    func testDefaultPackPolicyIsIdenticalToLegacyDispatch() {
        for o in allOutcomes {
            XCTAssertEqual(CosmeticAudioPolicy.cue(for: o, packID: "default"), .tone(legacySound(o)), "\(o)")
            // Unknown pack ids behave like the default pack.
            XCTAssertEqual(CosmeticAudioPolicy.cue(for: o, packID: "bogus"), .tone(legacySound(o)), "\(o)")
            XCTAssertEqual(CosmeticAudioPolicy.defaultTone(for: o), legacySound(o))
        }
        XCTAssertEqual(CosmeticAudioPolicy.gameOverCue(packID: "default"), .silent)
    }

    func testThemedPackPolicyTable() {
        let table: [(TapSoundOutcome, CosmeticEvent)] = [
            (TapSoundOutcome(accuracy: .perfect), .perfect),
            (TapSoundOutcome(accuracy: .great), .great),
            (TapSoundOutcome(accuracy: .good), .good),
            (TapSoundOutcome(accuracy: .miss), .miss),
            (TapSoundOutcome(accuracy: .miss, comboBroken: true), .miss),
            (TapSoundOutcome(accuracy: .good, comboBroken: true), .miss),       // hardcore break on GOOD
            (TapSoundOutcome(accuracy: .miss, lostLife: true), .lifeLost),
            (TapSoundOutcome(accuracy: .miss, lostLife: true, comboBroken: true), .lifeLost),
            (TapSoundOutcome(accuracy: .perfect, milestone: true), .perfect),   // no arpeggio layering
            (TapSoundOutcome(accuracy: .great, milestone: true), .great),
        ]
        for pack in themedPacks {
            for (outcome, event) in table {
                XCTAssertEqual(CosmeticAudioPolicy.cue(for: outcome, packID: pack.id), .pack(event), "\(pack.id) \(outcome)")
            }
            XCTAssertEqual(CosmeticAudioPolicy.gameOverCue(packID: pack.id), .pack(.gameOver))
            // Exactly one primary voice and never the neutral `tap` sound for a scored tap.
            for o in allOutcomes {
                if case .pack(let e) = CosmeticAudioPolicy.cue(for: o, packID: pack.id) {
                    XCTAssertNotEqual(e, .tap)
                } else {
                    XCTFail("themed pack must route to its own sounds: \(o)")
                }
            }
        }
    }

    // MARK: Haptic policy

    func testDefaultHapticStyleIsIdenticalToLegacyDispatch() {
        for o in allOutcomes {
            XCTAssertEqual(CosmeticHapticPolicy.pulses(for: o, styleID: "default"),
                           [HapticPulse(style: legacyHaptic(o), intensity: nil, delay: 0)], "\(o)")
        }
    }

    func testThemedHapticStylesStaySubtle() {
        let frequent = [TapAccuracy.perfect, .great, .good].map { TapSoundOutcome(accuracy: $0) }
        for style in ["bouncy", "soft", "punchy"] {
            for o in allOutcomes {
                let pulses = CosmeticHapticPolicy.pulses(for: o, styleID: style)
                XCTAssertTrue((1...2).contains(pulses.count), "\(style) \(o)")
                XCTAssertEqual(pulses.first?.delay, 0, "first pulse must be immediate")
                for p in pulses {
                    XCTAssertLessThanOrEqual(p.delay, 0.1)
                    if let i = p.intensity { XCTAssertTrue((0...1).contains(i)) }
                }
            }
            for o in frequent {
                for p in CosmeticHapticPolicy.pulses(for: o, styleID: style) {
                    XCTAssertTrue([.light, .soft, .rigid].contains(p.style),
                                  "\(style) uses \(p.style.rawValue) on a frequent event")
                }
            }
        }
    }

    // MARK: Files & decoding

    func testFileDurationsWithinLimits() throws {
        let limitsMs: [CosmeticEvent: ClosedRange<Double>] = [
            .tap: 70...220, .good: 70...220, .great: 70...220,
            .perfect: 70...400, .miss: 70...300, .lifeLost: 70...500, .gameOver: 70...900,
        ]
        for pack in themedPacks {
            for (event, names) in pack.files {
                for name in names {
                    let url = try XCTUnwrap(SoundPackLoader.url(forFile: name, packID: pack.id, bundle: .main))
                    let file = try AVAudioFile(forReading: url)
                    let ms = Double(file.length) / file.fileFormat.sampleRate * 1000
                    XCTAssertTrue(limitsMs[event]!.contains(ms), "\(name): \(ms) ms")
                    XCTAssertEqual(file.fileFormat.sampleRate, 44100)
                    XCTAssertEqual(file.fileFormat.channelCount, 1)
                }
            }
        }
    }

    func testDecodeProducesBuffersInEngineFormat() {
        let format = SoundEngine.shared.playerFormat
        for pack in themedPacks {
            let buffers = SoundPackLoader.decode(pack, format: format)
            for event in CosmeticEvent.allCases {
                let decoded = buffers[event] ?? []
                XCTAssertEqual(decoded.count, pack.files[event]?.count, "\(pack.id) \(event)")
                for b in decoded {
                    XCTAssertEqual(b.format, format)
                    XCTAssertGreaterThan(b.frameLength, 0)
                    // Onset at sample 0 (± 2 ms) for tap-path sounds: first audible
                    // sample (-40 dB re peak) within 88 frames.
                    let data = b.floatChannelData![0]
                    let n = Int(b.frameLength)
                    var peak: Float = 0
                    for i in 0..<n { peak = max(peak, abs(data[i])) }
                    XCTAssertLessThan(peak, 0.75, "\(pack.id) \(event) peak above -3 dBFS ceiling")
                    if event != .gameOver {
                        let onset = (0..<n).first { abs(data[$0]) >= peak * 0.01 } ?? n
                        XCTAssertLessThanOrEqual(onset, 88, "\(pack.id) \(event) onset \(onset) frames")
                    }
                }
            }
        }
    }

    func testDecodeConvertsToForeignFormat() throws {
        let pack = try XCTUnwrap(SoundPackCatalog.pack(id: "boom_mode"))
        let url = try XCTUnwrap(SoundPackLoader.url(forFile: pack.files[.perfect]![0], packID: pack.id, bundle: .main))
        let target = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(SoundPackLoader.decodeFile(at: url, to: target))
        XCTAssertEqual(buffer.format, target)
        let srcFrames = Double(try AVAudioFile(forReading: url).length)
        XCTAssertEqual(Double(buffer.frameLength), srcFrames * 48000 / 44100, accuracy: 200)
    }

    // MARK: Engine routing

    func testActivePackPreloadsAndPreviewNeverChangesActivePack() {
        let engine = SoundEngine.shared
        engine.setActiveSoundPack("boom_mode")
        XCTAssertEqual(engine.activeSoundPackID, "boom_mode")
        XCTAssertTrue(waitReady("boom_mode"))
        let active = engine.cachedSoundPackBuffers("boom_mode")
        XCTAssertEqual(active?.keys.count, CosmeticEvent.allCases.count)
        XCTAssertEqual(active?[.perfect]?.first?.format, engine.playerFormat)

        engine.previewSound(.perfect, packID: "quack_attack")
        XCTAssertTrue(waitReady("quack_attack"))
        XCTAssertEqual(engine.activeSoundPackID, "boom_mode", "preview must not change the active pack")
        XCTAssertEqual(engine.cachedSoundPackIDs(), ["boom_mode", "quack_attack"])

        // Cache stays bounded: previewing a third pack evicts the previous preview.
        engine.previewSound(.miss, packID: "purrfect_tap")
        XCTAssertTrue(waitReady("purrfect_tap"))
        XCTAssertEqual(engine.cachedSoundPackIDs(), ["boom_mode", "purrfect_tap"])
        engine.stopPreview()
        XCTAssertEqual(engine.activeSoundPackID, "boom_mode")

        // Unknown id → default (built-in, nothing to load).
        engine.setActiveSoundPack("no_such_pack")
        XCTAssertEqual(engine.activeSoundPackID, "default")
    }

    func testSoundOffMeansPreviewDoesNotLoadOrPlay() {
        let engine = SoundEngine.shared
        UserDefaults.standard.set(false, forKey: "perfecttap_sound")
        engine.refreshSettings()
        engine.setActiveSoundPack("default")
        let cold = coldPackID()
        engine.previewSound(.perfect, packID: cold)
        // Nothing was enqueued, so the pack is neither cached nor loading.
        XCTAssertFalse(waitReady(cold))
    }

    // MARK: Performance (simulator numbers — indicative only)

    func testTapOutcomeMainThreadCostAndPreloadTime() {
        let engine = SoundEngine.shared

        // Off-main preload cost, measured synchronously here.
        for pack in themedPacks {
            let t0 = CACurrentMediaTime()
            _ = SoundPackLoader.decode(pack, format: engine.playerFormat)
            print(String(format: "[CosmeticAudioPerf] decode %@: %.2f ms", pack.id, (CACurrentMediaTime() - t0) * 1000))
        }

        // End-to-end cold load: setActiveSoundPack → buffers cached.
        engine.setActiveSoundPack("default")
        let cold = coldPackID()
        let t0 = CACurrentMediaTime()
        engine.setActiveSoundPack(cold)
        XCTAssertTrue(waitReady(cold))
        print(String(format: "[CosmeticAudioPerf] setActiveSoundPack→ready %@ (cold): %.2f ms",
                     cold, (CACurrentMediaTime() - t0) * 1000))

        let outcomes: [TapSoundOutcome] = [
            TapSoundOutcome(accuracy: .perfect), TapSoundOutcome(accuracy: .great),
            TapSoundOutcome(accuracy: .good), TapSoundOutcome(accuracy: .miss, lostLife: true),
        ]
        for packID in ["quack_attack", "default"] {
            engine.setActiveSoundPack(packID)
            XCTAssertTrue(waitReady(packID))
            var worst = 0.0
            let start = CACurrentMediaTime()
            for i in 0..<200 {
                let s = CACurrentMediaTime()
                engine.playTapOutcome(outcomes[i % outcomes.count])
                worst = max(worst, CACurrentMediaTime() - s)
            }
            let total = CACurrentMediaTime() - start
            let avgUs = total / 200 * 1_000_000
            print(String(format: "[CosmeticAudioPerf] playTapOutcome x200 (%@): total %.2f ms, avg %.1f µs, max %.1f µs",
                         packID, total * 1000, avgUs, worst * 1_000_000))
            // It only enqueues: generous bound so a loaded CI simulator doesn't flake.
            XCTAssertLessThan(avgUs, 500, "playTapOutcome must only enqueue (avg \(avgUs) µs)")
        }
    }
}
