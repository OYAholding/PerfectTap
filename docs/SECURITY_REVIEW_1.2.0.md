# PerfectTap 1.2.0 — Adversarial security & economy review (2026-11-27)

Two independent read-only reviewers (server: Supabase SQL + Edge Functions;
client: iOS economy / StoreKit / outbox) attacked the 1.2.0 candidate. Every
finding below was re-traced in code before a fix was written. Fixes are
minimal and each has a regression test.

- Server fixes: `supabase/migrations/20261127110000_economy_hardening.sql`
  (+ guarded casts edited in the undeployed `20261125130443`).
- Server tests: `supabase/tests/database/economy_hardening.test.sql` (28),
  updated `economy_ledger.test.sql`; Deno `_shared/admob.test.ts`.
- Client fixes: `EconomyEvent.swift`, `EconomyOutbox.swift`,
  `EconomyService.swift`, `AuthViewModel.swift`, `PurchaseManager.swift`,
  `EntitlementLedger.swift`. Client tests: `EconomyHardeningTests` in
  `PerfectTapTests/EconomyServiceTests.swift`.

Nothing here is deployed. Production is still at `20261114120000`.

## Server findings

| ID | Sev. | Finding | Status | Fix | Test |
|---|---|---|---|---|---|
| C1 | critical | `purchase_economy_item` granted the item even when `apply_economy_delta` answered `duplicate` → reusing any existing event key (e.g. a free wheel spin) bought every shop item for free | **Fixed** | Item granted only when the debit is `applied`; replay of the same purchase → `duplicate`; any other replay → `invalid_payload`. Lock order economy → profile_data (L1) | hardening 4–11 |
| C2 | critical | JIT legacy refresh accepted a Firestore document for any Firebase uid (incl. brand-new accounts whose owner can write the doc) → forged items / premium / auto-accepted coins | **Fixed (after activation) / mitigated (before)** | Import-snapshot uids recorded (`legacy_snapshot_uids`); JIT-only uids recorded. After any owner approval, a claim drops server-owned state (no_ads, season_premium, daily streak) for everyone, drops server-owned + unpaid premium items for JIT-only players, and sends JIT-only coins to `review` (never auto-accepted). **Owner action:** disable new Firebase sign-ups (closes the source) | hardening 25–26 |
| H1 | high | Claiming legacy data on an already-`accepted` account lost the legacy coins (next save pinned to confirmed balance) | **Fixed** | Claimed coins + current balance become the reviewed legacy candidate (`pending`) | hardening 22–24 |
| H2 | high | Reconciliation allowance grew without bound with account age (≈915k for a 1-year account) | **Fixed (policy bound)** | Age counted ≤180 days; Sandbox purchases are not evidence. Allowance parameters stay owner inputs; run dry-run first | hardening 28 |
| M1 | medium | Sandbox purchases credited real coins and counted as paid evidence | **Partly fixed** | Excluded from reconciliation evidence. Crediting Sandbox coins to the tester's own account remains (needed for App Review / TestFlight); documented risk | hardening 28 |
| M2 | medium | `season_premium` was sticky forever and could be client-set in the 1.1 era | **Fixed** | Active economy: premium = verified SSV season ads in the current season ≥ `season_ads_required` | hardening 12–15 |
| M3 | medium | During containment (config inactive) clients could add server-owned items, kept after re-activation | **Fixed** | Once any config was ever approved, the legacy path still filters server-owned items (stored ones kept). Inert before the first approval (1.1 unchanged) | hardening 1–2, 19–21 |
| M4 | medium | 1.1.x clients cannot earn once a config is active | **Open (activation prerequisite)** | Activation of the authoritative economy requires a forced minimum app version; listed as a gate in the runbook | — |
| M5 | medium | Client-reported achievements/challenges could pay >26k coins immediately | **Mitigated** | Server cap `progress_daily_cap` (3000/UTC day, first claim always passes) → `progress_daily_limit`; client keeps such events (never expire). Residual: still claimable over days; server-side evidence for big achievements is a later improvement | hardening 16–18 |
| L1 | low | Lock-order deadlock risk in shop purchase | **Fixed** | see C1 | — |
| L2 | low | Unguarded `::bigint` casts could abort the migration on odd stored coins | **Fixed** | Guarded regex parse (undeployed migration edited) | reset + all suites |
| L3 | low | Daily streak could be preset in the 1.1 era | **Mitigated** | Claim path drops streak after activation; profile path already pins it while active | — |
| L4 | low | Reconcile re-run collided on the deterministic ledger key | **Fixed** | Key includes the candidate | — |
| L5 | low | AdMob callbacks from any ad unit on the account were paid | **Fixed (opt-in)** | `ADMOB_ALLOWED_AD_UNITS` secret; when set, other units are rejected | Deno 2 tests |
| L6 | low | Refund for a deleted account failed forever (FK) | **Fixed** | Tombstone stored without the user | hardening 27 |

