# Cosmetic Art Replacement Spec

This is the spec for swapping the 13 provisional cosmetic graphics (and, optionally, the 6 button backgrounds that were never produced) for production art. **No gameplay code changes are needed**: art is looked up by asset id, and every renderer draws it `resizable().scaledToFit()` (or into a computed rect). That means any square canvas at or above the minimum works.

Related:
- [`ASSET_MANIFEST.md`](ASSET_MANIFEST.md) covers the current provisional files.
- The owner review page is `design/cosmetics/review/index.html`. Generate it with `python3 scripts/cosmetics/build_review_page.py`.
- QA findings: [`QA_REPORT.md`](QA_REPORT.md) QA-09 (emblems cut flat at the bottom) and QA-10 (emblem covers the "T" on small buttons).

## Rules for every asset

| Rule | Requirement |
|---|---|
| Asset id | **Stable. Never rename.** The id is the imageset name and the string in `CosmeticCatalog.swift` (`imageName` / `secondaryImageName` / `emblemImageName`). Renaming one means a code change and breaks `CosmeticEffectsTests` / `CosmeticQATests`. |
| Location | `ios/PerfectTap/Assets.xcassets/Cosmetics/<QuackAttack\|PurrfectTap\|BoomMode>/<id>.imageset/` |
| Files | `<id>@2x.png` and `<id>@3x.png`. Keep the existing `Contents.json`: 1x slot empty, `universal`, `preserves-vector-representation: false`. |
| Format | PNG-24 + alpha (RGBA, 8-bit/channel), sRGB, no colour profile other than sRGB, not interlaced. A PDF vector is also acceptable if `Contents.json` is changed to a single `"filename": "<id>.pdf"` entry with `preserves-vector-representation: true`. |
| Canvas | **Square.** The renderers fit the image into a square frame, so a non-square canvas shrinks the art. |
| Transparency | Fully transparent background. No baked panel, card, vignette or drop shadow; the game adds glow and shadow itself. Clean antialiased edges with no dark or light halo, which you can check on the checkerboard in the review page. |
| Text | No text, numbers or "TAP!" in any asset. The label is native. |
| Masters | Keep a master at ≥ 4× the @3x size (or vector) in `design/cosmetics/source/` for future exports. |
| Readiness | Set `readiness` to `final` in `design/cosmetics/asset_manifest.json` only after the owner approves. |

## Per-asset spec

Point sizes are what the app actually draws on an iPhone (402 pt wide). The effect radius is R = min(0.225 × width, 110 pt), so R ≈ 90 pt on phones and 110 pt on iPad. Minimum pixels are @3x of the largest drawn size. Delivering at the *recommended* canvas is preferred, because it keeps @3x sharp. The current provisional files use the smaller *current* canvas, and that's why they look soft.

### Life icons (6)

| Asset id | Collection | Role | Where it renders | Drawn size |
|---|---|---|---|---|
| `cos_quack_life` | Quack Attack | lifeIcon active (`imageName`) | Lives HUD (top right, lives modes), one per remaining life. Studio cards, Preview Studio. | 22 pt; ≈19 pt with 5 lives (Rush, row capped at 100 pt) |
| `cos_quack_life_lost` | Quack Attack | lifeIcon lost (`secondaryImageName`) | Lives HUD: a lost life slot | same |
| `cos_paw_life` | Purrfect Tap | lifeIcon active | same | same |
| `cos_paw_life_lost` | Purrfect Tap | lifeIcon lost | same | same |
| `cos_boom_life` | Boom Mode | lifeIcon active | same | same |
| `cos_boom_life_lost` | Boom Mode | lifeIcon lost | same | same |

- **Canvas.** Current 24 pt = **48 / 72 px**. Recommended 32 pt = **64 / 96 px**. The minimum @3x is 72 px.
- **Safe area.** Centre the icon with 4–6 % transparent margin on every side. Active and lost must share the same silhouette and position, so the HUD doesn't jump when a life is lost.
- **Lost state.** It must read as "gone" at 19 pt on a dark background: desaturated, dimmed, cracked or outlined. Don't rely on colour alone, so it still works for colour-blind players.
- **Max file size.** ≤ 12 KB per PNG.

