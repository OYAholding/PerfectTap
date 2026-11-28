# PerfectTap mode × evidence matrix

**Prepared:** 2026-11-21 · **Status:** research document; no code was changed.
**Code basis:** `main` @ `8defb4f`:
- `ios/PerfectTap/ViewModels/GameViewModel.swift`
- `ios/PerfectTap/Utils/TimingEngine.swift`
- `ios/PerfectTap/Utils/GameConfig.swift`
- `ios/PerfectTap/Models/GameMode.swift`
- `ios/PerfectTap/Views/Game/TapBarView.swift`

**Evidence references** point to [ADHD_ATTENTION_EVIDENCE.md](ADHD_ATTENTION_EVIDENCE.md), where every source is linked. The section numbers below (§) refer to that document.

---

## 1. Shared mechanics (true of every mode)

| Aspect | What the code does | Why it matters |
|---|---|---|
| **Movement** | An indicator moves across a bar and reflects off both edges (`TimingEngine.advance`). `speed` = **seconds per full edge-to-edge sweep**, so the centre is crossed once per `speed` seconds. | The path is predictable, so taps are **anticipatory / coincidence timing**, not reaction. |
| **Self-paced** | There is **no auto-miss** when the indicator passes centre. Only a tap is scored. The player may wait any number of sweeps. | **No omission errors.** The game does not require vigilance (CPT-style sustained attention), and the player sets their own event rate (§2.1, §2.7). |
| **Scoring windows** | Distance from centre as a fraction of bar width: PERFECT ≤ 0.04 × `perfectScale`, GREAT ≤ 0.10, GOOD ≤ 0.20, otherwise MISS. A MISS costs a life in lives modes. | Temporal half-window = zone × `speed`. Example: PERFECT at speed 1.2 s = **±48 ms**, at 0.3 s = **±12 ms**. |
| **Tap timing** | The touch timestamp is projected to what the player saw (1 display frame of latency compensation, ≤ 50 ms extrapolation). Minimum interval between taps is 40 ms. The display link is locked to 60 fps. | Good basis for measurement. The signed error (early/late, in ms) is computable per tap. |
| **Feedback** | Accuracy popup. Particles on PERFECT/GREAT. Sound and haptic per tap. Heavy haptic plus a "combo break" sound on misses after a combo ≥ 3. EARLY/LATE hint on non-PERFECT taps. | Immediate, rich feedback fits reward-sensitivity findings (§7). EARLY/LATE is useful knowledge-of-results. No reduce-motion handling was found in the codebase. Settings offer only sound, music and haptics toggles. |
| **Data kept** | Aggregates only: taps, perfects, misses, max combo, perfects in the first 20 taps, speed level, elapsed time. **No per-tap signed error or inter-tap interval is stored.** | Consistency metrics (SD of error, lapse rate) are **not possible today** without new per-session telemetry. |

### Approximate PERFECT half-windows (ms) = 0.04 × perfectScale × speed × 1000

| | Start | Floor / extreme |
|---|---|---|
| Zen | ±64 (fixed) | — |
| Classic / Duel | ±48 | ±12 (speed 0.30) |
| Sudden Death | ±36 | **±6** (speed 0.15, reached after ~12 taps) |
| Rush | ±22 | ±12 |
| Precision | ±40 | **±10** (scale 0.5 × speed 0.5) |
| Tiny Window | ±22 | **±5** (scale 0.25 × speed 0.5) |

**What the numbers mean:**
- Windows below roughly ±10–15 ms are near or under one 60 Hz frame (16.7 ms). Typical human sensorimotor timing variability is tens of ms (general timing literature; not quantified in this review).
- At the extremes, PERFECT outcomes are therefore **largely noise**. This matters for both frustration and measurement.

---

## 2. Matrix

**Column definitions:**
- **Process:** the cognitive process the mode *may* engage. This is not established.
- **Evidence:** what the literature says about that process (§ = evidence doc).
- **Measurable:** what could be computed with per-tap logging.
- **Risk:** overstimulation / frustration risk (L/M/H).

