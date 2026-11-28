# Cosmetic Studio — Ownership & Economy

Owner: Agent D (shop / economy integration). Contract: `INTEGRATION_CONTRACT.md` §1, §5.

## 1. Ownership model

- A cosmetic item id is `<collection>.<slot rawValue>`, e.g. `quack_attack.tapButton`
  (`CosmeticItem.makeID`). Owning it = the id is in `PlayerProfile.ownedItems`.
  No new profile fields, so sync, restore, account switching and server
  `set_profile_item` work unchanged.
- Every cosmetic is bridged to a `ShopItem` (category `.cosmetics`) in
  `ShopItem.cosmetics`. Classic defaults are `ShopItem.cosmeticDefaults` with price
  0, so `isFree` makes them always owned. Both lists are in `ShopItem.allItems`, so
  `ShopItem.item(id:)`, `EconomyManager.isOwned`, the legacy buy, and the restore
  and sync paths need no special cases.
- `.cosmetics` is not in `ShopCategory.shopVisible`: the legacy grid never lists
  cosmetics. The Studio tab shows them.
- A bundle id (`bundle.<collection>`) is **never** stored in `ownedItems`. A
  bundle counts as owned when every item in it is owned.
- Equip: `EconomyManager.equipItem(.cosmetics)` and `equipCosmetic(_:)` check
  ownership first and then call `CosmeticLoadoutStore.shared.equip`. They
  refuse unowned items and change nothing. `isEquipped` means the stored loadout,
  checked against the profile's ownership, renders this item in its slot.
- **Canonical items only (QA-13).** `isCosmeticOwned`, `canPurchaseCosmetic` and
  `ShopItem.cosmetic(_:)` look up the catalog copy (`CosmeticCatalog.item(id:)`). They never
  trust a caller-supplied `isDefault`, `collectionID`, price or availability. A value
  that claims a different slot or collection than the catalog is refused
  (`EconomyManager.canonicalCosmetic` returns nil). A forged value "claiming default" for a
  paid id is not owned.
- **Lookups are O(1) (QA-17).** `ShopItem.allItems` is a stored `static let` with
  an id index (`ShopItem.item(id:)`, `cosmeticPrice`). `isCosmeticEquipped(_:in: profile)`
  checks only the stored selection of the item's own slot. Views that already hold
  `CosmeticLoadoutStore.shared.resolved` can call
  `EconomyManager.isCosmeticEquipped(_:in: resolved)`, which is a dictionary lookup.

## 2. Fair bundle policy (implemented)

```
completion = round(bundlePrice × missingListValue / totalListValue)
             clamped to [1, missingListValue] while anything is missing
completion = 0 and "Owned" when nothing is missing
```

`listValue` is the sum of the items' individual prices. `CosmeticBundlePricing`
(in `Models/ShopItem.swift`) is a pure function that does integer arithmetic and rounds halves up.

Properties (tested over every ownership subset of every bundle):
- You never pay for an item you already own.
- Completing the bundle never costs more than buying the missing items one by one.
- It never costs more than the full bundle price.
- The bundle discount rate is the same for everyone. A player who bought two
  items first gets the same percentage off the rest as a player who buys the
  whole bundle at once.
- When something is missing, the price is at least 1, so a bundle is never free.

Example (Quack Attack, legacy proposal): list value 1,620, bundle 1,100. If you own
the Duck Button (300), the missing list value is 1,320 and you pay
round(1,100 × 1,320 / 1,620) = **896**.

### Alternatives considered

| Policy | Why not |
|---|---|
| Full bundle price always | Charges again for items the player already owns. This is unfair and invites refund requests. |
| Bundle price minus the full price of owned items | Can go to 0 or below while items are still missing. Players who bought single items first get a larger total discount than bundle buyers. |
| Pro-rate by item *count* (price × missing / total items) | A missing 100-coin haptics item would cost as much as a missing 300-coin button. A player could game this by buying the cheap items one by one. |
| Hide the bundle once anything is owned | Takes the discount away from engaged players. The UI is also confusing ("where did the bundle go?"). |
| **Pro-rate by list value (chosen)** | Fair, monotonic and easy to explain ("you pay the bundle rate for what you're missing"). The same integer rule runs on the client and in the proposed server function. |

## 3. Purchase paths

### Legacy economy (authoritative flag OFF — today's builds)

- **Single item:** the unchanged `EconomyManager.buyItemForCurrentRollout(ShopItem)` →
  `LedgerEconomyService.purchaseItem` → `legacyBuy` (check owned, check balance,
  deduct, append, `persistLegacy` = local save + cloud sync).