### Tap-button emblems (3)

| Asset id | Collection | Where it renders | Drawn size |
|---|---|---|---|
| `cos_quack_emblem` | Quack Attack | Tap button, every round: leading overlay at 1.05 × button height, inset 8 pt from the left, lifted by 0.1 × height. Studio collection card (56 pt button), item cards (40 pt), Preview Studio chips (30 pt). | **84 pt** on the 80 pt gameplay button |
| `cos_paw_emblem` | Purrfect Tap | same | same |
| `cos_boom_emblem` | Boom Mode | same | same |

- **Canvas.** Current 72 pt = **144 / 216 px**. That's below the drawn size, so the art is upscaled. Recommended 96 pt = **192 / 288 px**. The minimum @3x is 252 px.
- **Safe area (QA-09).** Draw the **whole** character, including the bottom. The current bomb and paw are sliced flat because the concept-sheet crop cut them. Leave **≥ 10 % transparent padding at the bottom** and ≥ 6 % on the other sides. The emblem is lifted 8 pt and may poke above the button top. That's intended, so the top can be tight.
- **Label clearance (QA-10).** The TAP! label starts at 0.8 × button height from the left. Keep the visual weight in the left 75 % of the canvas, so the emblem doesn't cover the "T" on small buttons.
- **Readability.** Use a strong silhouette with a 1–2 px darker outline. It sits on a glossy capsule: Quack on yellow `#FFD129`, Purrfect on pink `#FF6BB3`, Boom on steel `#38384D`.
- **Max file size.** ≤ 80 KB per PNG.

### Effect sprites (4)

| Asset id | Collection | Effect | Where it renders | Drawn size |
|---|---|---|---|---|
| `cos_quack_feather` | Quack Attack | Life Lost (`feathers` style) | 4–6 copies burst from the lives HUD on a miss that costs a life, rotating and swaying, fading out within ~1 s. Reduced Motion: one static sprite. | 0.38–0.48 R ≈ **35–43 pt** on phone, ≤ 53 pt on iPad |
| `cos_quack_gameover` | Quack Attack | Game Over (`rainDroop`) | Game Over screen, once per round (not on quit, not with Visual Effects off), centred, droops down | 1.5 R ≈ **135 pt** on phone, ≤ 165 pt on iPad |
| `cos_paw_gameover` | Purrfect Tap | Game Over (`rainDroop`) | same | same |
| `cos_boom_gameover` | Boom Mode | Game Over (`explosion`) | same, pops in with an ease-out-back scale | same |

- **Feather canvas.** Current 36 pt = 72 / 108 px. Recommended 56 pt = **112 / 168 px**. The minimum @3x is 160 px.
- **Game Over canvas.** Current 96 pt = 192 / 288 px, which is well below the drawn size, so it's soft. Recommended 168 pt = **336 / 504 px**. The minimum @3x is 495 px.
- **Safe area.** Feather: centred, with 6 % margin. Rotation is applied around the centre, so keep the shape balanced. Game Over: the element sits on the canvas centre, with ≥ 6 % margin all round. Don't include rain, sparkles, dizzy dashes or smoke: the native effect draws those.
- **Glow.** Optional and subtle. The renderer adds its own additive glow, so baked glow doubles it.
- **Max file size.** Feather ≤ 25 KB per PNG. Game Over ≤ 150 KB per PNG (@3x).

### Optional button backgrounds (6, not produced)

The capsule body is drawn natively from the palette. Background art is optional. If it's commissioned, it's used automatically, and the native gloss, rim and label stay on top.

| Asset id (reserved) | Collection | Field |
|---|---|---|
| `cos_quack_button` / `cos_quack_button_pressed` | Quack Attack | `imageName` / `secondaryImageName` |
| `cos_paw_button` / `cos_paw_button_pressed` | Purrfect Tap | same |
| `cos_boom_button` / `cos_boom_button_pressed` | Boom Mode | same |

