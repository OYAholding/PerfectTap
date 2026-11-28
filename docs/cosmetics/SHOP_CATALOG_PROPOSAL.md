# Cosmetic Studio — Proposed Shop Catalog

> **UNAPPROVED — owner decision.** These numbers are engineering proposals.
> Debug builds show them with a "DEBUG: proposed prices" note. Release builds have the
> Studio flag OFF (`PT_COSMETIC_STUDIO_ENABLED = NO`).

The live price is always `EconomyConfig.current.shopPrice(itemID:fallback:)`. The
fallback is the catalog's `proposedPrice` (`Models/Cosmetics/CosmeticCatalog.swift`).
The authoritative column is the candidate used in
`supabase/proposals/2026112800_cosmetic_studio_catalog.sql`.

## Reference points

| Existing (legacy coins) | Range |
|---|---|
| Themes | 75 – 600 (Matrix 600 legendary) |
| Tap FX | 100 – 400 |
| Avatars | 100 – 750 |

The authoritative `balanced-premium-rc1` catalog is about **3.5×** legacy on average
(themes 250–2,500, Tap FX 250–2,500, avatars 250–2,800). The authoritative column
below uses the same factor, rounded to 50.

**Earn rate (legacy, estimate).** A game pays `max(3, score / 50)` plus a combo bonus.
A typical 1,000–1,500 point game is roughly 20–35 coins. The daily reward cycle averages
about 94 coins a day (25…250). A player with 10 games a day therefore earns about
300–450 coins a day. These are rough estimates from `EconomyConfig.legacy`. The game
has no telemetry for this.

| Purchase | Legacy price | ≈ games (25 coins/game) | ≈ days (10 games + daily) |
|---|---|---|---|
| Cheapest slot item (Haptics) | 100 | 4 | < 1 |
| Tap button (hero item) | 300 | 12 | ~1 |
| Full bundle | 1,100 | 44 | ~3 |
| All 3 bundles | 3,300 | 132 | ~9 |

## Items (per collection — identical structure for Quack Attack, Purrfect Tap, Boom Mode)

| Slot | Quack Attack | Purrfect Tap | Boom Mode | Rarity | Legacy price | Authoritative candidate | Rationale |
|---|---|---|---|---|---|---|---|
| Tap Button | Duck Button | Paw Button | Bomb Button | Epic | 300 | 1,000 | Most visible item (on screen every tap). Priced like an epic theme (Gold 300). |
| Sounds | Quack Pack | Purr Pack | Boom Pack | Epic | 250 | 850 | A full 7-voice pack. Changes the feel strongly. Below the button. |
| Life Icons | Duck Lives | Paw Lives | Bomb Lives | Rare | 200 | 700 | Small HUD element. Like a rare theme (Ice 200). |
| Tap Effect | Water Splash | Pink Ripple | Spark Flick | Rare | 150 | 500 | Every tap, subtle. Like the Hearts Tap FX (150). |
| Perfect Effect | Golden Stars | Magic Sparkle | Golden Shockwave | Epic | 200 | 700 | The reward moment. Like the Stars Tap FX (250), a little cheaper because it is one event only. |
| Miss Effect | Panic Splash | Claw Swipe | Fizzle | Rare | 120 | 400 | Shown rarely by good players. |
| Life Lost Effect | Feather Drift | Fluff Burst | Cartoon Boom | Rare | 150 | 500 | Lives modes only. |
| Game Over Effect | Duck Panic | Dizzy Kitty | Final Boom | Epic | 150 | 500 | Once per round. |
| Haptics | Bouncy | Soft | Punchy | Common | 100 | 350 | Invisible and device-dependent, so it has the cheapest entry point. |
| **List value** | | | | | **1,620** | **5,500** | |

All 27 item ids follow `<collection>.<slot>`: `quack_attack.tapButton`, `quack_attack.tapSound`, `quack_attack.lifeIcon`,
`quack_attack.tapEffect`, `quack_attack.perfectEffect`, `quack_attack.missEffect`, `quack_attack.lifeLostEffect`,
`quack_attack.gameOverEffect`, `quack_attack.haptics`, and the same for `purrfect_tap.*` and `boom_mode.*`.

Classic defaults (`default.*`, 9 items) are free and always owned.

## Bundles

| Bundle id | Contents | Legacy price | Authoritative candidate | Discount vs list |
|---|---|---|---|---|
| `bundle.quack_attack` | all 9 Quack Attack items | 1,100 | 3,750 | 32% |
| `bundle.purrfect_tap` | all 9 Purrfect Tap items | 1,100 | 3,750 | 32% |
| `bundle.boom_mode` | all 9 Boom Mode items | 1,100 | 3,750 | 32% |

Players who already own items in a set pay a pro-rated price to complete it
(`OWNERSHIP_AND_ECONOMY.md` §2). For example, owning the Duck Button means the Quack
Attack set costs 896 to complete.

Rationale: a bundle costs a little less than two epic themes. The 32% discount
rewards commitment to a collection without making single items feel like a trap.
Single items stay well priced for mix & match.

## Rules kept from the existing shop

- No loot boxes, random rewards, countdown timers, "limited time" copy or streak-loss offers.
- Prices are shown in full before a confirmation dialog. Owned items are never charged again.
- Cosmetics never change timing, scoring, lives, speed or the hit area.
- Every item can be previewed for free in the Preview Studio before buying.

## Optional future IAP mapping (proposal only)

**Not implemented.** No StoreKit product ids were added to code or to
`StoreKit/PerfectTap.storekit`. The 9 existing products (4 coin packs, Remove Ads,
4 premium skins) are unchanged and covered by a test.

If the owner later wants to sell collections for real money, here are some options. Each one
needs App Store Connect setup, server verification (`verify-purchase`), an
`EntitlementLedger` mapping and a review by the release session:

| Hypothetical product id | Type | Grants | Note |
|---|---|---|---|
| `com.perfecttap.collection.quackattack` | Non-consumable | the 9 `quack_attack.*` ids | Restorable through StoreKit history, like the premium skins |
| `com.perfecttap.collection.purrfecttap` | Non-consumable | the 9 `purrfect_tap.*` ids | |
| `com.perfecttap.collection.boommode` | Non-consumable | the 9 `boom_mode.*` ids | |

Open questions for the owner: whether a coin bundle and an IAP bundle should coexist
(owners of some items would need pro-rating, which StoreKit cannot do), and the price
tier (suggested: the same tier as the premium skins).
