# Perfect Tap

A one-button timing game for iOS. A glowing indicator sweeps left ↔ right across a bar;
tap when it crosses the center. Precision builds combos, combos multiply score, the
sweep keeps speeding up. Fifteen modes remix that one mechanic.

> This README was reconstructed from the code in Nov 2026. The original Base44
> template README is preserved in git history (commit `35b6004`).

## Repository layout

| Path | What it is | Status |
|---|---|---|
| `PerfectTap/` | **The product.** Native SwiftUI iOS app (iOS 16+), Firebase backend, AdMob, StoreKit 2 | Active |
| `PerfectTap/project.yml` | XcodeGen spec — **source of truth** for the Xcode project | Active |
| `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc` | Firestore config for project `perfecttap-48a08` | Active (needs hardening, see below) |
| `src/`, `index.html`, `vite.config.js`, `package.json` | Original **Base44 React web version** the iOS app was ported from (Mar 2026) | Legacy / reference |
| `functions/*.ts` | Base44 **Deno** functions (`npm:@base44/sdk`). **Not** Firebase functions; nothing is deployed | Legacy / reference |
| `../perfect-tap.zip` | Original Base44 export | Archive |

## Core mechanic (as implemented)

- Indicator position `p ∈ [0, 1]`, center `0.5`. `speed` = seconds per full sweep (lower = faster).
- Accuracy uses distance from center as a fraction of the **full bar width** (same as the
  web original and exactly what `TapBarView` draws):

  | Result | `abs(p − 0.5)` | Points |
  |---|---|---|
  | PERFECT | ≤ 0.04 × mode scale | 100 |
  | GREAT | ≤ 0.10 | 70 |
  | GOOD | ≤ 0.20 | 40 |
  | MISS | > 0.20 | 0, −1 life |

- Combo grows on PERFECT/GREAT (Combo Frenzy: any hit). Multiplier ×1 / ×1.5 (3+) / ×2 (5+);
  Combo Frenzy ×2…×6.
- Input is **touch-down** (`Components/TouchDownTapArea.swift`). The tap is scored at the
  position visible on screen at the touch's hardware timestamp
  (`touch.timestamp − 1 frame`), extrapolated from the last simulated frame.
- Pure timing math lives in `Utils/TimingEngine.swift` (unit-tested); tuning constants in
  `Utils/GameConfig.swift`; per-mode rules in `Models/GameMode.swift`; the state machine
  (countdown → playing → revive → finished) in `ViewModels/GameViewModel.swift`.

### Modes
Classic, Endless, Timed (60s), Sudden Death, Combo Frenzy, Zen, Precision, Chaos, Mirror,
Invisible Zone, Rush (30s), Hardcore Combo, Tiny Window, Focus, plus Duel (async 1v1 via
code/friend invite). See `GameMode.description` / `.tip` for rules.

### Meta-progression
XP & levels, Season Pass (30 tiers, premium track), 21 achievements, daily quests,
7-day login rewards, lucky wheel, persistent challenges, coin shop (themes, tap FX),
friends, global leaderboard, rewarded-ad revive / double coins.

## Architecture

```
PerfectTapApp (Firebase + AdMob init) → RootView (AuthState router)
  AuthViewModel   anonymous Firebase Auth, username, optional email link, delete account
  AppRouter       NavigationStack path ([AppRoute])
  GameViewModel   CADisplayLink loop @60fps → IndicatorRelay (only TapBarView observes it)
  FirebaseService all Firestore/Auth/Functions calls (players, duels, friends, invitations)
  EconomyManager  local-first profile persistence (UserDefaults) + cloud sync
  PurchaseManager StoreKit 2, verified transactions, dedupe ledger
  AdManager       AdMob rewarded + interstitial, test IDs in DEBUG
  SoundEngine     procedural audio (AVAudioEngine, .ambient — respects silent switch)
```

The player profile is **local-first** (UserDefaults JSON), mirrored to `players/{uid}`.

## Build & run

Requirements: Xcode 26.x **with the matching iOS platform installed**
(Xcode → Settings → Components, or `xcodebuild -downloadPlatform iOS`), XcodeGen.

```bash
cd PerfectTap
xcodegen generate            # only after editing project.yml
open PerfectTap.xcodeproj
```

Unit tests (pure logic, no simulator needed for the logic itself):
`⌘U` in Xcode (target `PerfectTapTests`), or
`xcodebuild test -project PerfectTap/PerfectTap.xcodeproj -scheme PerfectTap -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

UI test `PerfectTapUITests/ModeRuntimeQATests` drives all modes against live Firebase; it is
slow (10+ min) and only hard-fails if Home is unreachable.

Configuration: `PerfectTap/GoogleService-Info.plist` (public Firebase client config),
AdMob app ID in `project.yml`/`Info.plist`, signing team `K88C7DPG4C`.

## Known issues & technical debt (Nov 2026 audit)

Critical / High — **not fixed yet, need decisions or backend work**:
1. ~~Duel takeover / score rewrite~~ and ~~free-form player docs~~ — hardened in
   `firestore.rules` (52 emulator tests in `firestore-tests/`), **deployed to production 2026-11-04**.
   Rollback: `docs/rules-backups/firestore.rules.prod-2026-11-04` (exact copy of the previous live rules).
   Remaining gap: plausible fake coins/scores on one's *own* doc need Cloud Functions.
2. (see 1)
3. No server-side score validation: `submitScore` callable doesn't exist (the `functions/`
   folder is Base44/Deno code). The call fails silently.
4. Sign-out keeps the local profile and copies it into the next anonymous account
   (purchases / coins can be cloned; shared-device data bleed).
5. Account deletion only deletes `players/{uid}`; friendships, duels, invitations remain.
6. Revive is granted even if no ad is shown or the ad is closed early (product decision).

Medium / Low: lucky-wheel limit is per device; daily rewards use UTC days while quests use
local days; `stats.duelWins` is never incremented on iOS (duel achievements unreachable);
`ScoreBoost` is read but never consumed; no Dynamic Type / VoiceOver / Reduce Motion
support; privacy manifest incomplete (User ID, email, purchases); no UMP consent (EEA);
missing composite index for outgoing duel invitations; stale zone-label row alignment.

See `docs/MODERNIZATION_REPORT.he.md` for the full audit and roadmap.

## Change log

- **2026-11 recovery** (branch `recovery/modernization-2026-11`): touch-down input with
  timestamp scoring; hit windows restored to match the drawn zones; feedback on repeated
  results; cloud profile restore on reinstall; double-navigation guards; music double-start
  fix; `TimingEngine` + unit tests; `project.yml` now mirrors hand-made Xcode settings.
