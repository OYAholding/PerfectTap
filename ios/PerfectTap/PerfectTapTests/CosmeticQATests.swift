import XCTest
import CryptoKit
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Independent QA (Agent E) checks for the Cosmetic Studio — gaps not covered by
/// the implementers' suites. docs/cosmetics/QA_REPORT.md.
@MainActor
final class CosmeticQATests: XCTestCase {

    private var savedProfile: PlayerProfile?
    private var originalService: EconomyService!

    override func setUp() async throws {
        savedProfile = PlayerProfile.load()
        originalService = EconomyManager.shared.service
        var p = PlayerProfile()
        p.coins = 5_000
        p.save()
    }

    override func tearDown() async throws {
        EconomyManager.shared.service = originalService
        if let savedProfile { savedProfile.save() } else { PlayerProfile.clearSaved() }
        CosmeticLoadoutStore.shared.refresh()
    }

    private var economy: EconomyManager { .shared }
    private func coins() -> Int { economy.currentProfile().coins }
    private let duckButtonID = "quack_attack.tapButton"

    /// Repo root on the host (simulator tests can read the Mac file system).
    private var repoIOSDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: DEBUG perf override (-PTForceCosmeticCollection)

    func testForcedCollectionOverrideResolvesEverySlotOfTheCollection() throws {
        #if DEBUG
        let arg = CosmeticLoadoutStore.forceCollectionArgument
        for collection in CosmeticCatalog.collections {
            let resolved = try XCTUnwrap(CosmeticLoadoutStore.forcedResolved(arguments: ["app", arg, collection.id]))
            for slot in CosmeticSlot.allCases {
                XCTAssertEqual(resolved.item(for: slot).collectionID, collection.id, "\(collection.id) \(slot)")
            }
        }
        XCTAssertNil(CosmeticLoadoutStore.forcedResolved(arguments: ["app"]))
        XCTAssertNil(CosmeticLoadoutStore.forcedResolved(arguments: ["app", arg]), "missing value")
        XCTAssertNil(CosmeticLoadoutStore.forcedResolved(arguments: ["app", arg, "bundle.quack_attack"]), "unknown id")
        // The unit-test host is launched without the argument: the real store is unaffected.
        XCTAssertFalse(ProcessInfo.processInfo.arguments.contains(arg))
        #else
        throw XCTSkip("DEBUG-only override")
        #endif
    }

