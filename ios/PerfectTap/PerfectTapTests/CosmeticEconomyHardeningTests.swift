import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Agent B (economy integration & security): QA-13 canonical ownership,
/// QA-17 O(1) lookups, QA-18 double-charge protection, and the prepared
/// cross-device loadout sync (docs/cosmetics/LOADOUT_SYNC_CONTRACT.md).
@MainActor
final class CosmeticEconomyHardeningTests: XCTestCase {

    private var savedProfile: PlayerProfile?
    private var originalService: EconomyService!

    private let duckButtonID = "quack_attack.tapButton"
    private let quack = CosmeticCatalog.bundle(collectionID: "quack_attack")!

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
    private func profile() -> PlayerProfile { economy.currentProfile() }
    private func coins() -> Int { profile().coins }
    private func item(_ id: String) -> CosmeticItem { CosmeticCatalog.item(id: id)! }
    private func profile(owning ids: [String]) -> PlayerProfile {
        var p = PlayerProfile()
        p.ownedItems = ids
        return p
    }

    // MARK: QA-13 — canonical ownership

    func testForgedItemClaimingDefaultIsNotOwned() {
        let forgedDefault = CosmeticItem(id: duckButtonID, slot: .tapButton,
                                         collectionID: CosmeticCatalog.defaultCollectionID, name: "Forged default")
        XCTAssertTrue(forgedDefault.isDefault, "precondition: the forged value claims to be a default")
        XCTAssertFalse(economy.isCosmeticOwned(forgedDefault, in: profile(owning: [])))
        XCTAssertFalse(EconomyManager.isCosmeticOwned(id: duckButtonID, in: profile(owning: [])))
        XCTAssertTrue(economy.isCosmeticOwned(forgedDefault, in: profile(owning: [duckButtonID])),
                      "owned only through ownedItems")
    }

    func testCanonicalDefaultsAreOwnedAndUnknownIdsAreNot() {
        for slot in CosmeticSlot.allCases {
            XCTAssertTrue(economy.isCosmeticOwned(CosmeticCatalog.defaultItem(for: slot), in: profile(owning: [])))
        }
        let unknown = CosmeticItem(id: "nope.tapButton", slot: .tapButton, collectionID: "default", name: "?")
        XCTAssertFalse(economy.isCosmeticOwned(unknown, in: profile(owning: ["nope.tapButton"])),
                       "an id the catalog does not know is never a cosmetic the player owns")
    }

    func testForgedValuesAreRefusedNotReinterpreted() {
        let wrongSlot = CosmeticItem(id: duckButtonID, slot: .haptics, collectionID: "quack_attack", name: "x")
        let wrongCollection = CosmeticItem(id: duckButtonID, slot: .tapButton, collectionID: "boom_mode", name: "x")
        for forged in [wrongSlot, wrongCollection] {
            XCTAssertNil(EconomyManager.canonicalCosmetic(forged))
            XCTAssertFalse(economy.canPurchaseCosmetic(forged))
            XCTAssertNil(ShopItem.cosmetic(forged))
            XCTAssertEqual(economy.buyCosmeticItems([forged]), .unavailable)
        }
        XCTAssertEqual(coins(), 5_000)
        XCTAssertEqual(EconomyManager.canonicalCosmetic(item(duckButtonID)), item(duckButtonID))
        XCTAssertEqual(ShopItem.cosmetic(item(duckButtonID))?.id, duckButtonID)
    }

    // MARK: QA-17 — O(1) lookups with identical answers

    func testIndexedLookupMatchesLinearScanForEveryItem() {
        for shopItem in ShopItem.allItems {
            let linear = ShopItem.allItems.first { $0.id == shopItem.id }
            XCTAssertEqual(ShopItem.item(id: shopItem.id)?.id, linear?.id)
            XCTAssertEqual(ShopItem.item(id: shopItem.id)?.price, linear?.price)
            XCTAssertEqual(ShopItem.item(id: shopItem.id)?.category, linear?.category)
        }
        XCTAssertNil(ShopItem.item(id: "does_not_exist"))
        for c in CosmeticCatalog.items {
            let expected = ShopItem.cosmetics.first { $0.id == c.id }?.price ?? 0
            XCTAssertEqual(ShopItem.cosmeticPrice(c.id), expected, c.id)
        }
        XCTAssertEqual(ShopItem.cosmeticPrice("theme_neon"), 0, "non-cosmetic ids have no cosmetic price")
    }

