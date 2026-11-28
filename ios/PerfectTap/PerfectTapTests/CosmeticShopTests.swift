import XCTest
#if canImport(PerfectTap)
@testable import PerfectTap
#endif

/// Cosmetic Studio shop: ShopItem bridge, fair bundle pricing, legacy bundle
/// purchase, authoritative "preview only", Studio flag, legacy categories
/// unchanged, StoreKit ids unchanged, Preview Studio isolation.
@MainActor
final class CosmeticShopTests: XCTestCase {

    private var savedProfile: PlayerProfile?
    private var originalService: EconomyService!

    private let quack = CosmeticCatalog.bundle(collectionID: "quack_attack")!
    private let duckButtonID = "quack_attack.tapButton"
    private let pawLivesID = "purrfect_tap.lifeIcon"

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
    }

    private var economy: EconomyManager { .shared }
    private func profile() -> PlayerProfile { economy.currentProfile() }
    private func coins() -> Int { profile().coins }
    private func item(_ id: String) -> CosmeticItem { CosmeticCatalog.item(id: id)! }
    private func setOwned(_ ids: [String], coins: Int = 5_000) {
        economy.updateProfile(syncCloud: false) { $0.ownedItems = ids; $0.coins = coins }
    }
    private func listValue(_ ids: [String]) -> Int { ids.reduce(0) { $0 + ShopItem.cosmeticPrice($1) } }

    // MARK: Bundle pricing

    func testBundlePriceWhenNothingOwnedIsTheFullBundlePrice() {
        let quote = economy.bundleQuote(quack)
        XCTAssertEqual(quote.ownedCount, 0)
        XCTAssertEqual(quote.totalCount, 9)
        XCTAssertEqual(quote.totalListValue, 1_620)
        XCTAssertEqual(quote.completionPrice, ShopItem.cosmeticBundlePrice(quack))
        XCTAssertEqual(quote.completionPrice, 1_100)
        XCTAssertLessThan(quote.completionPrice, quote.missingListValue)
        XCTAssertEqual(quote.savings, 520)
    }

    func testBundlePriceIsProRatedByMissingListValue() {
        setOwned([duckButtonID])   // 300 of 1620 list value owned
        let quote = economy.bundleQuote(quack)
        XCTAssertEqual(quote.ownedCount, 1)
        XCTAssertEqual(quote.missingListValue, 1_320)
        XCTAssertEqual(quote.completionPrice, 896, "round(1100 × 1320 / 1620) = round(896.3)")
        XCTAssertFalse(quote.missingItemIDs.contains(duckButtonID))
    }

    func testBundleFullyOwnedCostsNothing() {
        setOwned(quack.itemIDs)
        let quote = economy.bundleQuote(quack)
        XCTAssertTrue(quote.isComplete)
        XCTAssertEqual(quote.completionPrice, 0)
        XCTAssertEqual(quote.missingItemIDs, [])
    }

    func testBundleRounding() {
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 10, totalListValue: 30, missingListValue: 10), 3)  // 3.33
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 10, totalListValue: 40, missingListValue: 10), 3)  // 2.5 → 3
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 10, totalListValue: 60, missingListValue: 10), 2)  // 1.67
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 1_100, totalListValue: 1_620, missingListValue: 100), 68)
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 1_100, totalListValue: 1_620, missingListValue: 0), 0)
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 1, totalListValue: 10_000, missingListValue: 1), 1,
                       "something missing is never free")
    }

    func testBundleNeverExceedsSumOfMissingItems() {
        // Misconfigured bundle priced above its list value: clamp to the missing sum.
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 2_000, totalListValue: 1_000, missingListValue: 100), 100)
        XCTAssertEqual(CosmeticBundlePricing.completionPrice(bundlePrice: 2_000, totalListValue: 1_000, missingListValue: 1_000), 1_000)
        // Every ownership subset of every real bundle.
        for bundle in CosmeticCatalog.bundles {
            let ids = bundle.itemIDs
            for mask in 0..<(1 << ids.count) {
                let owned = Set(ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
                let quote = CosmeticBundlePricing.quote(for: bundle, bundlePrice: ShopItem.cosmeticBundlePrice(bundle),
                                                        price: ShopItem.cosmeticPrice, isOwned: owned.contains)
                XCTAssertLessThanOrEqual(quote.completionPrice, quote.missingListValue)
                XCTAssertLessThanOrEqual(quote.completionPrice, quote.bundlePrice)
                if quote.isComplete { XCTAssertEqual(quote.completionPrice, 0) } else { XCTAssertGreaterThan(quote.completionPrice, 0) }
            }
        }
    }

    // MARK: Legacy bundle purchase

    func testLegacyBundlePurchaseDeductsOnceAndGrantsAll() {
        XCTAssertFalse(economy.service.isAuthoritative)
        let result = economy.buyCosmeticBundle(quack, expectedPrice: 1_100)
        XCTAssertEqual(result, .purchased(granted: quack.itemIDs, charged: 1_100))
        XCTAssertEqual(coins(), 3_900)
        for id in quack.itemIDs {
            XCTAssertTrue(economy.ownsItem(id), id)
            XCTAssertEqual(profile().ownedItems.filter { $0 == id }.count, 1, "no duplicates for \(id)")
        }
        XCTAssertFalse(profile().ownedItems.contains(quack.id), "a bundle id is never stored as owned")
    }

    func testLegacyBundlePurchaseIsIdempotent() {
        _ = economy.buyCosmeticBundle(quack)
        let afterFirst = coins()
        XCTAssertEqual(economy.buyCosmeticBundle(quack), .alreadyOwned)
        XCTAssertEqual(economy.buyCosmeticBundle(quack, expectedPrice: 1_100), .alreadyOwned)
        XCTAssertEqual(coins(), afterFirst, "a repeated / double-tapped bundle is never charged twice")
        XCTAssertEqual(profile().ownedItems.count, quack.itemIDs.count)
    }

    func testBundleNeverChargesAlreadyOwnedItems() {
        setOwned([duckButtonID])
        let result = economy.buyCosmeticBundle(quack)
        XCTAssertEqual(result, .purchased(granted: quack.itemIDs.filter { $0 != duckButtonID }, charged: 896))
        XCTAssertEqual(coins(), 5_000 - 896)
        XCTAssertEqual(profile().ownedItems.filter { $0 == duckButtonID }.count, 1)
    }

    func testBundleWithInsufficientCoinsChangesNothing() {
        setOwned(["theme_fire"], coins: 100)
        XCTAssertEqual(economy.buyCosmeticBundle(quack), .insufficientCoins(needed: 1_000))
        XCTAssertEqual(coins(), 100)
        XCTAssertEqual(profile().ownedItems, ["theme_fire"])
    }

    func testBundleRefusesAPriceThePlayerDidNotConfirm() {
        setOwned([duckButtonID])
        XCTAssertEqual(economy.buyCosmeticBundle(quack, expectedPrice: 1_100), .priceChanged(current: 896))
        XCTAssertEqual(coins(), 5_000)
        XCTAssertEqual(profile().ownedItems, [duckButtonID])
    }

    // MARK: Single / multi item purchases (legacy)

    func testSingleCosmeticPurchaseUsesLegacyPath() async {
        let shopItem = ShopItem.cosmetic(item(duckButtonID))!
        XCTAssertEqual(shopItem.category, .cosmetics)
        XCTAssertEqual(shopItem.price, 300)
        let bought = await economy.buyItemForCurrentRollout(shopItem)
        XCTAssertTrue(bought)
        XCTAssertEqual(coins(), 4_700)
        XCTAssertTrue(economy.ownsItem(duckButtonID))
    }

    func testAlreadyOwnedCosmeticIsNotCharged() async {
        setOwned([duckButtonID])
        let again = await economy.buyItemForCurrentRollout(ShopItem.cosmetic(item(duckButtonID))!)
        XCTAssertFalse(again)
        XCTAssertFalse(economy.buyItem(ShopItem.cosmetic(item(duckButtonID))!))
        XCTAssertEqual(economy.buyCosmeticItems([item(duckButtonID)]), .alreadyOwned)
        XCTAssertEqual(coins(), 5_000)
    }

    func testMultiItemUnlockChargesOnlyMissingItemsOnce() {
        setOwned([duckButtonID])
        let items = [item(duckButtonID), item(pawLivesID), item("boom_mode.tapSound"), item(pawLivesID)]
        XCTAssertEqual(economy.cosmeticItemsPrice(items, in: profile()), 200 + 250)
        let result = economy.buyCosmeticItems(items, expectedPrice: 450)
        XCTAssertEqual(result, .purchased(granted: [pawLivesID, "boom_mode.tapSound"], charged: 450))
        XCTAssertEqual(coins(), 4_550)
        XCTAssertEqual(profile().ownedItems.filter { $0 == pawLivesID }.count, 1)
    }

    func testDefaultsAreFreeAndNeverSold() {
        for item in CosmeticCatalog.items where item.isDefault {
            XCTAssertTrue(ShopItem.item(id: item.id)!.isFree)
            XCTAssertTrue(economy.ownsItem(item.id), "Classic \(item.slot) is always owned")
            XCTAssertFalse(economy.canPurchaseCosmetic(item))
        }
        XCTAssertEqual(economy.buyCosmeticItems([CosmeticCatalog.defaultItem(for: .tapButton)]), .unavailable)
        XCTAssertEqual(coins(), 5_000)
    }

    // MARK: Authoritative economy ⇒ preview only

    func testAuthoritativeModeOffersNoCosmeticPurchase() async {
        let h = EconomyHarness(authoritative: true)
        defer { h.cleanUp() }
        h.profile.coins = 5_000
        economy.service = h.service

        XCTAssertFalse(economy.cosmeticPurchasesAvailable)
        XCTAssertFalse(economy.canPurchaseCosmetic(item(duckButtonID)))
        XCTAssertFalse(economy.canPurchaseCosmeticBundle(quack))
        XCTAssertEqual(economy.buyCosmeticBundle(quack), .unavailable)
        XCTAssertEqual(economy.buyCosmeticItems([item(duckButtonID)]), .unavailable)
        let bought = await economy.buyItemForCurrentRollout(ShopItem.cosmetic(item(duckButtonID))!)
        XCTAssertFalse(bought)
        XCTAssertTrue(h.remote.purchases.isEmpty, "cosmetic ids are never sent to the server catalog")
        XCTAssertEqual(coins(), 5_000)
        XCTAssertTrue(profile().ownedItems.isEmpty)

        let flow = CosmeticPurchaseFlow()
        XCTAssertFalse(flow.purchasesAvailable)
        flow.requestItem(item(duckButtonID), spendable: 5_000)
        flow.requestBundle(quack, profile: profile(), spendable: 5_000)
        XCTAssertNil(flow.pending, "no purchase confirmation is offered")
        XCTAssertEqual(flow.message, "Preview only — these cosmetics are coming soon.")
    }

    func testPurchaseFlowAsksForConfirmationWithExactPrice() {
        let flow = CosmeticPurchaseFlow()
        setOwned([duckButtonID])
        flow.requestBundle(quack, profile: profile(), spendable: 5_000)
        guard case .bundle(let quote, _)? = flow.pending else { return XCTFail("expected bundle confirmation") }
        XCTAssertEqual(quote.completionPrice, 896)
        XCTAssertEqual(coins(), 5_000, "requesting never charges")

        flow.pending = nil
        flow.requestItem(item(pawLivesID), spendable: 10)
        XCTAssertNil(flow.pending)
        XCTAssertEqual(flow.message, "Not enough coins. You need 190 more.")
    }

    // MARK: Equip

    func testEquipRefusesUnownedCosmetic() {
        let before = CosmeticLoadoutStore.shared.loadout
        XCTAssertFalse(economy.equipCosmetic(item(duckButtonID)))
        economy.equipItem(ShopItem.cosmetic(item(duckButtonID))!)
        XCTAssertEqual(CosmeticLoadoutStore.shared.loadout, before)
        XCTAssertFalse(economy.isEquipped(ShopItem.cosmetic(item(duckButtonID))!))
    }

    func testDefaultCosmeticsResolveAsEquippedWithDefaultLoadout() {
        guard CosmeticLoadoutStore.shared.loadout == .default else { return }
        for slot in CosmeticSlot.allCases {
            XCTAssertTrue(economy.isCosmeticEquipped(CosmeticCatalog.defaultItem(for: slot), in: profile()))
        }
    }

    // MARK: Flag / tabs

    func testStudioTabOnlyWhenFlagOn() {
        XCTAssertFalse(ShopView.ShopTab.visible(premium: false, studio: false).contains(.studio))
        XCTAssertFalse(ShopView.ShopTab.visible(premium: true, studio: false).contains(.studio))
        XCTAssertEqual(ShopView.ShopTab.visible(premium: false, studio: false), [.themes, .tapFX, .avatars])
        XCTAssertEqual(ShopView.ShopTab.visible(premium: true, studio: true), [.themes, .tapFX, .avatars, .premium, .studio])
        XCTAssertEqual(ShopView.ShopTab.visible.contains(.studio), FeatureFlags.cosmeticStudioEnabled)
    }

    func testStudioFlagIsOnInDebugBuilds() {
        #if DEBUG
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "PT_COSMETIC_STUDIO_ENABLED") as? String, "YES")
        XCTAssertTrue(FeatureFlags.cosmeticStudioEnabled)
        #endif
    }

    // MARK: Existing categories unaffected

    func testLegacyCategoriesAreUnchanged() {
        XCTAssertEqual(ShopCategory.shopVisible, [.themes, .tapFX, .avatars])
        XCTAssertFalse(ShopCategory.shopVisible.contains(.cosmetics))
        XCTAssertEqual(ShopItem.items(for: .themes).count, 9)
        XCTAssertEqual(ShopItem.items(for: .tapFX).count, 7)
        XCTAssertEqual(ShopItem.items(for: .avatars).count, 10)
        XCTAssertEqual(ShopView.ShopTab.themes.items.map(\.id), ShopItem.themes.map(\.id))
        XCTAssertTrue(ShopView.ShopTab.studio.items.isEmpty)
        XCTAssertEqual(ShopItem.item(id: "theme_fire")?.price, 150)
        XCTAssertEqual(ShopItem.item(id: "avatar_dragon")?.price, 750)

        let ids = ShopItem.allItems.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "item ids stay unique")
        XCTAssertEqual(ShopItem.allItems.filter { $0.category != .cosmetics }.count, 9 + 4 + 7 + 7 + 10 + 10)
    }

    func testLegacyBuyAndEquipStillWorkForThemesFXAndAvatars() {
        let fire = ShopItem.item(id: "theme_fire")!
        XCTAssertTrue(economy.buyItem(fire))
        XCTAssertEqual(coins(), 4_850)
        economy.equipItem(fire)
        XCTAssertEqual(profile().equippedTheme, "fire")
        XCTAssertTrue(economy.isEquipped(fire))

        let ripple = ShopItem.item(id: "fx_ripple")!
        XCTAssertTrue(economy.buyItem(ripple))
        economy.equipItem(ripple)
        XCTAssertEqual(profile().equippedTapFX, "fx_ripple")

        let ninja = ShopItem.item(id: "avatar_ninja")!
        XCTAssertTrue(economy.buyItem(ninja))
        economy.equipItem(ninja)
        XCTAssertEqual(profile().equippedAvatar, "avatar_ninja")
        XCTAssertTrue(economy.ownsItem("theme_default"))
    }

    func testCosmeticBridgeCoversTheCatalog() {
        let nonDefault = CosmeticCatalog.items.filter { !$0.isDefault }
        XCTAssertEqual(ShopItem.cosmetics.count, nonDefault.count)
        XCTAssertEqual(ShopItem.cosmetics.count, 27)
        for item in nonDefault {
            let shopItem = ShopItem.item(id: item.id)
            XCTAssertEqual(shopItem?.category, .cosmetics)
            XCTAssertEqual(shopItem?.price, item.proposedPrice, "legacy config ⇒ proposed price")
            XCTAssertNil(shopItem?.premiumProductID, "cosmetics are never StoreKit products")
            XCTAssertFalse(shopItem?.isFree ?? true)
            XCTAssertEqual(shopItem?.cosmeticItem?.id, item.id)
        }
    }

    func testStoreKitProductIDsAreUnchanged() {
        let expected: Set<String> = [
            "com.perfecttap.coins.500", "com.perfecttap.coins.1200", "com.perfecttap.coins.3000",
            "com.perfecttap.coins.8000", "com.perfecttap.removeads",
            "com.perfecttap.skin.neonpulse", "com.perfecttap.skin.liquidchrome",
            "com.perfecttap.skin.glitchmode", "com.perfecttap.skin.cosmicgold",
        ]
        let all = MonetizationCategory.allCases.flatMap(\.productIDs)
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(Set(all), expected)
        XCTAssertEqual(ShopItem.allItems.compactMap(\.premiumProductID).count, 4)
    }

    func testStudioFilters() {
        setOwned([duckButtonID, pawLivesID])
        let isOwned: (CosmeticItem) -> Bool = { self.economy.isCosmeticOwned($0, in: self.profile()) }
        XCTAssertEqual(CosmeticStudioFilter.owned.items(isOwned: isOwned).map(\.id).sorted(), [pawLivesID, duckButtonID].sorted())
        XCTAssertEqual(CosmeticStudioFilter.effects.items(isOwned: isOwned).count, 5 * 4)
        XCTAssertEqual(Set(CosmeticStudioFilter.sounds.items(isOwned: isOwned).map(\.slot)), [.tapSound, .haptics])
        XCTAssertTrue(CosmeticStudioFilter.collections.items(isOwned: isOwned).isEmpty)
        XCTAssertTrue(CosmeticStudioFilter.tapButtons.items(isOwned: isOwned).contains { $0.isDefault },
                      "Classic stays selectable")
    }

    // MARK: Preview Studio isolation

    private func loadoutDefaultsSnapshot() -> [String: String] {
        UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("pt_cosmetic_loadout") }
            .mapValues { String(describing: $0) }
    }

    private func profileJSON() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(profile())) ?? Data()
    }

    func testPreviewModelNeverWritesLoadoutProfileOrCoins() {
        setOwned([duckButtonID])
        let defaultsBefore = loadoutDefaultsSnapshot()
        let profileBefore = profileJSON()
        let storeBefore = CosmeticLoadoutStore.shared.loadout
        let resolvedBefore = CosmeticLoadoutStore.shared.resolved
        var sounds: [(CosmeticEvent, String)] = []
        var stops = 0

        let model = CosmeticPreviewModel(start: .default, playSound: { sounds.append(($0, $1)) }, stopSound: { stops += 1 })
        model.tryCollection(CosmeticCatalog.collection(id: "boom_mode")!)
        model.select(item(pawLivesID))
        model.select(item("quack_attack.tapSound"))
        for event in CosmeticEvent.allCases { model.fire(event) }
        model.tap()
        for _ in 0..<5 { model.loseLife() }
        XCTAssertEqual(model.lives, 0, "lives clamp at zero")
        model.resetLives()
        XCTAssertEqual(model.lives, CosmeticPreviewModel.maxLives)
        XCTAssertEqual(model.item(for: .lifeIcon).id, pawLivesID, "unowned items preview for real")
        XCTAssertEqual(sounds.last?.1, "quack_attack", "preview sound uses the drafted pack")
        model.stop()
        XCTAssertEqual(stops, 1)

        XCTAssertEqual(loadoutDefaultsSnapshot(), defaultsBefore, "stored loadout untouched")
        XCTAssertEqual(profileJSON(), profileBefore, "profile (coins, owned items, stats) untouched")
        XCTAssertEqual(coins(), 5_000)
        XCTAssertEqual(CosmeticLoadoutStore.shared.loadout, storeBefore)
        XCTAssertEqual(CosmeticLoadoutStore.shared.resolved, resolvedBefore)

        model.resetDraft()
        XCTAssertFalse(model.hasChanges)
    }

    func testPreviewEquipOwnedAppliesOnlyOwnedDraftItems() {
        setOwned([duckButtonID])
        let model = CosmeticPreviewModel(start: .default, playSound: { _, _ in }, stopSound: {})
        model.tryCollection(CosmeticCatalog.collection(id: "quack_attack")!)
        let isOwned: (CosmeticItem) -> Bool = { self.economy.isCosmeticOwned($0, in: self.profile()) }
        XCTAssertEqual(model.unownedItems(isOwned: isOwned).count, 8)
        XCTAssertEqual(economy.cosmeticItemsPrice(model.unownedItems(isOwned: isOwned), in: profile()), 1_620 - 300)

        XCTAssertEqual(economy.cheaperBundle(for: model.unownedItems(isOwned: isOwned), in: profile())?.quote.completionPrice, 896,
                       "a whole missing set is offered at the bundle rate")
        let flow = CosmeticPurchaseFlow()
        flow.requestItems(model.unownedItems(isOwned: isOwned), profile: profile(), spendable: 5_000)
        guard case .bundle(let quote, _)? = flow.pending else { return XCTFail("expected bundle-rate confirmation") }
        XCTAssertEqual(quote.completionPrice, 896)
        XCTAssertNil(economy.cheaperBundle(for: [item(pawLivesID)], in: profile()))

        var equipped: [String] = []
        let applied = model.equipOwned(isOwned: isOwned) { equipped.append($0.id); return true }
        XCTAssertEqual(applied, [duckButtonID])
        XCTAssertEqual(equipped, [duckButtonID], "unowned draft items are never equipped")
    }

    func testPreviewStartsFromEquippedLookAndAppliesFocus() {
        let model = CosmeticPreviewModel(equipped: .defaults, focus: .item(item(pawLivesID)))
        XCTAssertEqual(model.item(for: .lifeIcon).id, pawLivesID)
        XCTAssertEqual(model.item(for: .tapButton).id, CosmeticCatalog.defaultItemID(for: .tapButton))
        XCTAssertTrue(model.hasChanges)
        model.resetDraft()
        XCTAssertEqual(model.item(for: .lifeIcon).id, CosmeticCatalog.defaultItemID(for: .lifeIcon))
    }

    // MARK: QA-08 — preview audio = gameplay audio

    /// The sound gameplay's policy picks for a GOOD tap, as a previewable event.
    private func gameplayGoodEvent(packID: String) -> CosmeticEvent {
        switch CosmeticAudioPolicy.cue(for: TapSoundOutcome(accuracy: .good), packID: packID) {
        case .pack(let event): return event
        case .tone(let tone):
            XCTAssertEqual(tone, .good)
            return .good   // previewSound(.good) plays the classic GOOD tone
        case .silent: XCTFail("a GOOD tap is never silent"); return .tap
        }
    }

    func testPreviewTapPlaysWhatAGoodTapPlaysForEveryPack() {
        XCTAssertFalse(SoundPackCatalog.all.isEmpty)
        for pack in SoundPackCatalog.all {
            let expected = gameplayGoodEvent(packID: pack.id)
            XCTAssertEqual(CosmeticPreviewModel.soundEvent(forPreview: .tap, packID: pack.id), expected, pack.id)
            XCTAssertEqual(expected, .good, "\(pack.id): a GOOD tap plays the pack's good sound")
            for event in CosmeticEvent.allCases {
                XCTAssertNotEqual(CosmeticPreviewModel.soundEvent(forPreview: event, packID: pack.id), .tap,
                                  "\(pack.id) \(event): the preview never plays the unused tap sound")
            }
        }
    }

    func testPreviewTapButtonFiresGoodEffectSoundAndHaptic() {
        var sounds: [(CosmeticEvent, String)] = []
        var haptics: [CosmeticEvent] = []
        let model = CosmeticPreviewModel(start: .default, playSound: { sounds.append(($0, $1)) }, stopSound: {},
                                         playHaptic: { event, _ in haptics.append(event) })
        model.tryCollection(CosmeticCatalog.collection(id: "quack_attack")!)
        sounds.removeAll(); haptics.removeAll()

        model.tap()
        XCTAssertEqual(sounds.map(\.0), [.good])
        XCTAssertEqual(sounds.map(\.1), ["quack_attack"])
        XCTAssertEqual(haptics, [.good])
        XCTAssertEqual(model.trigger?.event, .good, "Tap Effect fires as on a GOOD tap")

        // Picking a Tap Effect previews it as a GOOD tap too (not `.tap`).
        model.select(item("boom_mode.tapEffect"))
        XCTAssertEqual(model.trigger?.event, .good)
    }

    func testPreviewMomentButtonsMatchGameplayPolicy() {
        let themed: [CosmeticEvent: CosmeticEvent] = [.good: .good, .great: .great, .perfect: .perfect,
                                                      .miss: .miss, .lifeLost: .lifeLost, .gameOver: .gameOver]
        for (moment, expected) in themed {
            XCTAssertEqual(CosmeticPreviewModel.soundEvent(forPreview: moment, packID: "boom_mode"), expected, "\(moment)")
        }
        // Classic: a lost life sounds like the classic miss; game over is silent.
        XCTAssertEqual(CosmeticPreviewModel.soundEvent(forPreview: .lifeLost, packID: "default"), .miss)
        XCTAssertNil(CosmeticPreviewModel.soundEvent(forPreview: .gameOver, packID: "default"))
        XCTAssertEqual(CosmeticPreviewModel.soundEvent(forPreview: .great, packID: "default"), .great)

        var sounds: [CosmeticEvent] = []
        let model = CosmeticPreviewModel(start: .default, playSound: { e, _ in sounds.append(e) }, stopSound: {},
                                         playHaptic: { _, _ in })
        model.fire(.gameOver)
        XCTAssertTrue(sounds.isEmpty, "classic game over plays nothing, as in gameplay")
        model.loseLife()
        XCTAssertEqual(sounds, [.miss])
        XCTAssertEqual(model.trigger?.event, .lifeLost)
    }

    // MARK: QA-19 — one coin formatter

    func testCoinFormatterGroupsThousands() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(CoinFormat.string(1_100, locale: en), "1,100")
        XCTAssertEqual(CoinFormat.string(300, locale: en), "300")
        XCTAssertEqual(CoinFormat.string(0, locale: en), "0")
        XCTAssertEqual(CoinFormat.string(1_234_567, locale: en), "1,234,567")
        XCTAssertEqual(CoinFormat.coins(1_620, locale: en), "1,620 coins")
        XCTAssertEqual(CoinFormat.coins(1, locale: en), "1 coin")
        XCTAssertEqual(CoinFormat.string(1_100), CoinFormat.string(1_100, locale: .current))
    }

    func testBundleAccessibilityLabelReadsNaturally() {
        let quote = economy.bundleQuote(quack)
        XCTAssertEqual(studioBundleAccessibilityLabel(quote),
                       "Unlock bundle, \(CoinFormat.coins(1_100)), \(CoinFormat.string(1_620)) if bought separately")
        setOwned([duckButtonID])
        XCTAssertEqual(studioBundleAccessibilityLabel(economy.bundleQuote(quack)),
                       "Complete set, \(CoinFormat.coins(896)), \(CoinFormat.string(1_320)) if bought separately")
    }

    func testStudioSourcesUseTheShopCoinGlyphNotTheEmoji() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Views/Profile/CosmeticStudio")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path), !files.isEmpty else {
            throw XCTSkip("sources not readable from the test host: \(dir.path)")
        }
        for name in files where name.hasSuffix(".swift") {
            let source = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(source.contains("\\u{1FA99}") || source.contains("\u{1FA99}"), "\(name) uses the coin emoji")
        }
        XCTAssertEqual(StudioStyle.coinSymbol, "dollarsign.circle.fill", "same glyph as the shop balance row")
    }

    // MARK: QA-17 — per-render state computed once

    func testRenderStateLooksUpEachItemOnceAndMatchesEconomy() {
        setOwned([duckButtonID, pawLivesID, "quack_attack.tapSound"])
        economy.equipCosmetic(item(duckButtonID))
        economy.equipCosmetic(item(pawLivesID))
        defer { CosmeticLoadoutStore.shared.equip(CosmeticCatalog.defaultItem(for: .tapButton))
                CosmeticLoadoutStore.shared.equip(CosmeticCatalog.defaultItem(for: .lifeIcon)) }
        let p = profile()
        var ownedLookups = 0
        var priceLookups = 0
        let state = CosmeticStudioRenderState(loadout: CosmeticLoadoutStore.shared.loadout, spendable: 500,
                                              isOwned: { ownedLookups += 1; return EconomyManager.isOwned($0, in: p) },
                                              price: { priceLookups += 1; return ShopItem.cosmeticPrice($0) })
        let nonDefault = CosmeticCatalog.items.filter { !$0.isDefault }.count
        XCTAssertLessThanOrEqual(ownedLookups, CosmeticCatalog.items.count, "one ownership lookup per item at most")
        XCTAssertEqual(priceLookups, nonDefault, "one price lookup per purchasable item")

        // Reading every card (as a render does) performs no further lookups.
        for item in CosmeticCatalog.items {
            let card = state.card(for: item)
            XCTAssertEqual(card.owned, economy.isCosmeticOwned(item, in: p), item.id)
            XCTAssertEqual(card.equipped, economy.isCosmeticEquipped(item, in: p), item.id)
            XCTAssertEqual(card.price, ShopItem.cosmeticPrice(item.id), item.id)
            XCTAssertEqual(card.affordable, 500 >= card.price, item.id)
        }
        for bundle in CosmeticCatalog.bundles {
            XCTAssertEqual(state.quote(for: bundle), economy.bundleQuote(bundle, in: p), bundle.id)
        }
        XCTAssertLessThanOrEqual(ownedLookups, CosmeticCatalog.items.count)
        XCTAssertEqual(priceLookups, nonDefault)

        XCTAssertTrue(state.card(for: item(duckButtonID)).equipped)
        XCTAssertEqual(state.card(for: item(duckButtonID)).accessibilityValue, "Equipped")
        XCTAssertEqual(state.card(for: item("quack_attack.tapSound")).accessibilityValue, "Owned")
        XCTAssertEqual(state.card(for: CosmeticCatalog.defaultItem(for: .tapButton)).accessibilityValue, "Free",
                       "Classic is owned and not equipped while the duck button is")
        let locked = state.card(for: item("boom_mode.tapButton"))
        XCTAssertEqual(locked.accessibilityValue,
                       "Locked, \(CoinFormat.coins(locked.price))" + (locked.affordable ? "" : ", not enough coins"))
    }
}
