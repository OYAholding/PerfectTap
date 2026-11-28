# Cosmetic Studio — Collection Guide

How to add cosmetics without touching gameplay code. Read `ARCHITECTURE.md`
first for the rules (default = unchanged, missing assets fall back, nothing on
the tap path).

All paths are relative to `ios/PerfectTap/` unless they start with `docs/` or
`supabase/`.

## Naming

| Thing | Pattern | Example |
|---|---|---|
| Collection id | `snake_case`, stable forever | `quack_attack` |
| Item id | `<collection>.<slot rawValue>` (built by `CosmeticItem.makeID`) | `quack_attack.lifeIcon` |
| Bundle id | `bundle.<collection>` (never stored as owned) | `bundle.quack_attack` |
| Image assets | `cos_<short>_<part>` in `Assets.xcassets/Cosmetics/<collection>/` | `cos_quack_life_lost` |
| Sound pack id | equals the collection id | `quack_attack` |
| Haptic style id | short adjective | `bouncy` |

Item ids end up in `PlayerProfile.ownedItems` and on the server. **Never
rename an id after it has shipped**; add a new item instead.

## Add a whole collection (bundle)

1. **Catalog** — `Models/Cosmetics/CosmeticCatalog.swift`: add a
   `static let myTheme: CollectionSpec` with exactly one `SlotSpec` per
   `CosmeticSlot` (9), a 2–3 colour `palette`, a `bundlePrice`, and append it to
   `specs`. Prices are proposals; live prices come from `EconomyConfig` / the
   server.
2. **Assets** — add the images/sounds referenced by the specs (steps below).
3. **Shop bridge / server** — Agent D's `ShopItem.cosmetics` bridge picks the
   items up from the catalog. In authoritative-economy mode, the ids must also
   be added to `private.economy_shop_items` via a reviewed migration (see
   contract §5); until then they show as *Preview only*.
4. **Tests** — run `CosmeticLoadoutTests`; the catalog-integrity tests fail if
   a slot is missing, an id is duplicated or malformed, or a themed item lacks
   the assets its slot needs.

## Add a tap button

1. Catalog: `SlotSpec(slot: .tapButton, …, assets: CosmeticAssetRefs(…))`
   - `palette: [body, bodyShade, rimAccent]` — **required**; the button is drawn
     natively from it whenever art is missing.
   - `emblemImageName` — character/emblem drawn at the leading edge (~84 pt
     square, aspect-fit, may poke above the top edge).
   - `imageName` / `secondaryImageName` — *optional* text-free background art
     (normal / pressed). Aspect-filled and clipped to the capsule; never
     stretched. Do **not** bake "TAP!" into art — the label is native text.
   - `pressStyle` — `.squish` (default) or `.fuseGlow`.
2. Assets: emblem PNG/PDF with transparent background, ~3× of 84 pt
   (252 px). Background art at 3× of ~345×80 pt with the subject centred.
3. Check: label readable in both states, no layout change, hit area unchanged
   (`CosmeticGameplayIntegrationTests.testThemedViewsRenderWithMissingAssets`
   asserts the 80 pt height).

## Add a sound pack

1. Catalog: `SlotSpec(slot: .tapSound, …, assets: CosmeticAssetRefs(soundPackID: "<collection>"))`.
2. Audio: files under `Resources/Sounds/<collection>/` and the pack definition
   in `Services/CosmeticAudio/` (Agent C — see `docs/cosmetics/AUDIO_POLICY.md`):
   tap/good/great/perfect/miss/combo-break/milestone/life-lost/game-over.
   One primary voice per tap outcome; short, normalised, no long tails.
3. Gameplay needs no change: `GameViewModel.setup` selects the pack and every
   tap calls `playTapOutcome(TapSoundOutcome)`.

## Add life icons

1. Catalog: `SlotSpec(slot: .lifeIcon, …, assets: CosmeticAssetRefs(imageName: "cos_<x>_life", secondaryImageName: "cos_<x>_life_lost"))`.
2. Assets: square, transparent, readable at 18–22 pt (export 66 px @3×).
   The depleted icon is optional — without it the active icon is shown
   grayscale at 45 % opacity.
3. The row is capped at 100 pt wide (5 lives shrink to ~18 pt), so the HUD
   score is never pushed.

## Add an effect (tap / perfect / miss / life lost / game over)

1. Pick an existing `CosmeticEffectStyle` and give it a palette (and a sprite
   `imageName` for sprite styles such as `.feathers` / `.rainDroop`):
   `SlotSpec(slot: .missEffect, …, assets: CosmeticAssetRefs(effectStyle: .splash, palette: [...]))`.
2. A genuinely new style needs a case in `CosmeticEffectStyle`
   (`Models/Cosmetics/CosmeticModels.swift`) and a renderer in
   `Views/Game/Cosmetics/Effects/` (Agent B). Rules: ≤ 24 particles, ≤ 1.2 s,
   nothing at `EffectsLevel.off`, static/short fades at `.reduced`, no strobing,
   must not cover the timing bar for long.
3. Where it plays: accuracy effects originate at the TAP button, life lost at
   the lives HUD, game over at the top of the Game Over screen (one shot).

## Add a haptic style

1. Catalog: `SlotSpec(slot: .haptics, …, assets: CosmeticAssetRefs(hapticStyleID: "<id>"))`.
2. Implement the style in `Services/HapticsEngine.swift` (Agent C) for every
   `TapSoundOutcome` case. Keep intensities ≤ today's combo-break `.heavy`.

## Checklist before merging a collection

- [ ] 9 slots, ids `<collection>.<slot>`, unique; bundle prices set
- [ ] Every referenced asset name exists in `Assets.xcassets/Cosmetics/<collection>/`
      (a typo silently falls back to the default look — check in the Studio)
- [ ] Button: label readable pressed and unpressed, emblem not clipped,
      art not stretched; checked on iPhone SE and Pro Max widths
- [ ] Lives: readable at 18 pt (Rush, 5 lives); depleted state distinguishable
- [ ] Effects: Full / Reduced / Off all checked; nothing hides the timing bar
- [ ] Sounds: one voice per tap; game-over sting doesn't overlap the music badly
- [ ] `PerfectTapTests` green (catalog integrity, ownership, scoring identity)
- [ ] Server rows / prices reviewed by the economy owner before authoritative sale