    /// The cheap per-slot check gives the same answer as the former full
    /// 9-slot resolve, over many loadouts × ownership sets × every item.
    func testCheapEquippedCheckMatchesFullResolve() {
        let collections = CosmeticCatalog.collections
        var loadouts: [CosmeticLoadout] = [.default]
        for c in collections {
            var l = CosmeticLoadout(); l.apply(collection: c); loadouts.append(l)
        }
        var mixed = CosmeticLoadout()
        for (i, slot) in CosmeticSlot.allCases.enumerated() {
            let c = collections[i % collections.count]
            mixed.selections[slot] = CosmeticItem.makeID(collection: c.id, slot: slot)
        }
        loadouts.append(mixed)
        loadouts.append(CosmeticLoadout(selections: [.tapButton: "garbage", .haptics: duckButtonID]))   // invalid entries

        let allIDs = CosmeticCatalog.items.map(\.id)
        let ownerships: [[String]] = [[], allIDs, allIDs.enumerated().filter { $0.offset % 2 == 0 }.map(\.element),
                                      [duckButtonID]]
        for loadout in loadouts {
            for owned in ownerships {
                let p = profile(owning: owned)
                let resolved = ResolvedCosmetics.resolve(loadout) { EconomyManager.isOwned($0, in: p) }
                for c in CosmeticCatalog.items {
                    let full = resolved.item(for: c.slot).id == c.id
                    XCTAssertEqual(EconomyManager.isCosmeticEquipped(c, loadout: loadout, in: p), full,
                                   "\(c.id) loadout=\(loadout.selections) owned=\(owned.count)")
                    XCTAssertEqual(EconomyManager.isCosmeticEquipped(c, in: resolved), full)
                }
            }
        }
    }

    func testLegacyItemLookupsUnchanged() {
        XCTAssertEqual(ShopItem.item(id: "theme_neon")?.category, .themes)
        XCTAssertEqual(ShopItem.item(id: "fx_spark")?.category, .tapFX)
        XCTAssertEqual(ShopItem.item(id: "avatar_cool")?.category, .avatars)
        XCTAssertTrue(ShopItem.item(id: "theme_default")?.isFree ?? false)
        XCTAssertTrue(EconomyManager.isOwned("theme_default", in: profile(owning: [])))
        XCTAssertFalse(EconomyManager.isOwned("theme_neon", in: profile(owning: [])))
    }

    // MARK: QA-18 — double charges

    func testDoubleConfirmOfBundleChargesOnce() async {
        XCTAssertFalse(economy.service.isAuthoritative)
        let quote = economy.bundleQuote(quack)
        let flow = CosmeticPurchaseFlow()
        let request = CosmeticPurchaseFlow.Request.bundle(quote, name: "Quack Attack")
        async let a: Void = flow.confirm(request)
        async let b: Void = flow.confirm(request)
        _ = await (a, b)
        XCTAssertEqual(coins(), 5_000 - quote.completionPrice, "charged exactly once")
        for id in quack.itemIDs {
            XCTAssertEqual(profile().ownedItems.filter { $0 == id }.count, 1, id)
        }
    }

    func testRepeatedCallsAfterSuccessChargeNothing() {
        let quote = economy.bundleQuote(quack)
        XCTAssertEqual(economy.buyCosmeticBundle(quack, expectedPrice: quote.completionPrice),
                       .purchased(granted: quote.missingItemIDs, charged: quote.completionPrice))
        let after = coins()
        XCTAssertEqual(economy.buyCosmeticBundle(quack, expectedPrice: quote.completionPrice), .alreadyOwned)
        XCTAssertEqual(economy.buyCosmeticItems([item(duckButtonID)], expectedPrice: ShopItem.cosmeticPrice(duckButtonID)),
                       .alreadyOwned)
        XCTAssertEqual(coins(), after)
    }

    func testStaleConfirmationAfterPartialPurchaseIsRefused() {
        let staleQuote = economy.bundleQuote(quack)           // shown to the player
        XCTAssertEqual(economy.buyCosmeticItems([item(duckButtonID)]),
                       .purchased(granted: [duckButtonID], charged: ShopItem.cosmeticPrice(duckButtonID)))
        let before = coins()
        guard case .priceChanged = economy.buyCosmeticBundle(quack, expectedPrice: staleQuote.completionPrice) else {
            return XCTFail("a price the player did not confirm must not be charged")
        }
        XCTAssertEqual(coins(), before)
    }

    // MARK: Loadout sync (prepared, not wired)

    func testEncodeOmitsDefaultsAndInvalidSelections() {
        let loadout = CosmeticLoadout(selections: [
            .tapButton: duckButtonID,
            .haptics: CosmeticCatalog.defaultItemID(for: .haptics),
            .lifeIcon: "purrfect_tap.tapButton",       // wrong slot
            .tapSound: "unknown.tapSound",
        ])
        XCTAssertEqual(CosmeticLoadoutSync.encode(loadout), ["tapButton": duckButtonID])
        XCTAssertEqual(CosmeticLoadoutSync.encode(.default), [:])
    }