- **Bundle:** `EconomyManager.buyCosmeticBundle(_:expectedPrice:)`.
- **Several items** (the Preview Studio "Unlock N items" button): `buyCosmeticItems(_:expectedPrice:)`.
  If the unowned draft items are exactly the missing items of one collection and the
  bundle rate is cheaper (`EconomyManager.cheaperBundle`), the Preview Studio shows the
  bundle price and routes the purchase to the bundle instead.
  Both run through the same core. It loads the profile once and computes the missing ids and
  the price. It returns `alreadyOwned` when nothing is missing, `priceChanged` when the price
  is not the confirmed one, and `insufficientCoins` when the balance is too low. Otherwise it
  deducts **once**, appends every missing id (no duplicates) and makes **one**
  `persistProfile` call (the same local save + cloud sync as `updateProfile`). Then it refreshes the loadout store.
- **Double charges (QA-18).** There is no in-flight flag. The former
  `cosmeticPurchaseInFlight` was a no-op: `purchaseCosmetics` is synchronous and
  `@MainActor`, so two calls can never interleave. Four things actually prevent a double charge:
  1. serial execution: check, deduct, grant and persist run with no suspension point, so the
     next call reads the updated profile;
  2. the ownership re-check: a repeat finds nothing missing, returns `.alreadyOwned` and
     charges nothing;
  3. `expectedPrice`: if ownership or price changed after the confirmation, the call returns
     `.priceChanged` and charges nothing;
  4. `CosmeticPurchaseFlow.isPurchasing`, which drops a second `confirm` while one
     is running. This matters for the async single-item path, whose `legacyBuy` re-checks
     ownership as well.
  `.inProgress` is still in the result enum (for `CosmeticPurchaseFlow`'s switch) but is
  never returned. A future asynchronous server bundle path must add its own
  in-flight guard and idempotency key. Tests: `CosmeticQATests.testDoubleConfirmOfSingleItemChargesOnce`,
  `CosmeticEconomyHardeningTests.testDoubleConfirmOfBundleChargesOnce`.
- Analytics: on success the existing `AnalyticsService.logShopItemBought` fires,
  with the item id or bundle id and the coins charged. This is the same event the legacy shop sends.

### Authoritative economy ON

The server catalog (`private.economy_shop_items` for the active config) does not contain the
cosmetic ids. `purchase_economy_item` would answer `item_unavailable`. We do not fake a
purchase:

- `EconomyManager.cosmeticPurchasesAvailable == false`, so `canPurchaseCosmetic` and
  `canPurchaseCosmeticBundle` are false.
- `buyItemForCurrentRollout` refuses `.cosmetics` items before reaching the
  service, so nothing is sent to the server. `buyCosmeticBundle` and `buyCosmeticItems` return
  `.unavailable`.
- UI: no Buy or Unlock buttons. Cards, the action bar and the Preview Studio show
  **"Preview only — coming soon"**, and the Studio tab shows a banner. Preview and
  equipping already-owned items keep working.
- Server proposal (not applied): `supabase/proposals/2026112800_cosmetic_studio_catalog.sql`
  plus `README.md`. It was rebased onto the release/1.2.0 hardening migration. It also registers
  the cosmetic ids (disabled) under every config, so that while the authoritative economy is on, a
  client profile save cannot add them to `owned_items` (F1).

## 4. Preview isolation

`CosmeticPreviewModel` holds a draft `CosmeticLoadout` and resolves it with
`CosmeticLoadoutStore.previewResolved` (no ownership checks). It does not touch
GameViewModel, stats, coins, quests, achievements, leaderboards or analytics. Its only
writes are explicit:
- **Equip owned:** `equipOwned` applies the owned or default items of the draft through
  `EconomyManager.equipCosmetic`, which goes to `CosmeticLoadoutStore.shared.equip`.
- **Unlock:** the same confirmed `CosmeticPurchaseFlow` as the shop.

Sounds go through `SoundEngine.previewSound` / `stopPreview`, and `stopPreview` runs `onDisappear`.
`CosmeticShopTests` covers this: after preview mutations, the UserDefaults loadout keys,
the encoded PlayerProfile, the coins and the loadout store are all unchanged.

## 5. Known limitations / follow-ups

- Cross-device loadout sync needs the PlayerProfile change from contract §6. Ownership already syncs.
  The proposed field, merge rule and server validation are in `LOADOUT_SYNC_CONTRACT.md`.
  The pure helpers are in `Models/Cosmetics/CosmeticLoadoutSync.swift` (not wired).
- No haptic preview in the Studio yet. Agent C's `HapticsEngine` routing could add a
  "Feel" button.
- Authoritative prices for cosmetics exist only in the SQL proposal. The client's
  `EconomyConfig.balancedPremiumRC1.shopPrices` has no cosmetic entries, so in
  authoritative mode the cards show the legacy proposed price, and only as a preview.
- Refunds or revocations of cosmetic items: `EconomyManager.revokeItem` removes the id.
  `CosmeticLoadoutStore.refresh()` (Agent A) then resolves the slot back to the default.