| Mode | Actual mechanic (from code) | Process it may engage | Supporting evidence | Limitations | What can be measured | Proposed modifications | Risk |
|---|---|---|---|---|---|---|---|
| **Classic** | 3 lives, start 1.2 s/sweep. Speed −0.10 every 4 taps, floor 0.30. Combo ×1.5/×2. Earns coins. Revive via ad. | Anticipatory timing; speed-accuracy adjustment under ramping difficulty | Timing variability is elevated in ADHD (§2.5, §2.8). Practice → (a) only (§3, §4). | Self-paced, so no vigilance demand. A fixed ramp in taps means run length mixes skill with luck. A revive breaks comparability. | Signed error (ms), SD of error, % PERFECT by speed level, taps-to-failure | Use as the "fun" baseline. Do **not** use for measurement. Show per-run EARLY/LATE bias summary. | M |
| **Duel** | Classic rules, one run each, no revive, server-timed session. | Same as Classic, plus social evaluation and competition | No ADHD-specific evidence. Reward and competition raise engagement (§7). | Opponent pressure confounds performance. Asynchronous play. | As Classic | Keep as a social feature. Offer a "friendly" variant with no rank loss. | M–H |
| **Endless** | 3 lives. Speed = 1.2 − 0.005 × elapsed s, floor 0.2 (reached at ~200 s), then holds. | Timing at a high fixed pace; persistence over longer play | Longer sessions are needed to observe lapses (§2.7). | Floor 0.2 s/sweep gives ±8 ms PERFECT, so mostly noise at the floor. Ends on misses, so duration varies. | Error SD in the plateau phase; lapse rate (taps with abnormally large error) over time | Lower the plateau speed. Optional fixed-length "endurance" variant (see §4, R2/R7). | M–H |
| **Timed** | 60 s. **No lives.** Speed 1.0 → 0.45 over the run. Revive adds 15 s. | Timing under time pressure | None specific. Time pressure may raise arousal (state regulation, §2.7, mixed evidence). | The ramp confounds time-on-task with difficulty. Self-paced, so the player can slow-play. | Taps/min, accuracy vs elapsed time | **Closest existing basis for a fixed protocol**: fixed duration, no lives. Remove the ramp and revive in a "protocol" variant (R2). | M |
| **Sudden Death** | 1 life, no revive. Start 0.9, −0.12 every 2 taps, floor 0.15. | Precision under maximal stakes | None. Loss framing plus high stakes may raise frustration. Frustration was the most common AKL-T01 adverse event, ~3% (§5). | Runs are very short. The floor (±6 ms PERFECT, ±30 ms GOOD) is near the limits of human timing. | Taps survived, first-error latency | Raise the speed floor. Label as a "challenge" mode. Exclude from any calm/focus bundle. | **H** |
| **Combo Frenzy** | 3 lives. Combo counts any non-miss. Multiplier up to ×6 at 20. Speed = 1.2 − 0.03 × combo, floor 0.4. | Sustained consistency (streak maintenance) | Immediate, escalating reward fits ADHD reward sensitivity (§7, Luman 2005). This is engagement, not benefit. | Success makes it harder, and a break resets speed. Mixes reinforcement with difficulty. | Streak length distribution; error SD within streaks | Keep for fun. Consider a soft combo decay instead of hard reset to reduce loss aversion. | M–H |
| **Zen** | **No lives, no score, no combo.** Fixed 1.6 s/sweep. Shows PERFECT/GREAT/TOTAL counts. Exit any time. | Relaxed timing practice | Practice → (a) (§3). Low-pressure presentation is a comfort choice. There is no evidence for or against calm presentation in ADHD (§7, gap). | Fixed slow speed is not challenging for skilled players. Unlimited duration, so no structure. | Signed error, error SD, drift in accuracy over minutes | **Best base for a "Calm" option**: optional session length, an optional end-of-session consistency summary, and reduced effects (R4, R5). | **L** |
| **Precision** | 2 lives. **Only PERFECT counts; anything else is a miss.** PERFECT scale shrinks 0.05 every 5 taps (floor 0.5). Speed −0.06 every 8 taps (floor 0.5). | Fine timing precision; error monitoring | Timing precision is a relevant construct (§2.5). Training evidence is weak (§6). | Floor ±10 ms PERFECT is near frame and timing noise, so misses become partly random. Very punishing. | % PERFECT vs window size, which gives a psychometric curve | Replace the fixed shrink with an **adaptive staircase** on window size (R3). Report the threshold, not the score. | **H** |
| **Chaos** | 3 lives. Speed randomized to 0.35–1.4 every 3–6 taps. | Re-calibrating timing to changing tempo; flexibility | Phase correction to tempo shifts was intact in adult ADHD, but variability was higher (Hove 2017, §2.5). | Random parameters make runs non-comparable. Abrupt changes may feel unfair. | Error on the first taps after a change vs later (adaptation cost) | Announce tempo changes (visual cue) for fairness. Log the change events for adaptation analysis. | M–H |
| **Mirror** | 3 lives. Per-frame random direction flip: chance 0.008 + 0.001/s, capped at 0.04 per 60 Hz frame (≈0.5 → 2.4 flips/s). Speed ramps to a 0.5 floor. | Reactive correction to unpredictable events; some inhibition of the prepared tap | The closest existing mechanic to "withholding a prepared response" (§2.3), but not a validated inhibition task. | The flip rate becomes very high, so the game approaches randomness. A per-frame probability ties the flip rate to frame timing. | Error on taps shortly after a flip vs control taps; premature taps | Cap flips at a lower rate. Base the flip on time, not frames. A **go/no-go variant** would be a cleaner inhibition probe (R8). | H |
| **Invisible Zone** | 3 lives. Zone bands hidden; faint centre line and marker remain. Speed −0.08 every 4 taps, floor 0.4. | Internal reference / spatial estimation of centre; reliance on internal timing | No direct evidence. Reduced external cues may increase reliance on internal timing (§2.5, speculative). | Adds difficulty without adding information. Faint visuals hurt low-vision players. | Error bias (systematic early/late), error SD vs Classic | Offer a contrast setting. Useful as a comparison condition in a study (zones visible vs hidden). | M |
| **Rush** | 30 s, 5 lives, start 0.55 s/sweep. The last 10 s accelerate to a 0.3 floor. Revive restores lives only. | Fast timing under time pressure | None specific. High pace and intensity. | ±22 ms PERFECT from the start. Short and intense. A high-arousal design. | Taps, accuracy | Keep as an "intense" mode. Exclude from calm bundles. Flash/shake budget review. | **H** |
| **Hardcore Combo** | 3 lives. Speed from combo (−0.025 each) + base drift (−0.05 every 6 taps) + break shock (+0.15, cap 0.45, decaying). After a break, PERFECT scale 0.7 for 4 taps. Floor 0.45. | Performance under escalating punishment | Punishment after errors may raise frustration. No evidence of benefit. | Punishment compounds after errors, which can spiral. | Post-error slowing / accuracy (error monitoring); recovery taps | Keep as an opt-in challenge. Never default. Show a "recover" cue rather than a shock. | **H** |
| **Tiny Window** | 2 lives. PERFECT scale starts at 0.5 and shrinks 0.03 every 6 taps (floor 0.25). Speed −0.06 every 5 taps (floor 0.5). GREAT/GOOD unchanged. | Fine timing precision | As Precision (§2.5, §6) | PERFECT reaches **±5 ms**, below a frame, so PERFECTs become mostly chance. Misses are rare (GOOD unchanged), so failure is slow. | % PERFECT vs window size | Raise the floor to a perceptible window (e.g. ≥ ±15 ms). Or merge into an adaptive Precision mode (R3). | M–H |
| **Focus** | No HUD (no score or combo shown), no score tracking, quit button. Speed oscillates sinusoidally (±0.3 around a base decaying from 1.1 to a 0.5 floor; period ≈ 7.9 s). **3 lives still apply, but are hidden by the HUD.** | Minimal-distraction timing; adapting to a smoothly varying tempo | No evidence that a "focus" mode improves attention (§1, §3). The name could be read as a claim (see [COMPLIANCE.md](COMPLIANCE.md) §5). | Hidden lives mean the run can end without warning. The varying tempo makes trials non-comparable. The name "Focus" implies a benefit. | Error vs tempo phase; lapse rate | Consider renaming to **"Minimal"**/**"Clean"**. Show lives subtly or remove them. If a practice protocol is added, build it as a separate, clearly described mode (R2/R7), not under the "Focus" name. | M |

---

## 3. What PerfectTap does and does not exercise today

| Construct (§ in evidence doc) | Engaged today? | Where |
|---|---|---|
| Timing precision / anticipatory timing (§2.5) | **Yes, primarily** | All modes |
| Performance consistency (§2.8) | Yes, implicitly; **not measured** | All modes, especially Zen and Timed |
| Reactive correction (§2.4) | Partly | Mirror, Chaos, Hardcore (shocks) |
| Response inhibition (§2.3) | Weakly; restraint before the window, no stop/no-go signal | Mirror (flips) at best |
| Sustained attention / vigilance (§2.1) | **No**: self-paced, no omission cost | — |
| Selective attention (§2.2) | Minimal | Invisible Zone (reduced cues) |
| Working memory (§2.6) | No | — |

---

## 4. Ranked, evidence-informed changes

**Labels:**
- **evidence-supported:** the change itself rests on established findings, *as a measurement or design practice*. This is not a promise of cognitive benefit.
- **hypothesis:** plausible but untested. Should only be evaluated through the study plan.

**No item below justifies a benefit claim.**

| Rank | Change | Label | Rationale | Notes |
|---|---|---|---|---|
| **R1** | **Per-session timing telemetry (local first):** signed error (ms) per tap, inter-tap interval, speed, window size. Derived metrics: mean bias, SD, a lapse rate (e.g. taps beyond 2.5 SD or > X ms late). | evidence-supported (measurement) | RT/timing variability is a replicated ADHD-associated feature (§2.8, Kofler 2013). Also a prerequisite for every other item. | Store on-device. Upload only aggregates, with consent. Label metrics as game statistics ("timing consistency"). Never call them an attention score. |
| **R2** | **Fixed, repeatable protocol mode ("Practice Session"):** fixed speed, fixed duration (e.g. 3 min), fixed window, no lives, no revive, no ramp, identical visuals every time. | evidence-supported (measurement) | Comparable sessions are necessary to see practice curves (a). Simons 2016 best practices (§4). Today every mode changes difficulty mid-run. | Built on Zen/Timed mechanics. Show a practice curve over days. State plainly that this shows improvement at the game. |
| **R3** | **Adaptive staircase on window size or speed** (e.g. 2-down/1-up on PERFECT-or-GREAT), replacing the fixed shrink in Precision/Tiny Window. | evidence-supported (design and measurement); **hypothesis** for any transfer | Keeps difficulty near threshold and limits frustration. The threshold is a compact index. Adaptivity alone did not produce transfer (§8). | Clamp the window ≥ ~±12–15 ms to stay above frame and timing noise. |
| **R4** | **Calm / reduced-stimulation presentation:** settings to disable particles, popups, combo text, screen flash and heavy haptics. Respect iOS Reduce Motion. Muted palette. | evidence-supported **as accessibility/comfort**; **hypothesis** for any attention effect | No controlled evidence either way (§7, gap). Reduce Motion support is standard iOS accessibility practice. | Currently only sound, music and haptics toggles exist. Reduce Motion is not handled. |
| **R5** | **Adjustable session length and gentle stopping:** player-set duration (1/3/5/10 min), a soft "session complete" screen, no streak punishment, no loss-framed timers in calm modes. | evidence-supported (design ethics) | Avoids compulsive-loop mechanics. The observational media-use association is modest (Ra 2018, §7). Reward sensitivity in ADHD (§7). | Pairs with R2. |
| **R6** | **Raise speed floors and window floors in Sudden Death, Tiny Window, Precision and Endless** so PERFECT stays perceptible. | evidence-supported (signal vs noise) | Windows of ±5–10 ms are below a 60 Hz frame. Outcomes become noise and frustration rises (frustration was the main AKL-T01 adverse event, §5). | Balance change. Leaderboards would need a reset or a new season. |
| **R7** | **Non-self-paced sustained-attention protocol:** the indicator crosses centre on an externally paced schedule; an untapped crossing counts as an omission; optional variable inter-target intervals. Duration ≥ 5–10 min to observe lapses. | **hypothesis** | Converts the game toward a CPT-like structure, where ADHD group differences are large (§2.1, Huang-Pollock 2012). Whether practicing it transfers is unknown; CCT meta-analyses suggest attention training rarely does (§3, Rapport 2013). | Useful mainly as a **measurement condition** in the study (USER_STUDY_PLAN). Do not market it as attention training. |
| **R8** | **Go/no-go variant:** on some crossings the target turns a "no-go" color (or a flip cue appears late), and the player must withhold. | **hypothesis** | Adds a genuine response-inhibition demand (§2.3). SSRT differences may reflect general processing (Alderson 2007). Inhibition did not transfer in CCT meta-analyses (Westwood 2023). | Keep the no-go rate ~20–30%. Log commission errors separately. |
| **R9** | **Rename "Focus" mode** (e.g. "Minimal") and avoid "focus/attention" in mode names and metadata. | evidence-supported (regulatory) | Apple 2.3/2.3.14, FTC substantiation ([COMPLIANCE.md](COMPLIANCE.md)). | Copy change only. Coordinate with the 1.2.0 "focus-practice mode" plan. Call it "Practice Session". |
| **R10** | **Fairness cues in Chaos/Mirror:** brief cue before tempo/direction changes; time-based (not per-frame) flip probability with a lower cap. | evidence-supported (design) / hypothesis (cognitive) | Reduces perceived randomness. Allows adaptation-cost measurement (Hove 2017, §2.5). | Logging change events enables "adaptation" metrics. |

**Suggested 1.2.0 scope:** R1, R2, R4, R5 and R9. These are low-risk, honest and claim-free.
- **R3** and **R6** are balance work.
- **R7** and **R8** belong in a study build first, not the public game.
