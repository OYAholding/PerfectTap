import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Ownership / selection rules of the Cosmetic Studio loadout, and catalog
/// integrity. Offline: each test uses its own UserDefaults suite and an
/// injected profile, so nothing touches the real player data.
@MainActor
final class CosmeticLoadoutTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var profile = PlayerProfile()
    private var flagOn = true

    override func setUp() async throws {
        suiteName = "CosmeticLoadoutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        profile = PlayerProfile()
        profile.uid = "user-a"
        flagOn = true
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeStore() -> CosmeticLoadoutStore {
        CosmeticLoadoutStore(defaults: defaults,
                             loadProfile: { [unowned self] in self.profile },
                             isEnabled: { [unowned self] in self.flagOn })
    }

    private func item(_ collection: String, _ slot: CosmeticSlot) -> CosmeticItem {
        CosmeticCatalog.item(id: CosmeticItem.makeID(collection: collection, slot: slot))!
    }

    private func storedJSON(_ selections: [String: String], uid: String = "user-a") {
        let data = try! JSONSerialization.data(withJSONObject: ["selections": selections])
        defaults.set(data, forKey: CosmeticLoadoutStore.storageKey(forUID: uid))
    }

    private func assertAllDefault(_ resolved: ResolvedCosmetics, file: StaticString = #filePath, line: UInt = #line) {
        for slot in CosmeticSlot.allCases {
            XCTAssertEqual(resolved.item(for: slot).id, CosmeticCatalog.defaultItemID(for: slot),
                           "slot \(slot)", file: file, line: line)
        }
        XCTAssertEqual(resolved.soundPackID, CosmeticCatalog.defaultSoundPackID, file: file, line: line)
        XCTAssertEqual(resolved.hapticStyleID, "default", file: file, line: line)
    }

    // MARK: Resolve

    func testDefaultLoadoutResolvesDefaultItemsForAllSlots() {
        let store = makeStore()
        XCTAssertEqual(store.loadout, .default)
        assertAllDefault(store.resolved)
        assertAllDefault(ResolvedCosmetics.defaults)
        assertAllDefault(ResolvedCosmetics.resolve(.default, isOwned: { _ in false }))
        XCTAssertEqual(CosmeticCatalog.defaultItem(for: .perfectEffect).assets.effectStyle, .legacyParticles)
    }

    func testUnownedSelectionResolvesToDefault() {
        storedJSON(["tapButton": "quack_attack.tapButton", "tapSound": "boom_mode.tapSound"])
        let store = makeStore()
        XCTAssertEqual(store.loadout.selections.count, 2, "selection is kept…")
        assertAllDefault(store.resolved)                    // …but grants nothing
    }

    func testOwnedSelectionResolves() {
        profile.ownedItems = ["quack_attack.tapButton", "quack_attack.tapSound"]
        storedJSON(["tapButton": "quack_attack.tapButton", "tapSound": "quack_attack.tapSound"])
        let store = makeStore()
        XCTAssertEqual(store.resolved.item(for: .tapButton).id, "quack_attack.tapButton")
        XCTAssertEqual(store.resolved.soundPackID, "quack_attack")
        XCTAssertTrue(store.resolved.item(for: .lifeIcon).isDefault)
    }

    // MARK: Equip

    func testEquipRefusesUnownedAndChangesNothing() {
        let store = makeStore()
        XCTAssertFalse(store.equip(item("quack_attack", .tapButton)))
        XCTAssertEqual(store.loadout, .default)
        assertAllDefault(store.resolved)
        XCTAssertNil(defaults.data(forKey: CosmeticLoadoutStore.storageKey(forUID: "user-a")))
    }

    func testEquipOwnedPersistsPerAccount() {
        profile.ownedItems = ["purrfect_tap.lifeIcon"]
        let store = makeStore()
        XCTAssertTrue(store.equip(item("purrfect_tap", .lifeIcon)))
        XCTAssertEqual(store.resolved.item(for: .lifeIcon).id, "purrfect_tap.lifeIcon")

        let reopened = makeStore()   // e.g. next launch
        XCTAssertEqual(reopened.resolved.item(for: .lifeIcon).id, "purrfect_tap.lifeIcon")
    }

    func testEquipRejectsForgedItemWithBorrowedID() {
        profile.ownedItems = ["quack_attack.tapButton"]
        let store = makeStore()
        // Owned id, wrong slot: must not be accepted.
        let forged = CosmeticItem(id: "quack_attack.tapButton", slot: .lifeIcon, collectionID: "quack_attack", name: "x")
        XCTAssertFalse(store.equip(forged))
        XCTAssertTrue(store.resolved.item(for: .lifeIcon).isDefault)
    }

    func testEquipDefaultItemClearsSelection() {
        profile.ownedItems = ["boom_mode.haptics"]
        let store = makeStore()
        XCTAssertTrue(store.equip(item("boom_mode", .haptics)))
        XCTAssertEqual(store.resolved.hapticStyleID, "punchy")
        XCTAssertTrue(store.equip(CosmeticCatalog.defaultItem(for: .haptics)))
        XCTAssertNil(store.loadout.selections[.haptics])
        XCTAssertEqual(store.resolved.hapticStyleID, "default")
    }

    func testCollectionEquipEquipsOnlyOwnedItems() {
        profile.ownedItems = ["quack_attack.tapButton", "quack_attack.missEffect"]
        let store = makeStore()
        let quack = CosmeticCatalog.collection(id: "quack_attack")!
        let equipped = store.equip(collection: quack)
        XCTAssertEqual(Set(equipped), ["quack_attack.tapButton", "quack_attack.missEffect"])
        XCTAssertEqual(store.resolved.item(for: .tapButton).id, "quack_attack.tapButton")
        XCTAssertEqual(store.resolved.item(for: .missEffect).id, "quack_attack.missEffect")
        for slot in CosmeticSlot.allCases where slot != .tapButton && slot != .missEffect {
            XCTAssertTrue(store.resolved.item(for: slot).isDefault, "\(slot)")
            XCTAssertNil(store.loadout.selections[slot], "\(slot) must not be selected")
        }
    }

    func testCollectionEquipWithNothingOwnedChangesNothing() {
        let store = makeStore()
        XCTAssertEqual(store.equip(collection: CosmeticCatalog.collection(id: "boom_mode")!), [])
        XCTAssertEqual(store.loadout, .default)
    }

    func testDefaultCollectionAlwaysEquips() {
        profile.ownedItems = ["quack_attack.tapButton"]
        let store = makeStore()
        store.equip(item("quack_attack", .tapButton))
        let equipped = store.equip(collection: CosmeticCatalog.collection(id: "default")!)
        XCTAssertEqual(equipped.count, CosmeticSlot.allCases.count)
        XCTAssertEqual(store.loadout, .default)
        assertAllDefault(store.resolved)
    }

    // MARK: Tampering

    func testTamperedLoadoutJSONGrantsNothing() {
        profile.ownedItems = ["quack_attack.tapButton"]
        storedJSON([
            "tapSound": "boom_mode.tapSound",              // unowned
            "lifeIcon": "quack_attack.tapButton",          // owned id in the wrong slot
            "tapEffect": "nonexistent.tapEffect",          // not in the catalog
            "perfectEffect": "bundle.quack_attack",        // bundle ids are never items
            "futureSlot": "quack_attack.futureSlot",       // unknown slot: dropped
        ])
        let store = makeStore()
        assertAllDefault(store.resolved)
        XCTAssertNil(store.loadout.selections.values.first { $0.contains("futureSlot") })
    }

    func testCorruptLoadoutDataReadsAsDefault() {
        defaults.set(Data("not json".utf8), forKey: CosmeticLoadoutStore.storageKey(forUID: "user-a"))
        let store = makeStore()
        XCTAssertEqual(store.loadout, .default)
        assertAllDefault(store.resolved)
    }

    // MARK: Accounts, refunds, flag

    func testPerAccountIsolation() {
        profile.ownedItems = ["quack_attack.tapButton"]
        let store = makeStore()
        XCTAssertTrue(store.equip(item("quack_attack", .tapButton)))

        // Sign into another account that also owns the item: its own (empty) loadout.
        profile = PlayerProfile()
        profile.uid = "user-b"
        profile.ownedItems = ["quack_attack.tapButton"]
        store.refresh()
        XCTAssertEqual(store.storageKey, "pt_cosmetic_loadout.user-b")
        XCTAssertEqual(store.loadout, .default)
        assertAllDefault(store.resolved)

        // Signed out: anonymous key, still isolated.
        profile = PlayerProfile()
        store.refresh()
        XCTAssertEqual(store.storageKey, "pt_cosmetic_loadout.anon")
        assertAllDefault(store.resolved)

        // Back to A: selection restored.
        profile.uid = "user-a"
        profile.ownedItems = ["quack_attack.tapButton"]
        store.refresh()
        XCTAssertEqual(store.resolved.item(for: .tapButton).id, "quack_attack.tapButton")
    }

    func testAccountWithoutOwnershipCannotUseAnotherAccountsSelection() {
        profile.ownedItems = ["boom_mode.lifeIcon"]
        let store = makeStore()
        store.equip(item("boom_mode", .lifeIcon))
        // Same uid's stored loadout, but ownership was revoked server-side and
        // the account re-synced without the item.
        profile.ownedItems = []
        store.refresh()
        XCTAssertTrue(store.resolved.item(for: .lifeIcon).isDefault)
    }

    func testRefundFallsBackToDefaultAndRepurchaseRestores() {
        profile.ownedItems = ["purrfect_tap.tapButton", "purrfect_tap.tapSound"]
        let store = makeStore()
        store.equip(collection: CosmeticCatalog.collection(id: "purrfect_tap")!)
        XCTAssertEqual(store.resolved.soundPackID, "purrfect_tap")

        profile.ownedItems = ["purrfect_tap.tapButton"]           // refund of the sound pack
        store.refresh()
        XCTAssertEqual(store.resolved.soundPackID, CosmeticCatalog.defaultSoundPackID)
        XCTAssertEqual(store.resolved.item(for: .tapButton).id, "purrfect_tap.tapButton")

        profile.ownedItems.append("purrfect_tap.tapSound")       // bought again
        store.refresh()
        XCTAssertEqual(store.resolved.soundPackID, "purrfect_tap")
    }

    func testFlagOffAlwaysResolvesDefaults() {
        flagOn = false
        profile.ownedItems = CosmeticCatalog.items.map(\.id)
        let store = makeStore()
        XCTAssertTrue(store.equip(item("boom_mode", .tapButton)))  // selection can still be saved
        assertAllDefault(store.resolved)
        flagOn = true
        store.refresh()
        XCTAssertEqual(store.resolved.item(for: .tapButton).id, "boom_mode.tapButton")
    }

    func testFlagShimParsesOverride() {
        defer { CosmeticStudioFlag.overrideForTesting = nil }
        CosmeticStudioFlag.overrideForTesting = true
        XCTAssertTrue(CosmeticStudioFlag.isEnabled)
        CosmeticStudioFlag.overrideForTesting = false
        XCTAssertFalse(CosmeticStudioFlag.isEnabled)
    }

    func testPreviewResolveIgnoresOwnershipButNotSlots() {
        var loadout = CosmeticLoadout()
        loadout.apply(collection: CosmeticCatalog.collection(id: "boom_mode")!)
        let preview = CosmeticLoadoutStore.previewResolved(loadout)
        XCTAssertEqual(preview.item(for: .tapButton).id, "boom_mode.tapButton")
        XCTAssertEqual(preview.soundPackID, "boom_mode")
    }

    // MARK: Persistence format

    func testLoadoutJSONRoundTripsAndToleratesUnknownSlots() throws {
        var loadout = CosmeticLoadout()
        loadout.select(item("quack_attack", .tapButton))
        let data = try JSONEncoder().encode(loadout)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        XCTAssertEqual(object?["selections"]?["tapButton"], "quack_attack.tapButton")
        XCTAssertEqual(try JSONDecoder().decode(CosmeticLoadout.self, from: data), loadout)

        let future = Data(#"{"selections":{"tapButton":"quack_attack.tapButton","sparkleTrail":"x.sparkleTrail"}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CosmeticLoadout.self, from: future), loadout)
    }

    // MARK: Catalog integrity

    func testEverySlotHasAFreeDefault() {
        for slot in CosmeticSlot.allCases {
            let item = CosmeticCatalog.defaultItem(for: slot)
            XCTAssertEqual(item.slot, slot)
            XCTAssertTrue(item.isDefault)
            XCTAssertEqual(item.proposedPrice, 0)
        }
    }

    func testItemIDsAreUniqueAndFollowCollectionDotSlot() {
        let ids = CosmeticCatalog.items.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate item ids")
        for item in CosmeticCatalog.items {
            XCTAssertEqual(item.id, "\(item.collectionID).\(item.slot.rawValue)")
            XCTAssertEqual(CosmeticCatalog.item(id: item.id), item)
        }
        let collectionIDs = CosmeticCatalog.collections.map(\.id)
        XCTAssertEqual(collectionIDs.count, Set(collectionIDs).count)
    }

    func testEveryCollectionCoversAllNineSlots() {
        XCTAssertEqual(CosmeticSlot.allCases.count, 9)
        for collection in CosmeticCatalog.collections {
            let slots = collection.itemIDs.compactMap { CosmeticCatalog.item(id: $0)?.slot }
            XCTAssertEqual(slots.count, collection.itemIDs.count, "\(collection.id) references a missing item")
            XCTAssertEqual(Set(slots), Set(CosmeticSlot.allCases), collection.id)
            XCTAssertEqual(slots.count, 9, collection.id)
            if let hero = collection.heroItemID { XCTAssertNotNil(CosmeticCatalog.item(id: hero)) }
        }
    }

    func testBundlesReferenceExistingItemsOfTheirCollection() {
        XCTAssertNil(CosmeticCatalog.bundle(collectionID: CosmeticCatalog.defaultCollectionID))
        XCTAssertFalse(CosmeticCatalog.bundles.isEmpty)
        for bundle in CosmeticCatalog.bundles {
            XCTAssertEqual(bundle.id, "bundle.\(bundle.collectionID)")
            XCTAssertNil(CosmeticCatalog.item(id: bundle.id), "a bundle id must never be an item id")
            XCTAssertEqual(bundle.itemIDs.count, 9)
            for id in bundle.itemIDs {
                XCTAssertEqual(CosmeticCatalog.item(id: id)?.collectionID, bundle.collectionID, id)
            }
        }
    }

    func testThemedItemsCarryTheAssetsTheirSlotNeeds() {
        for item in CosmeticCatalog.items where !item.isDefault {
            switch item.slot {
            case .tapButton:
                XCTAssertFalse(item.assets.palette.isEmpty, "\(item.id): native button needs a palette")
                XCTAssertNotNil(item.assets.emblemImageName, item.id)
            case .lifeIcon:
                XCTAssertNotNil(item.assets.imageName, item.id)
            case .tapSound:
                XCTAssertEqual(item.assets.soundPackID, item.collectionID, item.id)
            case .haptics:
                XCTAssertNotNil(item.assets.hapticStyleID, item.id)
            case .tapEffect, .perfectEffect, .missEffect, .lifeLostEffect, .gameOverEffect:
                XCTAssertNotNil(item.assets.effectStyle, item.id)
                XCTAssertNotEqual(item.assets.effectStyle, CosmeticEffectStyle.none, item.id)
            }
        }
    }
}