    /// The override (and its ownership bypass) must only exist inside `#if DEBUG`.
    /// (The Release binary is also checked with `strings` — QA_REPORT.md.)
    func testForceOverrideIsCompiledOnlyInDebug() throws {
        let url = repoIOSDir.appendingPathComponent("Models/Cosmetics/CosmeticLoadoutStore.swift")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("source not readable from the test host: \(url.path)")
        }
        var depth = 0, debugDepth: Int? = nil, hits = 0
        for line in source.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#if") {
                depth += 1
                if t == "#if DEBUG", debugDepth == nil { debugDepth = depth }
            } else if t.hasPrefix("#endif") {
                if debugDepth == depth { debugDepth = nil }
                depth -= 1
            }
            if line.contains("PTForceCosmeticCollection") || line.contains("forcedFromLaunchArguments")
                || line.contains("forcedResolved(") {
                hits += 1
                XCTAssertNotNil(debugDepth, "outside #if DEBUG: \(t)")
            }
        }
        XCTAssertGreaterThanOrEqual(hits, 3)
    }

    // MARK: Manifests ↔ catalog ↔ bundle

    private struct AudioManifest: Decodable {
        struct Sound: Decodable { let id: String; let pack: String; let event: String; let file: String; let bytes: Int; let sha256: String }
        let sounds: [Sound]
    }

    func testAudioManifestMatchesSoundPackCatalogAndBundledFiles() throws {
        // Not shipped in the app (QA-14); read from the source tree (simulator
        // tests can see the host file system).
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Sounds/audio_manifest.json")
        XCTAssertNil(Bundle.main.url(forResource: "audio_manifest", withExtension: "json"),
                     "audio_manifest.json must not ship in the app")
        let manifest = try JSONDecoder().decode(AudioManifest.self, from: Data(contentsOf: manifestURL))
        let manifestIDs = Set(manifest.sounds.map(\.id))
        let catalogFiles = Set(SoundPackCatalog.all.flatMap(\.allFileNames))
        XCTAssertEqual(manifestIDs, catalogFiles, "manifest and SoundPackCatalog disagree")
        XCTAssertEqual(manifest.sounds.count, manifestIDs.count, "duplicate manifest ids")

        for sound in manifest.sounds {
            let url = try XCTUnwrap(SoundPackLoader.url(forFile: sound.id, packID: sound.pack, bundle: .main), sound.id)
            let data = try Data(contentsOf: url)
            XCTAssertEqual(data.count, sound.bytes, "\(sound.id) size")
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, sound.sha256, "\(sound.id) differs from the manifest")
            XCTAssertNotNil(CosmeticEvent(rawValue: sound.event), sound.event)
        }

        // No orphan CAF in the bundle.
        let bundled = (Bundle.main.urls(forResourcesWithExtension: "caf", subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
        let orphans = Set(bundled).subtracting(catalogFiles)
        XCTAssertTrue(orphans.isEmpty, "bundled CAF files not used by any pack: \(orphans.sorted())")
    }

    /// Every cosmetic imageset is referenced by the catalog and every catalog
    /// name is either an imageset or on the documented "not produced" list.
    func testAssetCatalogAndCosmeticCatalogAgree() throws {
        let dir = repoIOSDir.appendingPathComponent("Assets.xcassets/Cosmetics")
        guard let enumerator = FileManager.default.enumerator(atPath: dir.path) else {
            throw XCTSkip("asset catalog not readable from the test host")
        }
        let imagesets = Set(enumerator.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".imageset") }
            .map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".imageset", with: "") })
        let referenced = Set(CosmeticCatalog.items.flatMap {
            [$0.assets.imageName, $0.assets.secondaryImageName, $0.assets.emblemImageName].compactMap { $0 }
        })
        XCTAssertTrue(imagesets.subtracting(referenced).isEmpty, "orphan imagesets: \(imagesets.subtracting(referenced).sorted())")
        let missing = referenced.subtracting(imagesets)
        // Text-free button backgrounds are intentionally not produced (native capsule fallback).
        XCTAssertEqual(missing, ["cos_quack_button", "cos_quack_button_pressed", "cos_paw_button",
                                 "cos_paw_button_pressed", "cos_boom_button", "cos_boom_button_pressed"])
    }

    // MARK: Purchases / tamper

    /// Two confirmations of the same single-item request (double tap on the
    /// alert button, two Tasks) charge once.
    func testDoubleConfirmOfSingleItemChargesOnce() async {
        XCTAssertFalse(economy.service.isAuthoritative)
        let item = CosmeticCatalog.item(id: duckButtonID)!
        let flow = CosmeticPurchaseFlow()
        let request = CosmeticPurchaseFlow.Request.item(item, price: 300)
        async let a: Void = flow.confirm(request)
        async let b: Void = flow.confirm(request)
        _ = await (a, b)
        XCTAssertEqual(coins(), 4_700, "charged exactly once")
        XCTAssertEqual(economy.currentProfile().ownedItems.filter { $0 == duckButtonID }.count, 1)
    }

    /// A caller-built CosmeticItem cannot lower the price or pose as a free default.
    func testForgedCosmeticItemCannotChangePriceOrBeEquippedUnowned() {
        let forgedCheap = CosmeticItem(id: duckButtonID, slot: .tapButton, collectionID: "quack_attack",
                                       name: "Forged", proposedPrice: 1)
        XCTAssertEqual(economy.buyCosmeticItems([forgedCheap]), .purchased(granted: [duckButtonID], charged: 300),
                       "price always comes from the catalog/config, never from the item value")

        economy.updateProfile(syncCloud: false) { $0.ownedItems = []; $0.coins = 5_000 }
        let forgedDefault = CosmeticItem(id: duckButtonID, slot: .tapButton, collectionID: CosmeticCatalog.defaultCollectionID,
                                         name: "Forged default")
        XCTAssertFalse(economy.canPurchaseCosmetic(forgedDefault))
        XCTAssertFalse(economy.equipCosmetic(forgedDefault), "unowned item must not equip via a forged default")
        XCTAssertEqual(CosmeticLoadoutStore.shared.resolved.item(for: .tapButton).id,
                       CosmeticCatalog.defaultItemID(for: .tapButton))
    }

    /// Fair bundle rule, exhaustively over every owned subset of every bundle:
    /// never more than the missing items one by one, never free while something
    /// is missing, and owned value + completion is never below the full bundle
    /// price (splitting a purchase can't beat the bundle).
    func testBundleCompletionPropertiesForEveryOwnedSubset() {
        for bundle in CosmeticCatalog.bundles {
            let ids = bundle.itemIDs
            let full = ShopItem.cosmeticBundlePrice(bundle)
            for mask in 0..<(1 << ids.count) {
                let owned = Set(ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
                let q = CosmeticBundlePricing.quote(for: bundle, bundlePrice: full, price: ShopItem.cosmeticPrice,
                                                    isOwned: { owned.contains($0) })
                let ownedValue = owned.reduce(0) { $0 + ShopItem.cosmeticPrice($1) }
                if q.isComplete {
                    XCTAssertEqual(q.completionPrice, 0)
                } else {
                    XCTAssertGreaterThanOrEqual(q.completionPrice, 1)
                    XCTAssertLessThanOrEqual(q.completionPrice, q.missingListValue)
                    XCTAssertGreaterThanOrEqual(ownedValue + q.completionPrice, full,
                                                "\(bundle.id) owned=\(owned.sorted()) splits below the bundle price")
                }
            }
        }
    }

    // MARK: Audio

    /// The final-tap rule in GameViewModel relies on this: only themed packs have
    /// a game-over sting (default stays silent and keeps the old tap sound).
    func testOnlyThemedPacksHaveAGameOverSting() {
        let engine = SoundEngine.shared
        defer { engine.setActiveSoundPack(SoundPackCatalog.defaultPackID) }
        engine.setActiveSoundPack(SoundPackCatalog.defaultPackID)
        XCTAssertFalse(engine.activePackHasGameOverSound)
        for id in ["quack_attack", "purrfect_tap", "boom_mode"] {
            engine.setActiveSoundPack(id)
            XCTAssertTrue(engine.activePackHasGameOverSound, id)
        }
        engine.setActiveSoundPack("removed_pack")
        XCTAssertEqual(engine.activeSoundPackID, SoundPackCatalog.defaultPackID, "unknown pack ⇒ default")
        XCTAssertFalse(engine.activePackHasGameOverSound)
    }
}
