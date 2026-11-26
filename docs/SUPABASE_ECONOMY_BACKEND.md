# Supabase authoritative economy backend (1.2.0)

Server side of `docs/ECONOMY_SERVICE_CONTRACT.md` (v1). Local only. Nothing
here is deployed, and `balanced-premium-rc1` stays `active = false`.

| Piece | Location |
|---|---|
| Migration (additive) | `supabase/migrations/20261125200000_authoritative_economy_sources.sql` |
| Season calendar (additive) | `supabase/migrations/20261126120000_season_calendar_alignment.sql` |
| pgTAP | `supabase/tests/database/economy_sources.test.sql` (122 assertions), `season_calendar.test.sql` (35) |
| AdMob SSV Edge Function | `supabase/functions/admob-ssv/index.ts`, logic in `_shared/admob.ts`, tests in `_shared/admob.test.ts` |

## Behaviour while no config is active (production today)

Nothing changes. `private.sanitize_economy` dispatches to the previous body
(renamed `sanitize_economy_legacy`) without changing it. The purchase functions
keep their `pending_iap_coins` path. `submit_economy_event` and
`record_verified_rewarded_claim` fail with `economy_disabled`. The migration
modifies no balance, item or ledger row. Its config `UPDATE` only applies to
an inactive row.

## `public.submit_economy_event(p_event_key uuid, p_source text, p_payload jsonb) → jsonb`

The function is authenticated only and follows the invoker → definer pattern
(`private.submit_economy_event` → `private.submit_economy_event_for`). The rate
limit is 120 calls per minute. A profile is required. Every call takes a lock on
the player's `private.economy` row, so caps and uniqueness checks are race-free.
Unique indexes (`economy_grants` PK and `(user_id, event_key)`) are the final
safeguard. The order of checks is: active config → payload shape → rate →
profile → **duplicate event_key** (answers `duplicate` with the original
`granted`, `segmentIndex` and `itemID`) → `legacy_review_required` → source rule
→ `already_claimed` → limits.

| source | payload | server rule (config key) |
|---|---|---|
| gameplay | `mode, score, max_combo, perfects, taps, duration_ms, played_at (ISO-8601), session_id` | `mode` must be a key of `mode_bonus` other than `duel` (only `classic` qualifies). `played_at` must fall within `gameplay_max_age_hours` (72) and at most `gameplay_clock_skew_seconds` (300) in the future. The run must pass `private.check_plausibility` with elapsed = `duration_ms`. If `session_id` is a `start_game_session` id, the server elapsed time is used as the upper bound. coins = max(`minimum_game_coins`, score/`score_coin_divisor` + `combo_bonus` + `mode_bonus`). Grants once per `session_id`. |
| duel | `duel_id` | Reads the player's own score and combo from `public.duels`. The player must have submitted a score within 72 h. Uses the same formula with `mode_bonus.duel` and grants once per duel. |
| quest | `quest_id, difficulty, server_day` | `server_day` must be today or yesterday (UTC). `difficulty` must match `quest_difficulties[quest_id]`. Pays `quest_rewards[difficulty]`, once per (day, quest), with at most `quest_daily_limit` (3) quests per day. |
| achievement | `achievement_id` | Pays `achievement_rewards[id]`, once ever. |
| challenge | `challenge_id` | Pays `challenge_rewards[id].coins` plus the optional `.item`, once ever. |
| season_tier | `season_id, tier` | `season_id` must be the current season of the `season_calendar` rule (see "Season calendar"), or the previous season until its end + `grace_hours`, and `tier` ≤ `tiers`. Pacing is a per-season claim rate: the player's `season_tier` claims already made for that season id (grant keys `season:<id>:*`, other tiers) + 1 must be ≤ (whole days since that season started + 1) × `max_tiers_per_day`. A tier carried over from an earlier season (tier 26 on day 1) is accepted. Coins come from `season_coin_cycle[(tier-1) % len]`, once per tier. If the stored profile has `season_premium = true`, `season_premium_items[tier]` is granted too. A player who unlocks premium later sends the same tier again, and that call pays the item only. |
| wheel | `{}` (ignored) | Once per UTC day. The server picks `floor(random()*8)` and pays `wheel_rewards[segment]`. The response carries `segmentIndex`. |
| starter_item | `item_id` | The item must be in `starter_items`. One pick per player, and it adds the item to `owned_items`. If the player already owns that item, the response is `already_owned` and the pick stays unused. A 1.1 starter grant (`grant_starter_v1` marker plus a starter item) counts as the pick and returns `already_claimed`. |

`gameplay` and `duel` share `gameplay_daily_cap` (1500 per UTC day). Coins
above the cap are not paid. The response is `status: "capped"` with the partial
`granted` amount, and the excess is stored in `economy_grants.capped`.

Response: `{status, granted, balance, coinDebt, segmentIndex?, itemID?}`, where
`status` is one of `applied | duplicate | capped | already_owned | recorded`.

## Season calendar (shared with iOS)

