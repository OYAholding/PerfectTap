# Cosmetic Studio — Architecture

Companion to `INTEGRATION_CONTRACT.md` (interfaces and ownership between
agents). This document explains how the cosmetic layer works at runtime and the
rules that keep it from touching gameplay.

## 1. Model

```
CosmeticSlot (9)          tapButton · tapSound · lifeIcon · tapEffect · perfectEffect
                          missEffect · lifeLostEffect · gameOverEffect · haptics
CosmeticItem              one item for one slot; id "<collection>.<slot rawValue>"
                          e.g. "quack_attack.tapButton"
CosmeticCollection        the 9 items of one theme ("default", "quack_attack", …)
CosmeticBundle            "bundle.<collection>" purchase convenience; never owned itself
CosmeticLoadout           player's selection: slot → item id (missing = default)
ResolvedCosmetics         loadout after ownership validation — the only input renderers read
CosmeticCatalog           data-only specs (Models/Cosmetics/CosmeticCatalog.swift)
```

Every slot has a free item in the `default` collection that reproduces the
pre-Studio game exactly (`Classic Button`, `Classic Dots`, `Classic Particles`,
default sound pack, default haptics, `.none` for the other effects).

Item ids use the slot's Swift raw value (`tapButton`, `lifeIcon`, …) because
they are built by `CosmeticItem.makeID(collection:slot:)`. Ids are stored in
`PlayerProfile.ownedItems`, so once shipped they can never change.

## 2. Data flow

```
PlayerProfile.ownedItems ──┐
                           ├─► CosmeticLoadoutStore.resolve ─► ResolvedCosmetics
UserDefaults loadout ──────┘          (O(9), pure)                    │
 pt_cosmetic_loadout.<uid|anon>                                      │
                                                                     ▼
GameView bootstrap (once per round) ── @State cosmetics ──┬─► CosmeticTapButtonSkin
                                                          ├─► CosmeticLivesView
                                                          ├─► CosmeticEffectLayer (overlay)
                                                          └─► GameViewModel.setup(cosmetics:)
                                                                ├─ SoundEngine.setActiveSoundPack
                                                                └─ HapticsEngine.setActiveHapticStyle
GameViewModel.handleTap ─ scoring (unchanged) ─► TapSoundOutcome ─► playTapOutcome (sound + haptics)
GameViewModel.finish ─► SoundEngine.playGameOverCosmetic()
GameOverView.onAppear ─► one-shot CosmeticEffectLayer(.gameOver) overlay
```

- `CosmeticLoadoutStore.shared.refresh()` runs at round bootstrap, so a
  purchase, refund or account switch made since the last round is picked up
  without observers on the tap path. Shop / Studio call `refresh()` after
  purchases and on appear.
- The tap path never reads the store. The effect trigger is set from
  `GameView.onChange(of: vm.tapSequence)`, i.e. after the tap was scored and
  published.

## 3. Ownership vs selection

| Concern | Source of truth | Can a player edit it? |
|---|---|---|
| Ownership | `PlayerProfile.ownedItems` (server-validated in authoritative mode) | No |
| Selection | local UserDefaults, per account | Yes — and it grants nothing |

- `equip(_:)` re-reads the profile and refuses an item that isn't owned (or
  isn't the catalog's item for that slot). Equipping a default item clears the
  slot's selection.
- `equip(collection:)` equips only the owned items of the collection and
  leaves the other slots as they were.
- A selection is never deleted when ownership disappears: a refunded item
  resolves to the default, and buying it again restores the selection.

## 4. Fallback rules

| Situation | Result |
|---|---|
| Slot not selected | slot default |
| Selected id unknown / wrong slot / bundle id | slot default |
| Selected item not owned (never bought, refunded, other account) | slot default |
| Stored JSON corrupt | whole loadout = defaults |
| Stored JSON has an unknown slot (newer build) | that entry dropped, rest kept |
| Flag off | `resolved == .defaults` regardless of selection |
| Tap button art (`imageName`) missing | native glossy capsule from the palette |
| Emblem missing | no emblem, label centred |
| Life icon art missing | default red dots |
| Depleted life art missing | active icon, grayscale, 45 % opacity |
| Effect style `.none` | nothing mounted |

## 5. Rendering rules

- **Default = unchanged.** The default skin draws the exact pre-Studio button
  (RoundedRectangle r=20, mode gradient, 80 pt, "TAP!" 24 black tracking 4) and
  keeps `TouchDownTapArea`'s original press feedback. Default lives are the
  10-pt dots. With no themed effect equipped, `CosmeticEffectLayer` is not
  mounted and `ParticleEffectView` runs exactly as before.
- **Hit area.** Always the 80-pt full-width `TouchDownTapArea`. Skins only
  draw; emblems are overlays and may poke above the edge without changing
  layout. Accessibility label stays "TAP!".
