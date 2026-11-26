# PerfectTap 1.2.0 — QA Matrix

**Code under test:** `a7873e0` (local `release/1.2.0` tip: contract v1 on top of `24b45a2` Model B candidate; origin `release/1.2.0` = `e7714d7`).
**Run by:** Agent D (QA/CI), 25.11.2026. **Host:** Xcode 26.6 (17F113), Deno 2.9.7, Supabase CLI 2.119.0.
**Simulator:** iPhone 16e, iOS 18.5, UDID `911E86AC-88A9-4E12-A645-A81FB553C53E` only, private `-derivedDataPath`.
**Host load during runs:** load average 45–50 (other agents building concurrently). Timing results are therefore not representative.

**Status legend:** PASSED / FAILED / BLOCKED (cannot run yet: missing prerequisite, stated in the row) / NOT RUN (could run, was not run in this pass).
A row is PASSED only if it was actually executed in this pass. Earlier results from other documents are quoted as "prior", never as PASSED.

## Re-run 2026-11-26 — integrated `release/1.2.0` @ `e424776` (supersedes rows below)

| Area | Result | Evidence |
|---|---|---|
| iOS unit (`PerfectTapTests`) | **PASSED 128/128** | iPhone 16 Pro sim; CI `ios-unit-tests` |
| StoreKit local (`PerfectTapStoreKitTests`) | **PASSED 26/26** | flake fixed (`c331837`): 5 consecutive runs 26/26 |
| UI mode runtime matrix | **PASSED 15/15 modes** | test fixed (`29e2f49`): Rush declines revive deterministically; all 15 `QA_RESULT … PASS` |
| Release sim build + built flags | **PASSED** | all 6 flags NO in built Info.plist |
| Monetization flag guard / secret guard | **PASSED** | Release-IAP-aware guard (`aa3a1d8`) |
| Deno (5 functions + `_shared`) | **PASSED** | fmt/lint/check/test, 23 tests |
| Backend pgTAP | **PASSED 319/319** | local stack after `db reset`; CI `backend` 282/282 at `90a6c66` |
| Performance (simulator, idle host) | **PASSED ×2** | `docs/perf/qa-1.2.0-e424776-iphone16pro-run{1,2}.json`; round end → Game Over avg 39 / 35 ms (baseline 55.5), 0 frames ≥250 ms. The earlier 229 ms was host load |
| ASC reconciler (Ruby) | **PASSED 7/7** | dry-run only |
| Apple Sandbox / device / TestFlight / Ask to Buy / refunds on device | **BLOCKED** | 0/9 ASC products, owner gates G4–G10 |
| ATT/UMP consent UI tests | **PASSED 3/3** | now on the offline backend (no production writes) |
| iPad, audio interruptions, AirPods | **NOT RUN / BLOCKED** | device-only |


## 1. Automated — executed in this pass