    func testEncodeDecodeRoundTripForEveryCollection() {
        for c in CosmeticCatalog.collections {
            var l = CosmeticLoadout(); l.apply(collection: c)
            let expected = CosmeticLoadout(selections: l.selections.filter { !(CosmeticCatalog.item(id: $0.value)?.isDefault ?? true) })
            XCTAssertEqual(CosmeticLoadoutSync.decode(CosmeticLoadoutSync.encode(l)), expected, c.id)
        }
    }

    func testDecodeDropsUnknownSlotsIdsAndTypes() {
        let raw: [String: Any] = [
            "tapButton": duckButtonID,
            "sparkleTrail": "quack_attack.sparkleTrail",    // slot from a newer build
            "haptics": "quack_attack.tapButton",            // id of another slot
            "tapSound": 42,                                 // wrong type
            "lifeIcon": "made_up.lifeIcon",                 // unknown id
            "missEffect": CosmeticCatalog.defaultItemID(for: .missEffect),
        ]
        XCTAssertEqual(CosmeticLoadoutSync.decode(raw), CosmeticLoadout(selections: [.tapButton: duckButtonID]))
        XCTAssertEqual(CosmeticLoadoutSync.decode(nil), .default, "old profiles without the field decode to default")
        XCTAssertEqual(CosmeticLoadoutSync.decode(NSNull()), .default)
        XCTAssertEqual(CosmeticLoadoutSync.decode("tapButton"), .default)
        XCTAssertEqual(CosmeticLoadoutSync.decode(["tapButton": duckButtonID] as [String: String]),
                       CosmeticLoadout(selections: [.tapButton: duckButtonID]))
        let oversized = Dictionary(uniqueKeysWithValues: (0...CosmeticLoadoutSync.maxWireEntries).map { ("k\($0)", "v") })
        XCTAssertEqual(CosmeticLoadoutSync.decode(oversized), .default)
    }

    func testDecodeNeverGrantsOwnership() {
        let p = profile(owning: [])
        let decoded = CosmeticLoadoutSync.decode(["tapButton": duckButtonID, "haptics": "boom_mode.haptics"])
        XCTAssertEqual(decoded.selections.count, 2, "a selection is carried …")
        let resolved = ResolvedCosmetics.resolve(decoded) { EconomyManager.isOwned($0, in: p) }
        XCTAssertEqual(resolved, ResolvedCosmetics.resolve(.default) { EconomyManager.isOwned($0, in: p) },
                       "… but renders the defaults when nothing is owned")
        XCTAssertTrue(p.ownedItems.isEmpty)
        let filtered = CosmeticLoadoutSync.decode(["tapButton": duckButtonID, "haptics": "boom_mode.haptics"],
                                                  isOwned: { $0 == "boom_mode.haptics" })
        XCTAssertEqual(filtered, CosmeticLoadout(selections: [.haptics: "boom_mode.haptics"]))
    }

    func testMergeServerWinsExceptPendingLocalSlots() {
        let server = CosmeticLoadout(selections: [.tapButton: "boom_mode.tapButton", .haptics: "boom_mode.haptics"])
        let local = CosmeticLoadout(selections: [.tapButton: duckButtonID, .lifeIcon: "purrfect_tap.lifeIcon"])

        XCTAssertEqual(CosmeticLoadoutSync.merge(server: server, local: local, pendingLocalSlots: []), server,
                       "nothing pending: the server profile wins")
        XCTAssertEqual(CosmeticLoadoutSync.merge(server: server, local: local, pendingLocalSlots: [.tapButton, .lifeIcon]),
                       CosmeticLoadout(selections: [.tapButton: duckButtonID, .lifeIcon: "purrfect_tap.lifeIcon",
                                                    .haptics: "boom_mode.haptics"]))
        XCTAssertEqual(CosmeticLoadoutSync.merge(server: server, local: local, pendingLocalSlots: [.haptics]),
                       CosmeticLoadout(selections: [.tapButton: "boom_mode.tapButton"]),
                       "a pending local reset to default beats the server's choice")
        let dirtyServer = CosmeticLoadout(selections: [.tapButton: "garbage", .tapSound: "quack_attack.haptics"])
        XCTAssertEqual(CosmeticLoadoutSync.merge(server: dirtyServer, local: .default, pendingLocalSlots: []), .default,
                       "merge never keeps invalid ids")
    }

    func testChangedSlots() {
        let a = CosmeticLoadout(selections: [.tapButton: duckButtonID])
        let b = CosmeticLoadout(selections: [.tapButton: duckButtonID, .haptics: "boom_mode.haptics",
                                             .lifeIcon: CosmeticCatalog.defaultItemID(for: .lifeIcon)])
        XCTAssertEqual(CosmeticLoadoutSync.changedSlots(from: a, to: b), [.haptics])
        XCTAssertEqual(CosmeticLoadoutSync.changedSlots(from: b, to: .default), [.tapButton, .haptics])
    }
}