`active_season` (one placeholder season, `season_1_neon_nights`
2026-12-01..2027-03-01) is replaced by a deterministic rule that the server
(`private.season_at`, `private.season_tier_verdict`) and iOS
(`EconomyConfig.SeasonCalendarRule`, `SeasonSchedule` in
`ios/PerfectTap/Models/SeasonPass.swift`) compute identically, in UTC:

```
season_calendar = {anchor: "2026-03-01", length_months: 3, id_format: "season_<n>",
                   tiers: 30, max_tiers_per_day: 15, grace_hours: 72}
n = floor(whole months since anchor / length_months) + 1
start = anchor + (n-1)·length_months months (inclusive), end = start + length_months (exclusive)
```

So 2026-11-26 is `season_3` (Sep 1 – Nov 30) and 2026-12-01 00:00 UTC starts
`season_4` (Dec 1 – Feb 28). A `season_tier` claim for the previous season is
accepted for `grace_hours` after the boundary (offline claims). Outside that
window it fails `invalid_payload`. The iOS outbox drops a `season_tier` refused
with `invalid_payload` only once its season is outside the window by the same
rule. Inside the window it keeps the event and retries without blocking other
events, since the refusal there can only come from clock skew. Grant keys stay
`season:<id>:<tier>`, so earned tiers and rewards are never reset or deleted.
The anchor must be the 1st of a month. A malformed calendar fails closed (no
claim accepted). The shared date → id and claim-window tables live in
`supabase/tests/database/season_calendar.test.sql` and
`SeasonCalendarAlignmentTests` (iOS). Change both together.

**Pending owner approval:** the season length (`length_months = 3`), the anchor
(`2026-03-01`) and `grace_hours = 72` are owner-tunable values that are not
approved yet. Changing them requires the same change in
`EconomyConfig.SeasonCalendarRule.balancedPremiumRC1` (pinned by unit test and
pgTAP).

## Service-role functions

- `public.record_verified_rewarded_claim(p_user, p_event_key, p_source, p_ad_transaction_id, p_reference_event_key default null, p_claim_index default null)`
  — granted only to `service_role`. The server computes the amount:
  `home_rewarded` = `home_rewarded_coins` (1 per day); `double_coins` = the
  `granted` amount of the referenced gameplay/duel grant, which must belong to
  the same player and be at most 24 h old (1 per day, once per reference);
  `revive` = 0 (3 per day); `season_progress` = 0 (1 per day). One AdMob
  `transaction_id` pays at most once and at most one user
  (`private.rewarded_ad_receipts`).
- `record_verified_purchase`: when a config is active, a coin pack goes through
  `apply_economy_delta(event_key = private.deterministic_uuid('iap_coins:'||transaction_id), source 'iap_coins')`.
  The ledger PK on `transaction_id` and the `owned_by_other_account` check stop a
  transaction from crediting a second user. A global unique index on
  `economy_events(event_key) where source='iap_coins'` backs this up.
- `revoke_purchase` / `reinstate_purchase`: when a config is active, a refund
  takes back unsynced pending coins first. It then debits the ledger down to 0
  at most, never below. The shortfall is recorded as `metadata.uncollected` and
  `coin_debt` is never touched. A reversal restores exactly what the refund took
  (`from_pending + debited`). Event keys are deterministic per
  (transaction, revocation time), so repeated calls are idempotent.
- `private.reconcile_legacy_economy(p_dry_run default true, …thresholds)` — returns one row per `pending` account:
  - `accepted`: the balance ≤ verified IAP coins + 2000 + 2500 × account-age-days. This rule uses server evidence only.
  - `review`: the account has a refunded coin purchase; or the balance is ≤ 3× that allowance; or it is a legacy-claimed account supported by `stats.totalGames` × 120. Client-reported history can lead to `review` but never to `accepted`.
  - `rejected`: none of the above.

  A dry run changes nothing. With `false`, the function writes
  `legacy_economy_reviews` and the statuses. Accepted accounts keep their
  **current** balance. Review and rejected accounts keep theirs frozen for a
  human decision. **No balance is ever reduced.**

## save_profile while a config is active

- `coins` is pinned. For an `accepted` account it is set to
  `confirmed_balance`. For any other status it is set to the stored profile
  balance, which freezes it (no increase, no silent decrease).
- Coin-sold items, starter items, challenge items and season-premium items
  (`private.server_owned_items`) are kept only if the stored profile already has
  them. Stored server-granted items survive a stale client list. Other items
  behave as before.
- `daily_reward_last_claim` and `daily_reward_streak` are server-owned. Without
  this, a client could reset the streak or the last-claim day and claim the
  daily reward again.
- `season_premium` = the stored value OR a count of verified `season_progress`
  claims ≥ `season_ads_required`.
- Leftover `pending_iap_coins` from the inactive era are moved into the ledger
  on the first save, so pinning does not lose them.
- `no_ads` and premium-skin rules are unchanged (legacy body).

## Deviations from contract v1 and clarifications (iOS must note)