| Area | What | Command / evidence | Status | Notes |
|---|---|---|---|---|
| iOS unit | `PerfectTapTests` (98 tests: consent, timing, duels, codecs, legacy claim, balanced economy, purchases/cosmetics, 10 stability regressions, practice/metrics, game phase) | `xcodebuild test -scheme PerfectTap -only-testing:PerfectTapTests`, unsigned | **PASSED** | 98/98, 0 failures |
| StoreKit tests | `PerfectTapStoreKitTests` with `StoreKit/PerfectTap.storekit` via `SKTestSession` (catalog matches code; buy all 9 products) | `xcodebuild test -scheme PerfectTapStoreKitTests` | **PASSED** | 2/2 on iOS 18.5. Prior note: `SKInternalErrorDomain Code=3` on the iOS 26.5 runtime |
| Release build | `PerfectTap`, `-configuration Release`, generic iOS Simulator, unsigned | `xcodebuild build … -configuration Release` | **PASSED** | BUILD SUCCEEDED |
| Release flags (built) | Built Release `Info.plist`: all 6 monetization flags = NO, `PT_BACKEND=supabase` | `scripts/qa/assert-built-flags.sh <app>` | **PASSED** | |
| Release flags (source) | No flag = YES / non-literal outside Debug in project.yml, pbxproj, xcconfig, plist | `scripts/security/check-monetization-flags.sh` (+ `--self-test` 11/11) | **PASSED** | Also confirmed it FAILS when Release is flipped in a scratch copy (pbxproj and project.yml) |
| Secret files | No .p8/.p12/asc.env/.env/service-account JSON, PEM key, `sb_secret_`, service_role JWT tracked | `scripts/security/check-secret-files.sh` (+ `--self-test` 8/8) | **PASSED** | gitleaks not run locally (CI job `secret-scan`) |
| Backend target | project.yml URL == `supabase/.perfecttap-ref`, publishable key only, Release backend = supabase | `scripts/security/check-backend-target.sh` | **PASSED** | |
| Deno — all functions | fmt / lint / check / test for `_shared`, `app-store-notifications`, `claim-legacy-account`, `delete-account`, `verify-purchase` | `scripts/qa/deno-functions.sh` | **FAILED** | 2 failing steps: `_shared` fmt (5 files not `deno fmt`-formatted), `app-store-notifications` lint (`no-import-prefix`, `index.ts:6`). Check passed for all 4 functions; `_shared/purchases.test.ts` 10/10 passed |
| UI: mode runtime matrix | `ModeRuntimeQATests` with `TEST_RUNNER_PT_QA_OFFLINE=1` (offline backend, no ads) | `xcodebuild test-without-building -only-testing:…ModeRuntimeQATests` | **FAILED** | 10/15 modes PASS; Rush FAIL; 4 modes not reached. See §2 |
| UI: gameplay perf workload | `GameplayPerformanceTests` (Classic ×3, Timed 60 s, Endless background/foreground) | same run | **PASSED** (functional) | Completed in 164 s. Perf gate: see the Performance row |
| UI: IAP review screenshots | `IAPReviewScreenshotTests` (`-PTIAPPreview`, offline) | 1st: `test-without-building`, unsigned (`CODE_SIGNING_ALLOWED=NO`); 2nd: `xcodebuild test`, ad-hoc signed | **PASSED** (signed) | Unsigned run FAILED: prices stuck on "Loading…" (`IAPReviewScreenshotTests.swift:35`). The signed rerun passed in 37 s with all 5 prices and 4 premium skins. Scheme-attached StoreKit configuration needs a signed app; `SKTestSession` unit tests work unsigned |
| UI: ATT consent | `TrackingConsentUITests` | — | **NOT RUN** | Uses the Debug backend, which is the production Supabase project `pgvtaotdyspwnpqtxpju`, and creates an anonymous player. Not run because of the no-production rule. Needs an offline flag or a staging backend |
| Performance (simulator) | perf-probe JSON from the workload above → `scripts/qa/perf-gate.py` vs `after-1.2.0-default-run2` | probe copied from the simulator container | **FAILED (inconclusive)** | 0 frames ≥250 ms in gameplay, p99 23.9 ms, tap avg 0.14 ms. Failed: 4 frames ≥100 ms (limit 2), hitch 0.95% (limit 0.6), round end → Game Over avg **229 ms** (baseline 56) / max 415 ms, `game.finish` max 102 ms. The host was at load 45–50 and this is a different simulator model (16e/iOS 18.5 vs 17/26.5). **Rerun on an idle Mac before drawing conclusions** (`docs/perf/FREEZE_STUTTER_REGRESSION.he.md` B1) |
| Backend pgTAP | `supabase test db` (3 files, plan 132: core/RLS, purchase ledger, economy ledger) | — | **NOT RUN** | Agent B owns the local DB; `db reset` is forbidden for Agent D. Covered by the CI `backend` job. Prior: 132/132 |
| Backend integration | `supabase/tests/integration/run.sh` | — | **NOT RUN** | The script runs `supabase db reset --local`. CI only. Prior: 10/10 |
| CI YAML | `.github/workflows/ci.yml`, `pages.yml` parse plus structural check (jobs, runs-on, steps with run/uses) | `ruby -ryaml` | **PASSED** | actionlint is not installed, so expressions were not linted |
| PR ancestry | #12/#13 contained in `release/1.2.0`; merge simulation | `git merge-base`, `git merge-tree` | **PASSED** | See §4 |

## 2. Game mode matrix (UI, offline backend, iPhone 16e iOS 18.5)

| Mode | Status | Detail |
|---|---|---|
| Classic, Endless, Timed, Sudden Death, Combo Frenzy, Zen, Precision, Chaos, Mirror, Invisible Zone | **PASSED** | HUD, revive policy, Game Over title |
| Rush | **FAILED** | `rush_revive_continue_button_missing, rush_did_not_end, failed_to_return_home`. Cause: `24b45a2` changed `ReviveModalView` to a single "WATCH OPTIONAL AD TO CONTINUE" button (`Views/Game/ReviveModalView.swift:47`). The test still looks for "CONTINUE — FREE" / "WATCH AD TO CONTINUE" (`PerfectTapUITests/ModeRuntimeQATests.swift:208`) and never taps "Give Up", so the round never ends. **Test is stale.** No app defect is shown |
| Hardcore Combo, Tiny Window, Practice, Focus/Minimal | **NOT RUN** | `entry_path_failed`: the run cascaded after Rush stayed on screen. Re-run after the test fix |
| (test harness) | **DEFECT** | `test_mode_runtime_matrix` reported **passed** although 5 modes failed. `runMode` only prints `QA_RESULT` and never calls `XCTFail` (`ModeRuntimeQATests.swift:360`). CI or anyone reading only the XCTest result would miss mode failures |