Verified sound by the server reviewer: payload validation, uniqueness,
per-user row locks and caps, gameplay plausibility + daily cap, AdMob SSV
signature/replay/timestamp, StoreKit ownership (`appAccountToken`), refund /
reversal symmetry, `coin_debt` never written, privileges (no client-callable
SECURITY DEFINER in `public`), RLS on all new tables, ASSN dedupe/staleness.

## Client findings

| ID | Sev. | Finding | Status | Fix | Test |
|---|---|---|---|---|---|
| H1 | high | `legacy_review_required` dropped earned events; once-per-account events expired after 7 days | **Fixed** | Kept, retried non-blocking every ≥6 h; achievements/challenges/starter never expire. `economy_disabled` fallback: flag must only be enabled with an active config (runbook gate) | `testLegacyReview…`, `testOncePerAccount…` |
| H2 | high | Events earned with no backend user (first launch offline) were dropped | **Fixed** | Kept in an `unattributed` outbox and adopted by the device's first account only; after any account existed they are never adopted (no cross-account credit) | `testEventsEarnedBefore…`, `testEventsWithoutAUser…` |
| M1 | medium | A failed outbox read silently wiped the outbox | **Fixed** | Unreadable file → never written, re-opened later; per-entry lossy decode; non-JSON moved aside | `testOneUndecodable…`, `testCorruptOutbox…` |
| M2 | medium | Guest → account merge unioned claim markers, suppressing the account's own claims | **Fixed (flag ON)** | Markers from the cloud copy when authoritative | (merge is private; covered by review) |
| M3 | medium | Purchases recorded by 1.1.x could never be restored | **Fixed** | Legacy non-consumable markers upgrade to full records (no second grant, server re-acknowledges); legacy refunds revoke; legacy coins untouched | `testLegacyNonConsumable…`, `testRefundOfLegacyRemoveAds…` |
| M4 | medium | Flag ON + on-device verification would finish coin transactions credited nowhere | **Fixed** | Fail-closed `UnavailableVerifier` | `testAuthoritativeBuildWithout…` |
| M5 | medium | Daily claim replaced the whole local profile with the server copy | **Fixed** | Only coins, streak, last claim, owned items | `testDailyClaimNever…` |
| L1 | low | Duel coin event blocked the queue until the score landed | **Fixed** | `duel_score_pending` non-blocking | policy test |
| L2 | low | Cancelled flushes pushed events into long backoff | **Fixed** | Cancellation is not an attempt | — |
| L3 | low | Account switch during verification could apply effects to the new account | **Fixed** | Account re-checked after every verification await → deferred | StoreKit suite |
| L4 | low | Refund delivered while another account is signed in can be missed (finished consumables) | **Open (low)** | Server ASSN revokes server side; client copy corrects on next refresh when flag ON | — |
| L5 | low | Home rewarded ad makes a day-verification call with flag OFF | **No change** | Present since 1.1 (baseline), not a 1.2 regression | — |
| L6 | low | Device clock forward can save a future season number | **Open (low)** | Rollover is forward-only by design; at most one season without reset for that player | — |
| L7 | low | Orphan outbox files of abandoned anonymous uids | **Open (low)** | Bounded, a few KB | — |

Verified sound by the client reviewer: event keys created once and persisted
before send, atomic writes, account binding across awaits, StoreKit pipeline
(finish only after server ack, idempotent ledger, restore never re-credits
coins, refund-before-purchase tombstone, Ask to Buy), Release can never sell,
flag OFF arithmetic identical to 1.1.1.

## Compatibility with the live 1.1.x app

- Before the first owner approval of an economy config, every server path the
  1.1.x app uses behaves as today (pgTAP `perfecttap.test.sql`, hardening 1–2).
- After activation 1.1.x clients cannot earn (M4) → forced minimum version is a
  hard gate for activating the authoritative economy.
- `season_progress_number` is an extra profile key: 1.1.x ignores it; a 1.2
  client adopts a profile without it as the current season (no wipe).