1. **`record_verified_rewarded_claim` signature changed.** The undeployed
   candidate `(uuid, uuid, text, date, smallint, int)` took `p_amount` and
   `p_server_day`. It is dropped. The new signature takes
   `p_ad_transaction_id` and `p_reference_event_key` (required for
   `double_coins`). The server day is always "today UTC". `p_claim_index` is
   advisory only: the server assigns the next index, so a stale client index
   never burns a claim.
2. **AdMob `custom_data` format** (set by iOS in
   `GADServerSideVerificationOptions.customRewardString`). Either JSON
   `{"event_key":"<uuid>","source":"home_rewarded|double_coins|revive|season_progress","claim_index":1,"reference_event_key":"<uuid>"}`
   or pipe-delimited `event_key|source|claim_index|reference_event_key`.
   `user_id` must be the Supabase uid. `reference_event_key` is the `event_key`
   of the gameplay/duel `submit_economy_event` call being doubled.
3. **New error codes:**
   - `duel_score_pending`: the player's own duel score has not been submitted yet. **Retryable**, so keep the event in the outbox.
   - `duel_not_found`: terminal.
   - Other terminal codes from the existing list: `invalid_payload` (also used for a wrong season, a day outside today/yesterday, or a mode that earns no coins), `implausible_result`, `already_claimed`, `claim_limit`, `item_unavailable`, `legacy_review_required`, `profile_required`, `economy_disabled`, `rate_limited` (retryable).
4. **Pinning for non-accepted accounts** (principle 4): the balance is pinned
   to the stored profile balance, not `confirmed_balance`. For a pending
   legacy account, `confirmed_balance` is a snapshot taken at migration time
   and may be older than the stored balance. Paid coins are added on top of
   the stored balance (`apply_economy_delta` adds the delta for non-accepted
   accounts).
5. **The legacy gate is also bypassed for `iap_revoke` / `iap_reinstate`**,
   not only `iap_coins`. Otherwise a refund for a pending account would fail.
6. **Extra config keys** (additive):
   - `gameplay_max_age_hours`, `gameplay_clock_skew_seconds`
   - `quest_daily_limit`, `quest_difficulties`
   - `season_premium_items`
   - `season_calendar{anchor, length_months, id_format, tiers, max_tiers_per_day, grace_hours}` (replaces `active_season`, migration 20261126120000)
   - `combo_bonus` has the shape `[{min, coins}]`; `mode_bonus` has the shape `{classic: 2, duel: 6}`
   - `challenge_rewards` has the shape `{id: {coins, item|null}}`
7. **Achievements:** Swift `Achievement.all` has **36** entries (its comment
   says 37). All 36 are mirrored with the Swift coin values.
8. **Values awaiting owner approval:**
   - `gameplay_daily_cap = 1500`
   - season calendar: `anchor = 2026-03-01`, `length_months = 3`, `grace_hours = 72`
   - `max_tiers_per_day = 15`
   - the reconciliation thresholds

## Edge Functions

- `admob-ssv` (GET, `verify_jwt = false`). Handles `Deno.serve` and the shared
  `serviceClient()`.
  - Verifies the DER ECDSA P-256 signature over the raw query before
    `&signature=`. Nothing may follow `signature`/`key_id`.
  - Verifier keys are cached for 24 h. An unknown `key_id` triggers at most one
    refetch per 5 min. Stale keys are served if Google is briefly unreachable.
  - Rejects timestamps older than 72 h or more than 5 min in the future.
  - Terminal outcomes answer 200 (`{status:"rejected",reason}`) so Google stops
    retrying. Transient failures answer 5xx.
  - A signed callback without `user_id`/`custom_data` (the console "verify URL"
    test) answers `verified_no_claim`.
- Existing functions:
  - `app-store-notifications` imported a different supabase-js version
    (`2.49.4`) and used a non-null-asserted `SUPABASE_URL`. It now uses the
    shared `serviceClient()` (2.119.0, fails closed with 503) and rejects
    non-POST requests with 405.
  - The other functions already used `Deno.serve` and `requireUser()`.
  - Five pre-existing files were reformatted with `deno fmt`. The stale
    `withSupabase` comment in `config.toml` was fixed.

## Residual risks

- **Quest progress is client-reported.** The exposure is bounded by 3 quests per day.
- **Achievement and challenge conditions are client-reported.** Each pays once ever, with fixed amounts (27,450 coins in total for achievements). A cheater could claim all of them at once.
- **Gameplay is plausibility-checked, not proven.** A modified client can send plausible runs up to `gameplay_daily_cap`.
- **AdMob `user_id` is set by the client SDK.** A modified client could direct its own ad rewards to another uid. This needs real ad views, stays within daily limits, and gives the attacker nothing.
- **The season pace check is a claim rate.** It limits claims per season id per day (`max_tiers_per_day`), not the tier index. The server has no season XP of its own, so a modified client can claim any tier ≤ `tiers` within that rate.
- **`legacy_economy_reviews` support tooling** (manual accept, adjust, goodwill) is not built yet. Rejected and review accounts stay frozen until it exists.
- **Concurrency is enforced by a row lock plus unique indexes.** pgTAP runs in one session, so it asserts the indexes rather than racing two connections.
