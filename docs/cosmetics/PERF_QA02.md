# QA-02 — Themed-loadout frame pacing (Agent C, `fix/cosmetic-c-render`)

> **All numbers here are iOS Simulator numbers** (iPhone 17 Pro, iOS 26.2,
> `818F031C-EFBC-41D4-BBA9-3360311CD950`, 10-core Mac shared with other agents;
> every build/benchmark ran under `/tmp/pt-heavy.sh` so none overlapped). They show
> relative main-thread cost on this Mac. **They do not replace the physical-device
> Instruments pass** (`docs/perf/DEVICE_PROFILING_PROTOCOL.he.md`), which remains
> mandatory before `PT_COSMETIC_STUDIO_ENABLED` is turned on in Release.

Gate (`scripts/qa/perf-gate.py`, gameplay window): hitch ratio (frames ≥ 25 ms) ≤ 0.6 %,
p99 ≤ 25 ms. Workload: `GameplayPerformanceTests/test_gameplay_workload` (Classic ×3,
Timed 60 s, Endless with background/foreground), `-PTForceCosmeticCollection <id>`.
Raw JSON: `docs/cosmetics/qa/perf/c2-*.json`.

## Cause

Before this branch every live burst was a `TimelineView(.animation)` + `Canvas`:

* each display frame (30 Hz after the lead's mitigation) re-evaluated the SwiftUI
  subtree, rebuilt `Path`s and gradient shadings for ≤ 24 primitives, and the
  Canvas display list (radial gradients, gradient strokes, plus-lighter blending)
  was rasterised synchronously on the **main thread** during the CA commit;
* `onChange(of: queue.isExpired(at: now))` ran every frame; the `GeometryReader`
  around the canvas re-evaluated on every timeline tick.

During a tap-heavy round a burst is alive most of the time, so that per-frame main
thread cost overlapped with the timing indicator and input handling.

## Fix (kept)

**Core Animation renderer** (`Effects/CosmeticEffectPainter.swift`,
`CosmeticEffectCARenderer`, `CosmeticEffectHostView`):

1. `CosmeticEffectFrames` primitives now carry a stable `track` id (particle index, or
   100+ for fixed rings/glows/sprites). `CosmeticEffectTimeline.tracks(for:)` samples
   a burst **once, when it fires** (30 keyframes/s over its lifetime, ≤ 55 samples ×
   ≤ 24 tracks of pure math) — the same frame function the painter draws.
2. Each track becomes one `CALayer` with keyframed `position` / `transform` /
   `opacity` (rings and claw slashes: `CAShapeLayer` with keyframed `path` and
   `lineWidth`). The render server interpolates and composites them; **the app's main
   thread does no per-frame work while a burst plays** (no TimelineView, no SwiftUI
   update, no rasterisation). Motion is interpolated at the display rate (capped at
   60 Hz via `preferredFrameRateRange`), smoother than the old 30 Hz canvas steps.
3. Gradient/shape primitives (glow, droplet, streak, star, twinkle, puff, burst, dot,
   feather fallback) are **pre-rasterised once per colour** with Core Graphics
   (`CosmeticShapeRasterizer`, same geometry as the painter) into a thread-safe
   `CosmeticShapeSpriteAtlas`, warmed off the main thread at Home appear / round
   bootstrap (`CosmeticEffectAssets.warm`). A unit test proves warming covers every
   sprite any burst of each collection can draw (`syncMisses == 0`).
4. Additive (`plusLighter`) primitives use CA's `plusL` compositing filter, so the look
   is unchanged; bounds (≤ 24 primitives, ≤ 1.2/1.8 s, ≤ 2 bursts, ≤ 3 flashes/s,
   ≤ 45 % width), Reduced (one static fading primitive) and Off (nothing) rules are
   untouched because they live in the pure model.
5. The host view removes each burst tree when it ends, never re-adds a finished burst,
   is non-interactive and hidden from accessibility.

`CosmeticEffectPainter` (Canvas) is kept as the reference renderer for the opt-in
filmstrip test.

## Experiments (Quack Attack unless noted; one variable at a time)

| # | configuration | commit | runs | hitch % | p99 ms | frames ≥ 25 ms | verdict |
|---|---|---|---|---|---|---|---|
| — | lead's earlier table: before any fix | — | 7 | 1.62 (0.38–2.46) | 31.0 | 90 | — |
| — | lead's earlier table: `drawingGroup()` / normal blend / no button shadow | — | 3 / 1 / 1 | 2.92 / 1.31 / 1.42 | 33.4 / 33.3 / 33.3 | 162 / 70 / 76 | rejected by the lead |
| B | **baseline today**: cropped canvas + 30 Hz (`81f7ce3`) | `81f7ce3` | 2 | **1.12** (1.00, 1.23) | 24.3, 33.3 | 59, 68 | gate FAIL |
| E1 | B + `Canvas(rendersAsynchronously: true)` | `0ff2e83` (branch `c2-exp-async`, not merged) | 1 | 0.89 | 18.2 | 51 | **rejected** — within B's noise, still above the gate; Canvas still re-evaluated per frame |
| E2 | Core Animation renderer + pre-rasterised sprites (first cut) | `2daf24b` (WIP, squashed into `68718ea`) | 1 (+1 aborted: workload flake "TAP! not found") | **0.22** | 16.7 | 13 | kept → final |
| F | **final** = E2 + fuse-glow position tweak + layout/QA-16 (no renderer change) | `68718ea` | see below | | | | |

Not run separately: sprites drawn *inside* the existing Canvas (would still re-evaluate SwiftUI and rasterise
on the main thread every frame — E2 removes the per-frame work altogether, which is the stronger version of the
same idea); "single shared layer instead of two" (with CA an idle host view costs nothing per frame, so two
hosts stay — the life-lost burst keeps its HUD anchor); removing `GeometryReader` / the per-frame
`onChange(of: isExpired)` (both are gone with the TimelineView).

## Final numbers (`68718ea`, simulator)

`perf-gate.py`: **all 9 valid final runs PASS** (Quack ×3, Boom ×2, Purrfect ×2, Default ×2). Both
baseline (`81f7ce3`) Quack runs FAIL (hitch ratio; run 2 also p99 33.3 ms and 5 frames ≥ 100 ms).

| metric | before-81f7ce3-quack (n=2) | CA-quack-runs2-4 (n=3) | CA-boom (n=2) | CA-purrfect (n=2) | CA-default (n=2) |
|---|---|---|---|---|---|
| frames (gameplay) | 5710.50 (5536.00–5885.00) | 5664.00 (5430.00–5947.00) | 5605.50 (5588.00–5623.00) | 5673.00 (5595.00–5751.00) | 5683.50 (5559.00–5808.00) |
| p99 frame ms | 28.80 (24.28–33.33) | 16.67 (16.67–16.67) | 16.67 (16.67–16.67) | 16.67 (16.67–16.67) | 16.67 (16.67–16.67) |
| worst frame ms | 186.56 (185.65–187.47) | 198.53 (175.48–216.23) | 208.16 (169.79–246.53) | 200.56 (192.23–208.90) | 149.83 (138.66–161.00) |
| frames >=25 ms | 63.50 (59.00–68.00) | 20.00 (16.00–27.00) | 22.50 (18.00–27.00) | 16.50 (12.00–21.00) | 19.00 (11.00–27.00) |
| frames >=100 ms | 4.00 (3.00–5.00) | 1.00 (1.00–1.00) | 1.00 (1.00–1.00) | 1.00 (1.00–1.00) | 1.00 (1.00–1.00) |
| hitch ratio % | 1.12 (1.00–1.23) | 0.35 (0.29–0.45) | 0.40 (0.32–0.48) | 0.29 (0.21–0.37) | 0.34 (0.19–0.49) |
| tap handler avg ms | 0.13 (0.12–0.14) | 0.12 (0.11–0.14) | 0.14 (0.12–0.15) | 0.13 (0.11–0.15) | 0.12 (0.11–0.13) |
| tap handler max ms | 0.89 (0.49–1.29) | 0.46 (0.24–0.64) | 0.88 (0.79–0.98) | 0.43 (0.23–0.64) | 0.59 (0.41–0.77) |
| audio.tapOutcome.main avg ms | 0.02 (0.02–0.02) | 0.02 (0.02–0.02) | 0.02 (0.02–0.02) | 0.02 (0.02–0.02) | 0.02 (0.02–0.02) |
| audio.tapOutcome.main max ms | 0.08 (0.08–0.08) | 0.07 (0.03–0.12) | 0.11 (0.05–0.17) | 0.20 (0.04–0.35) | 0.08 (0.07–0.08) |
| view bootstrap max ms | 12.10 (11.34–12.87) | 6.62 (5.47–8.53) | 8.77 (6.37–11.17) | 6.10 (5.53–6.67) | 9.65 (7.18–12.12) |
| round end -> Game Over avg ms | 80.29 (64.17–96.40) | 78.41 (60.38–97.73) | 88.94 (64.72–113.17) | 73.76 (63.00–84.52) | 71.66 (60.75–82.57) |
| round end -> Game Over max ms | 155.88 (119.07–192.68) | 157.11 (144.64–172.11) | 163.58 (136.98–190.19) | 134.82 (127.69–141.95) | 131.58 (127.12–136.04) |
| taps measured | 176.00 (170.00–182.00) | 176.67 (172.00–181.00) | 176.50 (171.00–182.00) | 178.00 (173.00–183.00) | 182.00 (175.00–189.00) |
| resident memory MB | 102.31 (102.20–102.43) | 102.56 (101.99–103.07) | 101.63 (101.62–101.65) | 101.48 (101.31–101.65) | 99.44 (98.80–100.07) |
| gameplay stalls >=250 ms | 0.00 (0.00–0.00) | 0.00 (0.00–0.00) | 0.00 (0.00–0.00) | 0.00 (0.00–0.00) | 0.00 (0.00–0.00) |

Excluded from the table, reported honestly: `c2-final-quack-run1` — hitch 5.36 %, p99 63.5 ms, 11 stalls
≥ 250 ms **including two in the countdown (no effects alive)**, tap handler avg 0.40 ms (normally 0.12) —
taken while a Virtualization/Docker VM outside the lock was using ~260 % CPU (load average ≈ 30, 15-min
average 30 at 19:42). Every metric, effect-free ones included, was degraded, so it measures the host, not the
build. Two other runs aborted on workload flakes (onboarding "LET'S GO!" not taking / "TAP! not found";
no app crash) and were re-run. Load averages during the valid runs were still 5–15 (other agents' builds),
so absolute numbers carry noise; the before/after comparison was run in the same session.

Per-run hitch % (valid final runs): Quack 0.29 / 0.30 / 0.45, Boom 0.48 / 0.32, Purrfect 0.37 / 0.21,
Default 0.49 / 0.19. The themed loadouts are now indistinguishable from the default loadout (and from
Effects-Off, 0.38 % in the QA report) on this Mac.

**Gate verdict (simulator): met** — every valid themed run ≤ 0.6 % hitches and p99 16.7 ms. **Physical-device
validation is still mandatory** before the flag goes on: CA rendering moves the cost to the render server /
GPU, which the simulator models poorly; run the Instruments protocol (Core Animation + Time Profiler,
hitches) on the oldest supported iPhone with each collection.

## QA-16 — `game.viewBootstrap`

| | max ms per run | mean of maxima |
|---|---|---|
| base 1.2.0 (QA report) | 3.53 / 4.51 / 4.55 | 4.2 |
| `81f7ce3` themed (today) | 12.87 / 11.34 (Quack) | 12.1 |
| lead's fps30 runs (themed) | 10.8 / 10.3 (Quack), 16.5 (Boom), 10.5 (Purrfect) | 12.0 |
| **`68718ea` themed** | 5.47 / 8.53 / 5.86 (Quack), 11.17 / 6.37 (Boom), 6.67 / 5.53 (Purrfect) | **7.1** |
| `68718ea` default loadout | 12.12 / 7.18 | 9.7 |

Images, emblem/lives art, effect sprites and shape sprites are now decoded off the main thread
(`preparingForDisplay`, iOS 15+; deployment target is 16.0, so no fallback path is needed) when Home appears;
the bootstrap's synchronous `preload` calls are memory hits. Themed bootstrap max dropped ≈ 12 → ≈ 7 ms.
The remainder above base is **not** cosmetic image work: the *default* loadout (no images at all) shows the
same 7–12 ms. It sits in the first bootstrap of the run (`vm.setup` → haptics setup ≈ 3–4 ms, sound/haptic
selection, `store.refresh()`), outside the files this agent owns; worth a look by the SoundEngine/Haptics
owner. Nothing is decoded on the tap path: effect bursts only look up warmed sprites (unit test
`testWarmCoversEverySpriteAFiringBurstUses` asserts zero fire-time rasterisations).


## QA-09 / QA-10 — emblem (same branch, for reference)

`ThemedTapButtonLayout` (`CosmeticGameplayViews.swift`, pure): the emblem is drawn *inside* the capsule at
1.15 × height, positioned so the art's flat-cut bottom (≈ 84 % of the 216-px canvas for Boom/Paw) lies exactly
on the capsule's bottom edge, clipped to the capsule and covered by the rim strokes — no cut edge is visible,
art is aspect-fit (never stretched), the PNGs are untouched. The label is centred in the space right of the
emblem art; when both cannot fit (Studio chips, 30–40 pt) the emblem shrinks (1.0 / 0.85 / 0.75 ×), then the
font (26 → 12 pt), and only then is the emblem dropped. Unit tests check, for heights 28–96 pt × widths
60–1000 pt and both labels, that emblem art and label box never intersect and that the cut line sits on the
bottom edge. Screenshots: `qa/screenshots/c2-tap-button-sheet-80-56-40-30pt.png` (rendered sheet, normal and
pressed; rendered before the Boom fuse-glow position tweak), `c2-gameplay-*-iphone17pro.png`,
`c2-preview-studio-boom-loadout-iphone17pro.png` (chips), `c2-effect-perfect-quack_attack-iphone17pro.png`
and `c2-gameplay-boom_mode-lifelost-iphone17pro.png` (CA effects mid-burst).

Art note for Agent D (optional): re-exporting `cos_boom_emblem` / `cos_paw_emblem` with the whole object
inside the canvas (≥ 8 % transparent margin at the bottom) would let the emblem pop above the capsule again
instead of sitting inside it; the layout reads `artCutFraction`, so only that constant would change.