## 3. Full area matrix

| Area | Scope | Status | Evidence / blocker |
|---|---|---|---|
| iOS unit | `PerfectTapTests` | PASSED | §1 |
| Game mode matrix | 15 modes | FAILED (10 pass, 1 fail, 4 not reached) | §2 |
| Game Over transitions | round end → Game Over, PLAY AGAIN ×2, back to Home | PASSED (functional) / perf inconclusive | `GameplayPerformanceTests`; `StabilityRegressionTests.testRoundEndReplacesStackWithoutExposingHome` (in the unit run) |
| Background/foreground | Endless with Home press mid-round, resume 3-2-1 | PASSED (simulator) | `GameplayPerformanceTests` step 3; `testGameResumesAfterViewReappearsWithStoppedClock`. Device: NOT RUN |
| Audio interruptions / AirPods | route change mid-round, call or Siri interruption | BLOCKED | Needs a physical iPhone and AirPods (`DEVICE_PROFILING_PROTOCOL.he.md` scenario 5) |
| Shop UI | tabs, preview, coin prices, flags-off state | PASSED (automated screenshot path, signed) / manual NOT RUN | Shop renders 4 coin packs, Remove Forced Ads, themes and premium tab with local StoreKit prices (`-PTIAPPreview`). Manual review of the flags-off UI NOT RUN |
| Cosmetic rendering | premium skins (Glitch, Neon Pulse, Liquid Chrome, Cosmic Gold) in gameplay | NOT RUN | Perf run with `TEST_RUNNER_PT_PERF_THEME=glitch` not executed in this pass. Prior: passed after the warm-up fix |
| StoreKit lifecycle (local) | `SKTestSession` purchase of all 9 products | PASSED | §1 |
| StoreKit lifecycle (unfinished / retry / duplicate delivery) | ledger v2 dedupe | PASSED (unit level) | Included in `PurchaseAndCosmeticsTests` (unit run). Device: BLOCKED |
| Account linking | Sign in with Apple linking of an anonymous account; consumables require a permanent identity | BLOCKED | Needs the Apple provider in Supabase plus a device (runbook G5, Sandbox scenarios 4–5, 7–8) |
| iPhone / iPad | iPad Air 11" portrait and landscape | NOT RUN | Only iPhone 16e was allowed in this pass |
| Economy sources/sinks | gameplay, daily, wheel, quest, rewarded, shop purchase | PASSED (unit, flag off) | `BalancedEconomyTests` in the unit run. Server side: NOT RUN (pgTAP in CI) |
| Caps | daily gameplay cap, revive cap 3/day, quest max 3/day | PASSED (unit: `RewardClaimLimiter`) / server NOT RUN | pgTAP `economy_ledger.test.sql` in CI |
| Duplicates | same `event_key` / `transaction_id` gives `duplicate`, no double credit | PASSED (unit + Deno `purchases.test.ts` 10/10) / pgTAP NOT RUN | |
| Offline | airplane mode mid-round; offline during purchase verification | BLOCKED (device) | UI runs used the offline backend only (`-PTUITestOfflineBackend`), which is not the same as a network loss |
| Backend pgTAP / RLS | 132 planned assertions | NOT RUN locally | CI `backend` job |
| Backend Deno | 4 functions + `_shared` | FAILED (fmt + lint) | §1 |
| Apple Sandbox | 10 scenarios in `STOREKIT_DEVICE_SANDBOX_QA.he.md` | BLOCKED | No ASC products (0/9), no Sandbox tester or device in this pass. Runbook G4/G5/G8 |
| TestFlight | internal build QA | BLOCKED | Runbook G10 |
| Ask to Buy | pending, then approve or decline | BLOCKED | Sandbox device |
| Refund / revoke / refund reversal | ASSN V2 → ledger, entitlement removal | BLOCKED (device and Sandbox) / Deno unit PASSED | `purchases.test.ts` |
| Real ads + revive | rewarded and interstitial ads, revive continues | BLOCKED | TestFlight only |
| ATT / UMP consent | 3 UI tests | NOT RUN | Hits the production Supabase project (§1) |
| Freeze/stutter on device | `DEVICE_PROFILING_PROTOCOL.he.md` | BLOCKED | Physical device |

## 4. PR dependency findings (read-only)

