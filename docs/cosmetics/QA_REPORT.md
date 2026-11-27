# Cosmetic Studio — Independent QA, Security & Performance Report (Agent E)

| | |
|---|---|
| Reviewed | `feature/modular-cosmetic-studio` @ `3137a8c` vs base `f0e2091` (`origin/release/1.2.0`) |
| QA branch | `qa/cosmetic-studio` (this report, QA tests, one DEBUG-only perf hook) |
| Date | 2026-11-27 |
| Environment | 10-core Mac, 16 GB, Xcode 26.2 SDK, **simulators only** (iPhone 17 Pro iOS 26.2, iPhone 16e, iPad Pro 13" M5). No physical device. |
| Backend | Every UI test/launch used `-PTUITestOfflineBackend` (+ `TEST_RUNNER_PT_QA_OFFLINE=1` for the mode matrix). Unit-test hosts use `OfflineBackend` automatically. **No network writes**; SQL only in a throwaway Docker container (removed). |

## Verdict

**Ready for a draft PR with the flag OFF in Release** (verified: built Release `Info.plist` has
`PT_COSMETIC_STUDIO_ENABLED = NO`, Debug `YES`; Studio tab and themed resolve are gated). No
blocker for merging the branch dark.

**Not ready to turn the flag ON** until these are resolved:

1. **QA-01 (High, server, pre-existing):** `private.purchase_economy_item` grants an item for free
   when an old `event_key` is replayed with a different `item_id` — **proven** in a throwaway
   Postgres. Must be fixed (or confirmed fixed by `20261127110000_economy_hardening.sql`)
   before any cosmetic id is enabled in an authoritative config.
2. **QA-02 (High, perf, simulator):** with any themed collection equipped, gameplay hitches rise
   ~5–9× (frames ≥25 ms: 72–132 vs 15; p99 33.3 ms vs 16.7 ms; hitch ratio 1.25–2.37 % vs 0.26 %;
   `perf-gate` limit 0.6 %). Effects-Off isolation brings it back to 0.38 % ⇒ the
   `CosmeticEffectLayer` (TimelineView + Canvas overlays) is the cause. Needs a device
   Instruments capture and a fix before release.
3. QA-03 (Medium) haptic styles are sold but cannot be previewed; QA-04 (Medium) Life Lost burst
   misplaced on iPad/wide screens.

Everything else is Low / informational.

## Findings

| ID | Sev | Area | Evidence | Repro | Expected / Actual | Suggested fix |
|---|---|---|---|---|---|---|
| QA-01 | **High** (pre-existing; blocks enabling cosmetics server-side) | Security / economy (SQL) | `supabase/migrations/20261125130443_authoritative_economy_ledger.sql:302-321` (`purchase_economy_item`) + `apply_economy_delta` `:222-227` | `docs/cosmetics/qa/sql/purchase_item_duplicate_event_key.test.sql`: buy `theme_neon` (250) with key K, then `purchase_economy_item(K, 'theme_matrix')` | Expected: duplicate key grants nothing. Actual: status `duplicate`, balance unchanged (750), **`theme_matrix` (2500) owned** — pgTAP `not ok 6`. Same path will apply to every cosmetic id once enabled. The proposal's bundle RPC is safe (returns before granting) — its pgTAP 26/26. | In `purchase_economy_item`: `if out->>'status' = 'duplicate' then return out; end if;` before `set_profile_item`; better, store `item_id` in the event metadata and reject a duplicate key whose metadata differs. Check against `20261127110000_economy_hardening.sql` (release worktree; not read here). |
| QA-02 | **High** (simulator; confirm on device) | Performance | `Views/Game/Cosmetics/CosmeticEffectLayer.swift:38-58`, `GameView.swift` (two full-screen `cosmeticEffectLayers`) | `TEST_RUNNER_PT_PERF_COSMETIC=quack_attack scripts/perf-run.sh …` (table below) | Expected: themed loadout within perf gate (≤0.6 % hitches, p99 ≤25 ms). Actual: every themed run fails p99 (33.3 ms) and hitch ratio (1.25–2.46 %); default loadout passes. Effects Off with Quack equipped: 0.38 %, p99 16.7 ms. | Profile with Instruments (SwiftUI + Time Profiler) on device. Candidates: the TimelineView(.animation) driving a full-screen Canvas per layer (two layers mounted for the whole round), `onChange(of: queue.isExpired(at:))` evaluated per frame, re-rendering the whole GameView body on each trigger `@State` change. Size the Canvas to the burst rect, use one layer, or draw with `drawingGroup()`/CALayer. |
| QA-03 | Medium | UX / fairness | `Views/Profile/CosmeticStudio/CosmeticPreviewStudioView.swift:77-88` (`case .haptics: break`), `fire(_:)` `:104-111` plays only sound + effect | Preview Studio → Haptics → pick "Punchy Haptics" | Expected (shop copy "try it before you decide"): feel the style. Actual: nothing happens; 3 items × 100 coins are sold unseen/unfelt. | In `fire(_:)` call `HapticsEngine.shared` with `CosmeticHapticPolicy.pulses(for:styleID:)` of the draft haptics item (respecting the haptics setting). |
| QA-04 | Medium | Visual (iPad / wide) | `GameView.swift` `cosmeticEffectLayers`: life-lost origin `UnitPoint(x: 0.82, y: 0.08)` | Boom loadout on iPad Pro 13", lose a life — `screenshots/gameplay-boom_mode-lifelost-ipadpro13.png` | Expected: burst on the lives HUD. Actual: lives sit at the right edge (~0.97 × width), the explosion is ~150 pt to the left of them. On iPhone it roughly lines up. | Anchor the burst to the lives view (anchorPreference / GeometryReader of `livesView`) instead of a fixed unit point. |
| QA-05 | Low (test infra) | Build / tests | `PerfectTap.xcodeproj/xcshareddata/xcschemes/PerfectTapUITests.xcscheme` diff: `StoreKitConfigurationFileReference` removed (commit `0538aad`, regenerated with XcodeGen 2.46.0, which drops `test.storeKitConfiguration` from `project.yml:296`) | Diff the scheme vs `f0e2091` | Expected: regenerating the project keeps the scheme identical. Actual: StoreKit config reference dropped. **Not** the cause of the IAP test failure: `IAPReviewScreenshotTests` fails identically on the baseline `f0e2091` with its committed scheme, and on this branch with the reference restored ("StoreKit prices did not load") — a pre-existing failure. | Restore the reference (or pin the XcodeGen version that emits it); separately, fix/document how the IAP screenshot test is meant to run (probably the `PerfectTap-StoreKit` scheme / Debug-StoreKit config). |
| QA-06 | Low | Audio / UX | `GameViewModel.swift:336-339` (`quit()` → `finish()` → `playGameOverCosmetic()` `:351`), `GameOverView.prepareGameOverEffect` | Themed pack, Endless → QUIT → Quit | Quitting plays the themed "game over" sting and the Game Over effect. Debatable; the default pack is silent so it's new behaviour. | Owner decision; skip both when `endedByQuit`. |
| QA-07 | Low | Audio | `GameViewModel.swift:687-691` + `SoundEngine.playGameOverCosmetic` (fallback `nil`) | Round ends on a tap while the themed pack is still decoding (first ~0.5 s after setup; 560 ms measured off-main on the simulator) | The tap sound is suppressed *and* the sting has no fallback ⇒ silent final tap. Practically unreachable (3 s countdown), but the guard should check that the sting can actually play. | Suppress the tap sound only if the pack is cached, e.g. `activePackHasGameOverSound && packReady`. |
| QA-08 | Low | Audio / UX | `CosmeticAudioRouting.swift:49-55` (gameplay never emits `.tap`); `CosmeticPreviewStudioView.swift:113` `tap()` fires `.tap` | Preview Studio → tap the preview button | The preview plays `<pack>_tap.caf`, which gameplay never plays (a GOOD tap plays `good_v*`). Preview does not represent gameplay; 3 files (~35 KB) are preview-only. | Preview "tap" as `.good`, or route `.tap` in gameplay deliberately. |
| QA-09 | Low | Visual | Emblem art: `cos_boom_emblem`, `cos_paw_emblem` — bottom of the art is cut flat at the button's bottom edge (`screenshots/gameplay-boom_mode-*`, `preview-studio-boom-loadout-*`) | Equip Boom / Purrfect button | Emblem looks truncated (bomb body sliced horizontally). Provisional art. | Re-export emblems with transparent padding, or lower the `offset(y:)` / size in `ThemedTapButton`. |
| QA-10 | Low | Visual | `ThemedTapButton` at small heights: Preview Studio chips (`screenshots/preview-studio-boom-loadout-iphone17pro.png`, "Duck Button"/"Paw Button") | Open Preview Studio | Emblem covers the "T" of "TAP". | Scale the label padding with the emblem, or hide the emblem below ~50 pt height. |
| QA-11 | Low | Visual / readability | Tap/miss bursts originate at (0.5, 0.86) = centre of the TAP label (`screenshots/gameplay-quack_attack-lifelost-*`, `effect-tap-good-splash-*`) | Quack loadout, any tap | Ripple rings sit on top of "TAP!" for ~0.7 s; the timing zones stay clear (good). | Origin slightly above the button (y ≈ 0.80) or draw behind the label. |
| QA-12 | Low | Accessibility parity | `CosmeticGameplayViews.swift:188-193` | Flag OFF, VoiceOver on the lives dots | The **default** lives view now exposes "Lives, N of M lives" (pre-Studio: no element). An improvement, but the flag-OFF build is not byte-for-byte identical in the accessibility tree. | Accept (recommended) and note it in release notes, or gate on the flag. |
| QA-13 | Low | Security hygiene | `EconomyManager.isCosmeticOwned` (`EconomyManager.swift` ~`:209`) trusts `item.isDefault` from the caller's value | `CosmeticQATests.testForgedCosmeticItemCannotChangePriceOrBeEquippedUnowned` | A forged `CosmeticItem` with `collectionID: "default"` is reported "owned" (UI only). Equip, purchase and resolve still refuse — verified by test. | Look up `CosmeticCatalog.item(id:)` first (as the store does). |
| QA-14 | Low | Bundle size | `Resources/Sounds/audio_manifest.json` copied into the app (33.5 KB) | Inspect built `.app` | Dev metadata shipped to users. | Exclude from the target's resources (the QA test can read it from the repo path instead). |
| QA-15 | Low (pre-existing) | Test infra | `PerfectTapUITests/ModeRuntimeQATests.swift:47-52` | `xcodebuild test -only-testing:…ModeRuntimeQATests` | Defaults to the **cloud** backend (creates an anonymous user) unless `TEST_RUNNER_PT_QA_OFFLINE=1`. | Default to offline; opt in to cloud. |
| QA-16 | Low | Perf (not gameplay) | `GameView` bootstrap: `game.viewBootstrap` max 8–14 ms vs 3.5–4.6 ms base | perf table | `store.refresh()` + image/sprite preload on the first round. Under the 50 ms gate. | Optional: preload at app launch / Home appear. |
| QA-17 | Low | Perf (shop only) | `CosmeticStudioShopSection.isEquipped` → `EconomyManager.isCosmeticEquipped` → full 9-slot resolve, each `isOwned` → `ShopItem.item(id:)` linear scan over a freshly concatenated `allItems` (now +36 items) | Scroll the Studio grid | O(cards × 9 × items) per render. Not on the gameplay path. | Resolve once per render (use `loadoutStore.resolved`) and index `allItems` by id. |
| QA-18 | Info | Code | `EconomyManager.purchaseCosmetics` `cosmeticPurchaseInFlight` | — | The guard is a no-op (synchronous, main-actor); safety actually comes from synchronous execution + `expectedPrice` + ownership re-check. Single-item path is protected by `CosmeticPurchaseFlow.isPurchasing` and `legacyBuy`'s ownership check (double-confirm test: charged once). | None required; comment it. |
| QA-19 | Info | Visual consistency | Shop header uses a gold "$" coin; Studio prices use the 🪙 emoji (renders grey/silver) and mixed "1,100"/"1100" formatting (`screenshots/shop-studio-collections-iphone17pro.png`) | Open Studio | Cosmetic inconsistency. | Reuse the shop coin glyph and one number formatter. |
| QA-20 | Info | Dynamic Type | `screenshots/shop-studio-a11y-xxxl-*.png` | Accessibility XXXL | Studio text scales (good) and scrolls; the DEBUG price note and "Open Preview Studio" card take a full screen, the wand icon overlaps the card text, the legacy shop tabs above do not scale. Usable, not polished. | Cap the DEBUG note, use `ViewThatFits`/stacked layout for the preview card at accessibility sizes. |

### Verified OK (claims I tried to break and could not)

- **Scoring/timing isolation.** `TimingEngine.swift`, `TapBarView.swift`, `GameConfig.swift` untouched
  (`git diff --stat` empty). `GameViewModel` changes are limited to `setup` (pack/haptic selection),
  the post-scoring dispatch (`tapOutcome`), and the sting in `finish()`. The pure `tapOutcome`
  mapping reproduces the old if/else (`CosmeticAudioTests.testDefaultPackPolicyIsIdenticalToLegacyDispatch`,
  haptics equivalent).
- **Default parity.** Default skin = same RoundedRectangle r=20, mode gradient, 80 pt, "TAP!" 24 black tracking 4,
  same 0.94/0.85 press feedback, shadow radius 20; default lives = same 10 pt dots; `ParticleEffectView`
  unchanged while the Perfect Effect is the default; `CosmeticEffectLayer` not mounted; default pack plays the
  exact pre-Studio tones (`play(type)` path), no game-over sound; default haptics = `impactOccurred()` with
  the old styles. Only parity delta found: QA-12 (a11y element).
- **Hit area.** UI test asserts the `TAP!` button is 80.0 pt high and full width minus 2×24 pt for all
  three themed skins; accessibility label stays "TAP!"; skins only draw (emblem is a non-hit-testing overlay).
- **HUD.** Rush (5 themed lives + timer + score) on iPhone 16e (390 pt) and 17 Pro (402 pt): lives inside the
  window, no overlap with SCORE/TIME (UI test). Themed row is capped at 100 pt; arithmetic for 320–375 pt
  widths leaves ≥30 pt spare (score ≤5 digits).
- **SwiftUI invalidation.** `CosmeticLoadoutStore` publishes only on refresh/equip (bootstrap, shop), never per
  tap; GameView keeps `cosmetics` in `@State` resolved once per round; the 60 fps indicator still goes through
  `indicatorRelay`. Effect `TimelineView` exists only while a burst is alive; queue ≤2 bursts. (But see QA-02.)
- **Audio.** One engine, 8-node pool + 1 preview node; themed voices round-robin with priority protection,
  bounded. Pack decoding off-main (`audio.packPreload.offMain` 560 ms, simulator); `audio.tapOutcome.main`
  avg 0.02 ms / max 0.18 ms. `setActiveSoundPack` (round setup) calls `stopPreview()` and bumps the preview
  generation, so a preview cannot leak into a round; `perfecttap_sound` off ⇒ `playTapOutcome`,
  `playGameOverCosmetic`, `previewSound` all return early. Final-tap double sound: verified — themed pack plays
  only the sting when `phase == .finished` after scoring (QA test asserts which packs have a sting). Interruption /
  configuration-change restart unchanged and keeps buffers.
- **Flag OFF.** Release build: `PT_COSMETIC_STUDIO_ENABLED = NO` (PlistBuddy on the built app), Debug `YES`;
  `assert-built-flags.sh` PASS. Flag off ⇒ `resolved == .defaults` (unit test), Studio tab absent
  (`ShopTab.visible(premium:studio:)` test).
- **Ownership / tamper.** Editing `pt_cosmetic_loadout.<uid>` JSON grants nothing (unowned ⇒ default); forged
  `CosmeticItem` values cannot change price or equip unowned items; preview never writes loadout / profile /
  coins / analytics; per-account loadouts isolated; refund ⇒ default next round (existing tests + QA tests).
- **Purchases.** Bundle: one deduction, all missing items granted once, already-owned never charged,
  insufficient coins changes nothing, `expectedPrice` mismatch charges nothing, idempotent on repeat. Exhaustive
  property test over all 3×512 owned subsets: completion ∈ [1, missing value], owned value + completion ≥ bundle
  price (splitting never beats the bundle). Double-confirm of a single item: charged once. Authoritative mode:
  `buyItemForCurrentRollout` refuses cosmetics before calling the server (existing test).
- **StoreKit.** No new product ids in code or `.storekit`; the 9 ids unchanged
  (`com.perfecttap.coins.{500,1200,3000,8000}`, `removeads`, `skin.{neonpulse,liquidchrome,glitchmode,cosmicgold}`).
  `com.perfecttap.collection.*` appears only in `SHOP_CATALOG_PROPOSAL.md`.
- **Secrets.** `gitleaks git --log-opts=f0e2091..3137a8c --config .gitleaks.toml`: 13 commits, **no leaks**;
  manual grep of the diff for key/token patterns: none.

## Tests (exact counts, iPhone 17 Pro simulator unless noted)

| Suite | Result | Notes |
|---|---|---|
| `PerfectTapTests` (branch as delivered) | **215 run: 214 passed, 1 skipped, 0 failed** | skip = `CosmeticEffectsTests.testRenderEffectFilmstrips` (opt-in env) |
| `PerfectTapTests` + QA tests | **223 run: 222 passed, 1 skipped, 0 failed** | +8 `CosmeticQATests` (all pass) |
| `PerfectTapStoreKitTests` | **26 run, 26 passed** | local `.storekit`, offline backend |
| `CosmeticStudioQAUITests` (new, offline) | **9 runs, 9 passed** (8 tests on 17 Pro; PERFECT-frame test re-run after fixing its detector: pass) | 17 Pro; HUD test also on iPhone 16e (pass); Boom gameplay also on iPad Pro 13" (pass) |
| `ModeRuntimeQATests` (15-mode matrix, `TEST_RUNNER_PT_QA_OFFLINE=1`) | **1 test passed; 15/15 modes PASS (QA_RESULT lines, offline backend)** | |
| `TrackingConsentUITests` (offline) | **3/3 passed** | |
| `IAPReviewScreenshotTests` (offline) | **1 run, 1 failed** — "StoreKit prices did not load" | **Pre-existing:** fails identically on base `f0e2091` (committed scheme with StoreKit ref) and on this branch with the ref restored. Not a regression (QA-05). |
| `GameplayPerformanceTests` (offline) | **13 / 13 runs completed** | 3 base + 3 integrated + 2 × 3 themed + 1 Effects-Off isolation (gate results below) |
| Proposal pgTAP (`supabase/proposals/*.test.sql`) | **26/26** | throwaway `supabase/postgres:17.11.0.018`; all 11 migrations + proposal applied |
| Existing DB suites with proposal applied | economy_ledger 20/20, economy_sources 122/122, perfecttap 70/70, purchase_ledger 42/42, sales_gate 30/30, season_calendar 35/35 | no conflict with existing migrations |
| QA pgTAP `docs/cosmetics/qa/sql/purchase_item_duplicate_event_key.test.sql` | **6/7 — test 6 fails by design (proves QA-01)** | |

Not run / caveats: the proposal was not tested against `20261127110000_economy_hardening.sql` (release worktree,
not touched). Tests that set `role postgres` were run with `set_config('role', session_user, …)` because the
container applies migrations as `supabase_admin` (no SQL semantics changed).

### QA tests added (this branch)

- `ios/PerfectTap/PerfectTapTests/CosmeticQATests.swift` (8): DEBUG force-collection resolve; override only
  inside `#if DEBUG` (source check — plus `strings` on the Release binary: 0 hits, Debug: 1); audio manifest ⇔
  `SoundPackCatalog` ⇔ bundled CAF (ids, byte sizes, **SHA-256**, no orphans); asset catalog ⇔ cosmetic catalog
  (no orphan imagesets; the only missing names are the 6 intentionally-not-produced button backgrounds);
  double-confirm charges once; forged items; exhaustive bundle fairness; which packs have a game-over sting.
- `ios/PerfectTap/PerfectTapUITests/CosmeticStudioQAUITests.swift` (8): screenshots, hit-area and lives a11y
  assertions, Rush HUD layout, Dynamic Type XXXL, cold-launch metric.
- `GameplayPerformanceTests`: optional `TEST_RUNNER_PT_PERF_COSMETIC=<collection>` and
  `TEST_RUNNER_PT_PERF_EFFECTS=off|reduced|full` (launch arguments only; nothing persisted).
- `scripts/qa/perf-summary.py`: mean (min–max) table over several probe JSONs.
- Product code (the one allowed change): `CosmeticLoadoutStore` DEBUG-only `-PTForceCosmeticCollection <id>`
  (mirrors `-PTForceTheme`; ownership bypass and parsing exist only under `#if DEBUG`; not persisted).

## Performance (simulator, iPhone 17 Pro, same Mac, sequential, offline, `GameplayPerformanceTests` workload)

Raw probe JSONs: `docs/cosmetics/qa/perf/*.json` (summarise with `scripts/qa/perf-summary.py`).

**Simulator numbers only** — relative main-thread cost on this Mac, not a device result. Baseline runs were the
noisiest (two of three failed the absolute gate themselves: stalls in countdown / timed play); compare
within-column ranges, not single values.

| metric | base (n=3) | integrated (n=3) | quack (n=2) | purrfect (n=2) | boom (n=2) |
|---|---|---|---|---|---|
| frames (gameplay) | 5668.00 (5527.00–5928.00) | 5669.00 (5607.00–5790.00) | 5558.00 (5508.00–5608.00) | 5502.50 (5482.00–5523.00) | 5719.00 (5580.00–5858.00) |
| p99 frame ms | 22.22 (16.67–33.33) | 16.67 (16.67–16.67) | 33.33 (33.33–33.33) | 33.33 (33.33–33.33) | 33.33 (33.33–33.33) |
| worst frame ms | 258.13 (194.06–338.31) | 182.19 (130.73–261.21) | 179.19 (176.83–181.54) | 271.22 (160.26–382.17) | 182.58 (182.11–183.05) |
| frames >=25 ms | 45.33 (24.00–65.00) | 15.00 (10.00–22.00) | 132.00 (126.00–138.00) | 101.00 (100.00–102.00) | 72.00 (59.00–85.00) |
| frames >=100 ms | 3.00 (2.00–4.00) | 1.33 (1.00–2.00) | 2.50 (2.00–3.00) | 2.50 (2.00–3.00) | 2.50 (2.00–3.00) |
| hitch ratio % | 0.81 (0.40–1.17) | 0.26 (0.18–0.38) | 2.37 (2.29–2.46) | 1.84 (1.82–1.85) | 1.25 (1.06–1.45) |
| tap handler avg ms | 0.11 (0.09–0.13) | 0.11 (0.10–0.12) | 0.11 (0.11–0.12) | 0.11 (0.11–0.11) | 0.11 (0.11–0.11) |
| tap handler max ms | 1.50 (0.66–2.11) | 0.44 (0.38–0.49) | 0.54 (0.38–0.69) | 0.76 (0.39–1.14) | 0.64 (0.50–0.79) |
| audio.tapOutcome.main avg ms | n/a | 0.02 (0.01–0.02) | 0.02 (0.02–0.02) | 0.02 (0.02–0.02) | 0.02 (0.02–0.02) |
| audio.tapOutcome.main max ms | n/a | 0.08 (0.03–0.18) | 0.03 (0.03–0.04) | 0.04 (0.03–0.05) | 0.07 (0.04–0.09) |
| view bootstrap max ms | 4.19 (3.53–4.55) | 10.27 (8.16–11.33) | 12.05 (11.87–12.23) | 11.29 (11.22–11.36) | 13.10 (12.56–13.64) |
| round end -> Game Over avg ms | 108.74 (73.38–127.06) | 61.16 (54.43–71.45) | 52.19 (45.90–58.48) | 49.19 (41.73–56.65) | 47.50 (41.74–53.27) |
| round end -> Game Over max ms | 177.07 (112.00–222.10) | 147.18 (110.77–200.90) | 119.83 (110.42–129.25) | 110.54 (104.76–116.32) | 111.91 (108.81–115.01) |
| taps measured | 176.67 (167.00–186.00) | 181.67 (180.00–183.00) | 176.50 (175.00–178.00) | 177.00 (177.00–177.00) | 180.00 (177.00–183.00) |
| resident memory MB | 97.84 (97.48–98.49) | 99.46 (99.29–99.68) | 102.82 (102.35–103.29) | 102.87 (102.40–103.34) | 101.63 (101.15–102.12) |
| gameplay stalls >=250 ms | 0.33 (0.00–1.00) | 0.33 (0.00–1.00) | 0.00 (0.00–0.00) | 0.50 (0.00–1.00) | 0.00 (0.00–0.00) |

Effects-Off isolation (Quack equipped, `pt_effects_level=off`, 1 run): p99 16.67 ms, frames ≥25 ms 22,
hitch ratio 0.38 %, worst 144.6 ms, memory 100.8 MB ⇒ the themed hitches (QA-02) come from the effect layer,
not the button skin, lives art or sound pack.

`perf-gate.py` (absolute limits): integrated default 2/3 PASS (run 3: one 261 ms stall in Classic — baseline
run 1 had a 338 ms countdown stall too, i.e. simulator noise); **all 6 themed runs FAIL** p99 (33.3 > 25) and
hitch ratio (1.06–2.46 % > 0.6 %); baseline 0/3 PASS (noise).

- Main-thread per tap: `game.tap` avg 0.11 ms in every configuration (base 0.11); `audio.tapOutcome.main`
  avg 0.02 ms, max ≤0.18 ms.
- Round end → Game Over: integrated 61 ms avg (themed 47–52) vs base 109 ms — no regression (base noisier).
- Memory (resident at end of workload): base 97.8 MB, integrated 99.5 MB (+1.6), themed 101.6–102.9 MB (+4–5 MB:
  one decoded pack ≈ PCM float + art).
- Effect cleanup: no growth — memory flat across the 5 sessions; queue capped at 2 bursts (unit test);
  TimelineView removed when idle.
- Cold launch (`XCTApplicationLaunchMetric`, 5 iterations, fresh install, offline): base avg 1.805 s (values 2.84, 1.44, 1.59, 1.54, 1.62 — first iteration outlier, RSD 29 %), integrated avg 1.528 s (1.58, 1.41, 1.61, 1.52, 1.52; RSD 4.7 %); a second integrated run gave 1.463 s. Excluding the base outlier both are ≈1.5 s ⇒ no measurable cold-launch regression (simulator).

### App size (Release, generic iOS Simulator, universal arm64+x86_64, unsigned)

| | base `f0e2091` | integrated `3137a8c` | delta |
|---|---|---|---|
| `.app` on disk (`du -sk`) | 80 968 KB | 85 556 KB | **+4 588 KB** |
| `Assets.car` | 2 139 688 B | 2 681 752 B | **+542 064 B** (cosmetic art) |
| `Sounds` (33 CAF, bundle root) | 0 | 876 048 B | **+876 048 B** |
| `audio_manifest.json` | — | 33 553 B | +33 553 B (QA-14) |
| executable | 80 008 024 B | 83 187 048 B | +3 179 024 B (simulator, unstripped, two slices; `__TEXT` +0.52–0.57 MB per slice) |

Device App Store size will differ (thinning, one slice, stripped); expect roughly +1.5 MB of resources and
~+0.5 MB of code.

## Screenshots (`docs/cosmetics/qa/screenshots/`, offline backend, Debug)

| File | What | Notes |
|---|---|---|
| `shop-studio-collections-iphone17pro.png` | Shop → Studio → Collections | Readable; QA-19 coin glyph/format |
| `shop-studio-item-actionbar-iphone17pro.png` | Tap Buttons grid with Duck Button selected (action bar) | |
| `preview-studio-boom-loadout-iphone17pro.png` | Preview Studio, whole Boom collection tried, tap fired | QA-09, QA-10 |
| `gameplay-quack_attack-{start,lifelost,depleted}-iphone17pro.png` | Quack button + duck lives, one depleted; Life Lost (feathers) + Miss (panic splash) frame | QA-11 (rings over TAP!) |
| `gameplay-purrfect_tap-{start,lifelost,depleted}-iphone17pro.png` | Paw button + paw lives, one depleted | Good contrast; TAP readable |
| `gameplay-boom_mode-{start,lifelost,depleted}-iphone17pro.png` | Bomb button + bomb lives, one depleted | QA-09 (emblem cut) |
| `gameplay-boom_mode-{start,lifelost,depleted}-ipadpro13.png` | iPad Pro 13" Boom gameplay | QA-04 (life-lost burst misplaced) |
| `hud-rush-boom-5-lives-402pt-iphone17pro.png`, `hud-rush-boom-5-lives-390pt-iphone16e.png` | Rush: 5 themed lives + timer | No overlap (asserted) |
| `effect-tap-good-splash-quack_attack-iphone17pro.png` | Tap Effect (Water Splash) on a GOOD tap | First attempt's "Perfect" detection matched the static zone label; renamed honestly |
| `effect-perfect-quack_attack-iphone17pro.png` | Perfect Effect (Golden Stars) on a real PERFECT in Zen | QA-11 (ring over TAP!) |
| `shop-studio-a11y-xxxl-iphone17pro.png`, `…-scrolled-…` | Studio at Accessibility XXXL | QA-20 |

Visual check summary: no stretched art; TAP label readable on yellow, pink and steel bodies; timing zones stay
clear of every effect (bursts are low, at the button); lives icons crisp at 22 pt with a clear depleted state.
Defects: QA-04, QA-09, QA-10, QA-11, QA-19, QA-20.

## Accessibility

- Tap button: label "TAP!" (asserted by UI tests for all three skins); skin is `accessibilityHidden`.
- Lives: "Lives", value "N of M lives" — asserted ("3 of 3 lives", "5 of 5 lives"); drops on a lost life.
- Studio cards: collection card label "<name> collection", value "N of 9 owned" / "Free" (asserted
  `of 9 owned`); item cards "<name>, <collection>, <slot>" + value Equipped/Owned/Free/"<price> coins";
  buy buttons "Buy <item> for <price> coins"; Preview Studio chips locked/owned values; effect layers hidden.
- Reduce Motion: `CosmeticEffectLayer` uses `effects.effective(reduceMotion:)` ⇒ `.reduced` = one static fading
  primitive, no movement (unit test `testReducedModeHasNoMovement`). Themed button press scale (0.96, 80 ms) is
  not reduced — minor.
- Effects Off: no bursts (`testOffProducesNoBursts`), no Game Over overlay (`GameOverView` guard), themed glow
  radius × 0; perf isolation run confirms the layer is idle.
- Dynamic Type: see QA-20.

## Security review summary

- Client: ownership only from `PlayerProfile.ownedItems`; selection JSON is untrusted and validated against the
  catalog (slot + ownership) on every resolve; equip re-reads the profile and uses the catalog's copy of an item;
  previews resolve with `isOwned: true` but are never persisted; bundle ids never stored. Authoritative economy ON ⇒
  cosmetics are preview-only and never reach `purchase_economy_item`.
- Proposal SQL (`supabase/proposals/2026112800_cosmetic_studio_catalog.sql`): RLS on, no policies, no table
  grants; core function revoked from clients, only the invoker wrapper is callable by `authenticated`, not
  `anon`; `price > 0` checks; bundle requires every component enabled in the active config; profile row lock;
  one ledger delta; **duplicate key grants nothing** (verified). Applies cleanly on top of all 11 migrations
  and leaves every existing suite green. Concerns for the economy session: (a) the PK change to
  `(config_version, item_id)` makes `item_id` non-unique — every existing lookup filters by `config_version`
  (checked), but future code must too; (b) QA-01 still applies to single cosmetic items through
  `purchase_economy_item`; (c) the 23 copied rows are all `enabled = false`, so activating
  `cosmetic-studio-rc1` needs an explicit enable step for the existing catalog too.
- Secrets: none (gitleaks + grep). StoreKit: unchanged.

## Lead follow-up (after Agent E's review)

Fixed on `feature/modular-cosmetic-studio` after this report (commits after `b7e0be9`):

| ID | Status | Change |
|---|---|---|
| QA-02 | **Mitigated, still open** | Effect canvas cropped to the burst square and redrawn at 30 Hz (`CosmeticEffectLayer.swift`). Needs a physical-device check before the flag goes on. |
| QA-03 | Fixed | Preview Studio plays the previewed haptic style (`HapticsEngine.previewTapOutcome`); the gameplay style is untouched. |
| QA-04 | Fixed | Life-lost burst anchored to the real lives HUD (anchor preference) — correct on iPad. |
| QA-05 | Fixed | `xcschemes/` restored from release/1.2.0 (StoreKit config reference back in the UI-test scheme). |
| QA-06 | Fixed | QUIT no longer plays the themed game-over sting or effect (`GameResult.endedByQuit`). |
| QA-07 | Fixed | Themed game-over sting falls back to the classic miss tone while the pack is still decoding. |
| QA-11 | Fixed | Tap bursts start above the TAP label (origin y 0.79). |
| QA-14 | Fixed | `audio_manifest.json` excluded from the app target; the QA test reads it from the source tree and asserts it is not bundled. |
| QA-01 | Open — release session | Pre-existing server bug; see `RELEASE_INTEGRATION_NOTES.md` §2. |
| QA-08, 09, 10, 12, 13, 15–20 | Open (Low/Info) | Documented; QA-09 needs production art, QA-12 is an owner decision. |

### QA-02 measurements (simulator, iPhone 17 Pro, `scripts/perf-run.sh`, `-PTForceCosmeticCollection`)

| configuration | runs | hitch ratio % mean (range) | p99 ms mean | frames ≥25 ms |
|---|---|---|---|---|
| base `f0e2091` (default look) | 3 | 0.81 (0.40–1.17) | 22.2 | 45 |
| themed, before fix | 7 | 1.62 (0.38–2.46) | 31.0 | 90 |
| cropped canvas + `drawingGroup()` | 3 | 2.92 (2.17–3.32) | 33.4 | 162 — **rejected** |
| cropped canvas only (Quack) | 1 | 1.17 | 33.3 | 67 |
| cropped, normal blend instead of plusLighter (Quack) | 1 | 1.31 | 33.3 | 70 — rejected |
| cropped, no button outer shadow (Quack) | 1 | 1.42 | 33.3 | 76 — rejected (shadow is not the cause) |
| **cropped + 30 Hz bursts (shipped)** — Quack ×2, Boom, Purrfect | 4 | **0.89 (0.57–1.10)** | 20.8 | 48 |
| default loadout after fixes | 1 | 0.29 | 16.7 | 16 |

Reading: themed hitches roughly halved and now sit inside the base build's own run-to-run range
on this Mac, but the mean is still above the 0.6 % gate. Simulator Canvas rasterisation is CPU-bound
and not representative of a device GPU — a device Instruments capture decides whether this is closed.
Raw JSON: `docs/cosmetics/qa/perf/{fix,crop,noblend,noshadow,fps30}-*.json`.

Unit tests after the fixes: **223 executed, 222 passed, 1 skipped, 0 failures** (iPhone 17 Pro simulator).
UI suites were not re-run after these fixes.

## Items needing owner decisions

1. Fix QA-01 in the economy/hardening migration (economy session) before enabling any cosmetic server-side.
2. QA-02: accept a device Instruments pass as the gate for turning the flag on; until then keep Release `NO`.
3. Quit behaviour (QA-06): should quitting play the themed game-over sting/effect?
4. Default lives accessibility element with the flag off (QA-12): accept as an improvement?
5. Prices (proposed, unapproved) and the bundle pro-rating rule (fair, tested) — unchanged from the
   implementers' proposal.
6. Ship `audio_manifest.json` in the app or not (QA-14).