- **Where it renders.** The gameplay tap button, full width minus 2 × 24 pt (≈354 pt on iPhone 17 Pro, up to ≈980 pt on iPad landscape) × 80 pt. The art is drawn **aspect-fill and clipped to a capsule**, never stretched. Studio cards use 56 pt / 40 pt heights.
- **Canvas.** Not square. **1080 × 240 px** (@3x, 360 × 80 pt) plus a @2x at 720 × 160 px. If iPad matters, add width (e.g. 1500 × 240 px): aspect-fill crops the sides on narrow phones. Keep the important pattern inside the centre 70 %.
- **Safe area.** The ends are clipped to a semicircle of radius 40 pt (120 px @3x), so keep detail out of the 120 px at each end. Keep the centre band quiet and low-contrast: TAP! is drawn on top in white.
- **Pressed state.** The same art, 10–15 % darker or squashed. It's shown while the finger is down.
- **Transparency.** Opaque is fine, because it's clipped to the capsule.
- **Max file size.** ≤ 120 KB per PNG.
- **Code.** When added, remove the id from `CosmeticEffectsTests.intentionallyNotProduced` and from the "not produced" list that `CosmeticQATests.testAssetCatalogAndCosmeticCatalogAgree` uses. The test then requires the imageset to exist.

## Colour and style per collection

| Collection | Palette (catalog) | Style notes |
|---|---|---|
| Quack Attack | yellow `#FFD129`, orange `#FF8C1A`, water `#33ADFF`, aqua `#8CE6FF` | Rubber-duck toy: glossy, rounded, friendly. Orange bill, water accents. Lost life: a deflated/grey duck, not a dead one. |
| Purrfect Tap | pink `#FF6BB3`, cream `#FFEDE0`, magenta `#EB409E` | Soft and cute: paw pads, plush textures, soft highlights. The cream must stay visible on the pink button (use an outline). |
| Boom Mode | steel `#38384D`, ember `#FF8C14`, gold `#FFCC40` | Cartoon bomb, not realistic weaponry: round black/steel bomb, lit fuse, warm sparks. The Game Over mushroom stays cartoonish and friendly (all-ages rating). |

All three collections use the same light direction (top-left), outline weight and level of detail, so mixing items across collections in the Preview Studio still looks coherent.

## Drop-in procedure

1. Export @2x and @3x PNGs at the canvas sizes above, named exactly `<id>@2x.png` / `<id>@3x.png`.
2. Replace the two files in `ios/PerfectTap/Assets.xcassets/Cosmetics/<Collection>/<id>.imageset/`. Leave `Contents.json` alone unless switching to PDF.
3. **Don't re-run `swift scripts/cosmetics/extract_assets.swift`** afterwards. It regenerates the provisional crops from the concept sheet and would overwrite the new art. Update `design/cosmetics/asset_manifest.json` (bytes, pixels, readiness) by hand or with a follow-up script change.
4. Regenerate the review page with `python3 scripts/cosmetics/build_review_page.py --no-wav`, then check every asset on the dark and checkerboard tiles.
5. Run the asset tests (under the shared heavy-work lock on the shared Mac):
   ```sh
   cd ios/PerfectTap && xcodegen generate
   /tmp/pt-heavy.sh xcodebuild test -project PerfectTap.xcodeproj -scheme PerfectTap \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
     -only-testing:PerfectTapTests/CosmeticEffectsTests -only-testing:PerfectTapTests/CosmeticQATests
   ```
   `testCatalogAssetNamesExistInBundle` checks that the 13 ids load and are ≥ 48 px wide. `testAssetCatalogAndCosmeticCatalogAgree` checks for no orphan or missing imagesets.
6. Look at the art in the app: Shop → Studio → Open Preview Studio → try each collection, then play one lives round per collection to see the HUD, the Life Lost burst and the Game Over screen. Check the QA-09 emblem bottom and the QA-10 "T" clearance.
7. Don't change Swift code. If art only works with a different drawn size or offset, that's a separate gameplay/UI change: `CosmeticGameplayViews.swift` for button and lives, `Effects/` for sprites.
