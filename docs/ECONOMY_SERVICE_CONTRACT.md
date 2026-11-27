# PerfectTap 1.2.0 — Authoritative Economy Service Contract (v1)

Status: engineering contract shared by iOS (Agent A), Supabase (Agent B) and
StoreKit (Agent C). Values come from the server's active `economy_configs` row;
`balanced-premium-rc1` stays **inactive** (not owner-approved).

## Principles

1. The client **never sends an amount**. It sends *what happened*; the server
   computes the grant from the active config and enforces caps.
2. Every operation carries a client-generated `event_key uuid`, generated **once**
   when the event happens and persisted in the client outbox before the first
   send. Retries reuse it. Server: `(user_id, event_key)` unique → `duplicate`.
3. All balance changes go through `private.apply_economy_delta` (row lock,
   non-negative, ledger row in `private.economy_events`).
4. When an economy config is active, `save_profile` (client path) **cannot change
   `coins`** — it is pinned to `private.economy.confirmed_balance`. Owned items
   sold for coins can only be added by `purchase_economy_item` / server grants.
5. Paid (StoreKit) coin credits are verified money: they are credited to the
   ledger even when the player's legacy balance is still `pending`/`review`
   (legacy status only governs the *opening* balance).
6. Flag OFF (`PT_AUTHORITATIVE_ECONOMY_ENABLED=NO`, today's builds) ⇒ client
   behaviour is byte-for-byte the current legacy path. No new network calls.

## Client → server RPC

```
public.submit_economy_event(p_event_key uuid, p_source text, p_payload jsonb)
  returns jsonb  -- see Response
```
Authenticated only (`private.require_uid()`), rate limited, `security invoker`
wrapper over a `security definer` function in `private` (same pattern as
`claim_daily_economy_reward`). Fails `economy_disabled` when no active config.

| p_source | p_payload (client) | Server rule |
|---|---|---|
| `gameplay` | `{mode, score, max_combo, perfects, taps, duration_ms, played_at, session_id}` | mode must earn coins; plausibility (score ≤ f(taps, duration), taps/sec cap, played_at within 72h and ≤ now); coins = config formula; daily gameplay coin cap (config `gameplay_daily_cap`), excess recorded as `capped`. `session_id` unique per user. Duel games use `duel` source instead. |
| `duel` | `{duel_id}` | server reads the finished duel row it already owns; grant once per (user, duel_id). |
| `quest` | `{quest_id, difficulty, server_day}` | server_day ∈ {today, yesterday} UTC; max 3 per day; once per (day, quest_id); reward by difficulty from config. Progress itself is client-side (documented residual risk, bounded by cap). |
| `achievement` | `{achievement_id}` | id must exist in config `achievement_rewards`; once per user forever. Achievement + challenge coins capped per UTC day by `progress_daily_cap` (first claim of the day always passes) → `progress_daily_limit`. |
| `challenge` | `{challenge_id}` | id in config `challenge_rewards` (coins and optional item); once per user forever; shares `progress_daily_cap`. |
| `season_tier` | `{season_id, tier}` | season_id = current `season_calendar` season (or previous within `grace_hours`); tier ≤ server-tracked/plausible tier; once per (season_id, tier); coins from config season cycle. |
| `wheel` | `{}` | once per UTC day; **server** picks the segment (`gen_random_uuid`-seeded / `random()`), returns `segment_index` + amount. |
| `starter_item` | `{item_id}` | item must be config `starter_items` (Common); once per user; adds to `owned_items` without coins. |

Already defined (keep): `claim_daily_economy_reward(p_event_key)`,
`purchase_economy_item(p_event_key, p_item_id)`, `get_my_economy_state()`.

Service-role only (never callable by iOS):
- `record_verified_rewarded_claim(...)` — called by the AdMob SSV Edge Function
  (`admob-ssv`) after verifying Google's ECDSA signature; sources
  `home_rewarded`, `double_coins` (grant = the referenced gameplay grant, once),
  `revive` (0 coins, cap 3/day), `season_progress`.
- `record_verified_purchase(...)` — when a config is active, coin products credit
  via `apply_economy_delta(event_key = uuid_v5(transaction_id), source='iap_coins')`.
- `revoke_purchase` / `reinstate_purchase` — debit to zero, idempotent; `coin_debt`
  stays **inactive** (no automatic debt).

## Response (all economy RPCs)

```json
{ "status": "applied" | "duplicate" | "capped" | "already_owned" | "recorded",
  "granted": 0, "balance": 1234, "coinDebt": 0,
  "segmentIndex": 3,          // wheel only
  "itemID": "theme_neon" }    // shop/starter/challenge item
```
Errors are raised as `private.fail(code)`; codes clients must handle:
`economy_disabled`, `legacy_review_required`, `insufficient_coins`,
`already_claimed`, `claim_limit`, `item_unavailable`, `invalid_payload`,
`implausible_result`, `rate_limited`, `profile_required`,
`progress_daily_limit`, `duel_score_pending`.
`duplicate`, `already_claimed`, `already_owned` are terminal-success for the outbox.

Outbox dispositions (iOS `EconomyErrorPolicy`, hardening 2026-11-27):
- retry, blocking: network, `economy_disabled`, `rate_limited`, `profile_required`, unknown codes;
- retry, non-blocking: `legacy_review_required` (≥6 h backoff — the event is
  paid once the legacy balance is resolved), `duel_score_pending`,
  `progress_daily_limit`, and an in-window `season_tier` `invalid_payload`;
- drop (logged): `insufficient_coins`, `claim_limit`, `item_unavailable`,
  `invalid_payload`, `implausible_result`, `duel_not_found`, …

`purchase_economy_item`: the item is granted only when the debit is applied.
Replaying the same `(event_key, item)` returns `duplicate`; reusing an event key
for anything else fails `invalid_payload`.

## Client outbox (iOS, flag ON only)

- `EconomyOutbox` persists pending events (event_key, source, payload,
  created_at, attempts) per user id in Application Support (not UserDefaults).
- UI shows `confirmedBalance` (server) + `pendingCoins` (estimated, labelled
  pending). Spending uses confirmed balance only.
- Flush: on app foreground, after sign-in, after game over (off the render path),
  exponential backoff. Terminal errors drop the event and log analytics.
- Account switch: outbox is keyed by user id; never replayed under another uid.
- No user yet: events earned before the device's **first** account are kept in
  an `unattributed` outbox and adopted by that account; once any account has
  existed, user-less events are dropped (never credited to someone else).
- Expiry: 7 days, except once-per-account sources (achievement, challenge,
  starter item), which never expire.
- Unreadable outbox file: never overwritten (re-opened later); undecodable
  entries are skipped individually; a non-JSON file is moved aside.
- Seasons: seasonal progression resets when a new season starts
  (`PlayerProfile.applySeasonRollover`, forward-only, profile key
  `season_progress_number`); server season premium = verified SSV ads this season.
- Profile merge never uses `max(local.coins, cloud.coins)` when flag ON, and
  takes claim markers (achievements, challenges, season claimed tiers) from the
  cloud copy so a guest's markers never suppress the account's own claims.

## Config JSON keys (economy_configs.config)

`daily_rewards[7]`, `wheel_rewards[8]`, `quest_rewards{easy,medium,hard}`,
`score_coin_divisor`, `minimum_game_coins`, `combo_bonus` table, `mode_bonus`,
`gameplay_daily_cap`, `progress_daily_cap`, `home_rewarded_coins`, `season_ads_required`,
`season_coin_cycle[]`, `achievement_rewards{id:coins}`,
`challenge_rewards{id:{coins,item}}`, `starter_items[]`,
`season_calendar{anchor,length_months,id_format,tiers,max_tiers_per_day,grace_hours}`
(replaced `active_season`; see SUPABASE_ECONOMY_BACKEND.md "Season calendar").
Swift `EconomyConfig.balancedPremiumRC1` must match the seeded JSON; a unit test
and a pgTAP test pin the shared numbers.