| PR | Head | Base | State | In `release/1.2.0`? |
|---|---|---|---|---|
| #12 `docs/adhd-attention-research` | `777011b` | main | OPEN, MERGEABLE/CLEAN | **Yes.** Ancestor of origin `e7714d7` and local `a7873e0` (merged in `1c0fb81`) |
| #13 `hotfix/1.1.1-stability` | `a3ee906` | main | OPEN, MERGEABLE/CLEAN, CI 3/3 green | **Yes.** Ancestor (first parent of `1c0fb81`) |
| #14 `release/1.2.0` | `e7714d7` (origin) | main | OPEN, MERGEABLE/CLEAN, CI 3/3 green | Local `release/1.2.0` is 2 commits ahead (`24b45a2`, `a7873e0`), **not pushed** |

- `git log e7714d7..a3ee906` and `e7714d7..777011b` are empty. The hotfix and docs branches have **no commits** that are missing from `release/1.2.0`. `main` (`8defb4f`) is the merge base of all three.
- Files touched: #12 is docs only (`docs/research/*`); #13 is 29 files (iOS, perf docs, `scripts/perf-run.sh`). No overlap.
- `git merge-tree`: 777011b+a3ee906 is clean, and its tree equals `1c0fb81^{tree}` (`b63b5a0`). a3ee906+e7714d7 is clean and equals the e7714d7 tree. The same holds for a7873e0. **No conflicts expected.**
- **Merge order to `main`:** #12 → #13 → #14 (each merges cleanly), or #14 alone, which brings both in and GitHub auto-closes #12/#13 as merged. Use merge commits, not squash: squashing #14 would orphan the #12/#13 SHAs and leave both PRs open and unmerged in GitHub's view. Push the 2 local commits (and the agent branches) to `release/1.2.0` before merging #14.

## 5. Defects for routing (found in this pass)

| # | Owner | File:line | Defect |
|---|---|---|---|
| D1 | Agent B | `supabase/functions/app-store-notifications/index.ts:6` | Inline `npm:@supabase/supabase-js@2.49.4` import. It bypasses the import map (2.119.0), fails `deno lint` (`no-import-prefix`), and bundles two supabase-js versions |
| D2 | Agent B | `supabase/functions/_shared/{firebase,firestore,http,purchases,purchases.test}.ts` | Not `deno fmt`-formatted (5 files). The CI `edge-functions` job stays red until `deno fmt supabase/functions` is run |
| D3 | Agent B | `supabase/rollback/20261122120000_purchase_containment.sql` | Containment predates `20261125130443_authoritative_economy_ledger`. It does not deactivate `private.economy_configs` and does not revoke `record_verified_rewarded_claim`. The runbook §15 step 2 covers this manually; consider extending the script |
| D4 | Agent A / iOS | `ios/PerfectTap/PerfectTapUITests/ModeRuntimeQATests.swift:208` | Stale after `24b45a2`: the revive button is now "WATCH OPTIONAL AD TO CONTINUE" (`Views/Game/ReviveModalView.swift:47`) and the test never taps "Give Up". Rush fails and the 4 later modes cascade |
| D5 | Agent A / iOS | `ios/PerfectTap/PerfectTapUITests/ModeRuntimeQATests.swift:360` | `emitResult` never calls `XCTFail`, so the matrix test passes even with failing modes |
| D6 | Lead / iOS | `ios/PerfectTap/PerfectTapUITests/TrackingConsentUITests.swift:15` | Runs against the Debug backend, which is the production Supabase project, and creates anonymous players. Needs `-PTUITestOfflineBackend` or a staging URL for Debug |
| D7 | Lead (perf) | `docs/perf/qa-1.2.0-a7873e0-iphone16e-loadedhost.json` | Round end → Game Over avg 229 ms / max 415 ms, `game.finish` max 102 ms (1.2.0 baseline: 56 / 100 / 23 ms). Measured on a host at load 45–50, so this is **not confirmed**. Rerun on an idle Mac. If it reproduces, suspect the `24b45a2` economy path in `finish` |
| D8 | scripts (not changed) | `scripts/perf-run.sh:26` | If the named simulator is missing, `set -e` + `pipefail` exit silently before the "not found" message. Always pass `PT_SIM_UDID`. The script also writes `docs/perf/<label>.xcodebuild.log` into docs |
| D9 | Lead / ops | `scripts/deploy-supabase.sh` | A staging deploy requires repointing `project.yml` (via `use-supabase-project.sh`). The runbook §6 requires reverting, and `scripts/security/check-backend-target.sh` (CI) catches a half-switched state. `--apply-purchases` deploys only `verify-purchase` and `app-store-notifications`: any new function (e.g. `admob-ssv`) needs a script change |