- **Press state.** Comes from the real touch-down (`TouchDownTapArea`
  `pressedContent` init). Themed skins scale to 0.96 and darken; Boom
  (`pressStyle: .fuseGlow`) adds a warm glow while pressed when glow is allowed.
- **Art** is aspect-fit (emblem, life icons) or aspect-fill clipped to the
  capsule (button background) — never stretched.
- **EffectsLevel.** `.off`: no glow (themed button shadow radius × 0), no
  effects, no game-over overlay. `.reduced` (and Reduce Motion): a single short
  static fade per burst, no movement. Legacy particles keep their existing
  `showsParticles` gate.
- **Emblem layout (QA-09/QA-10).** `ThemedTapButtonLayout` (pure, tested) puts the
  emblem inside the capsule with the art's flat-cut bottom on the capsule's bottom
  edge (clipped, under the rim), centres the label in the remaining space, and
  never lets art and label intersect: emblem shrinks first, then the font, and
  only then is the emblem dropped (small Studio chips).
- **Effect placement.** Accuracy events originate just above the TAP label
  (unit point 0.5, 0.79) so neither the label nor the timing zones are covered;
  life lost originates at the lives HUD, located with an anchor preference
  (correct on iPad). Two layers, so a miss that costs a life shows both.
- **Legacy particles.** Shown only while the Perfect Effect is
  `.legacyParticles` (default). If a themed Tap Effect is equipped too, legacy
  particles keep PERFECT only, so GREAT never shows two bursts.
- **Effect renderer (QA-02).** Bursts are rendered with **Core Animation**, not a
  SwiftUI Canvas. When a burst fires, `CosmeticEffectTimeline` samples the pure
  frame model (`CosmeticEffectFrames`) once at 30 keyframes/s; `CosmeticEffectCARenderer`
  turns each primitive track into one keyframed `CALayer` (shape layers for rings and
  slashes, pre-rasterised sprites from `CosmeticShapeSpriteAtlas` for glows, stars,
  puffs; additive blending kept). The animation then runs in the render server:
  **zero main-thread work per frame**. `CosmeticEffectHostView` keeps ≤ 2 bursts and
  removes each when it ends. The Canvas painter remains only as the reference
  renderer for filmstrip tests.

## 6. Performance rules

1. No disk I/O, JSON decoding, catalog scans or `UIImage(named:)` on the tap
   path. The loadout is resolved once per round.
2. Images and effect sprites are warmed **off the main thread** before play:
   `CosmeticImageCache.warm` (decodes with `preparingForDisplay`) from Home appear
   and GameView bootstrap; `CosmeticEffectAssets.warm` rasterises every sprite a
   burst can use. Tests assert zero sprites are drawn at tap time.
3. Resolve is O(slots) over in-memory data (`PlayerProfile.load()` is cached).
4. Sound packs are selected/preloaded in `GameViewModel.setup` (before the
   countdown) on a dedicated user-initiated decode queue; `playTapOutcome` only
   enqueues playback. Until a pack is ready, taps fall back to the classic tones.
5. Effects are bounded (≤ 24 primitives, ≤ 1.2 s, game over ≤ 1.8 s, ≤ 2 concurrent
   bursts) and leave no layers behind.
6. Measurements and rejected experiments: `docs/cosmetics/PERF_QA02.md`.
   Simulator numbers only — a physical-device Instruments pass is required before
   the flag is enabled in Release.

## 7. Gameplay isolation

`TimingEngine`, scoring, speed, lives and revive logic do not read anything
cosmetic. The only GameViewModel changes are: the post-scoring sound/haptic
dispatch (`TapSoundOutcome`, same priority: combo break > miss > milestone >
accuracy), sound pack / haptic style selection in `setup`, and the game-over
sting in `finish`. `CosmeticGameplayIntegrationTests` plays identical
synthetic rounds with the default and themed loadouts and asserts identical
score, lives, combo, speed level, accuracy sequence and phase.

## 8. Feature flag

`PT_COSMETIC_STUDIO_ENABLED` (Info.plist; YES/TRUE/1). Off ⇒ `resolved` is
always `.defaults`, so gameplay is byte-for-byte the pre-Studio game even if a
loadout was saved earlier. Until Agent D's `FeatureFlags.cosmeticStudioEnabled`
lands, the store reads `CosmeticStudioFlag.isEnabled`
(`Views/Game/Cosmetics/CosmeticStudioFlag.swift`), which tests override with
`CosmeticStudioFlag.overrideForTesting`.

## 9. Known limitations / follow-ups

- Loadouts are per device (contract §6: `equipped_cosmetics` profile sync).
- An account switch is picked up at the next `refresh()` (round start, Shop,
  Studio), not instantly.
- The game-over sting is requested inside `finish()`; when a round ends on a
  miss, it is requested *before* that tap's miss sound. The sound router
  (Agent C) decides voice priority.
