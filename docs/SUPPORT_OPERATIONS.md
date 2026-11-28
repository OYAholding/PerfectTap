# PerfectTap — internal support & operations (1.2.0)

No admin app. Support runs through owner-only Postgres functions
(`supabase/migrations/20261127120000_support_operations.sql`) and one
protected CLI (`scripts/support/pt-support.sh`).

## Security model

- Functions live in `private`, `SECURITY DEFINER`, empty `search_path`.
- Executable **only** by the database owner (connection string). Not by
  `anon`, `authenticated` or `service_role`: a leaked Edge Function key cannot
  adjust balances or read support data (pgTAP `support_operations.test.sql`).
- Every write needs operator + ticket + reason (≥10 chars), is idempotent per
  ticket, goes through the ledger (`apply_economy_delta`: never below zero,
  `coin_debt` untouched) and writes one row to the append-only
  `private.support_actions` (UPDATE/DELETE blocked by trigger).
- The CLI refuses Corelim connection strings, prints the target without the
  password, runs reads inside `READ ONLY` transactions, binds every argument
  as a psql variable (no SQL injection) and requires `PT_CONFIRM=yes` for
  writes.

```bash
export PT_SUPPORT_DB_URL='postgresql://…'   # owner only; never commit or paste in chat
export PT_SUPPORT_OPERATOR='oya'
```

## Workflows

| Need | Command | Notes |
|---|---|---|
| Find a player | `pt-support.sh find <uid|username|friend code|email>` | |
| Inspect everything for a player | `pt-support.sh user <uid> [ledger_limit]` | economy row, legacy review, purchases, today's grants, recent ledger, past support actions |
| Missing purchase | `pt-support.sh purchase <transaction_id or original_transaction_id>` | Ledger + ASSN notifications + credits. No ledger row → ask the player to *Restore Purchases* while signed in. Owned by another user → shared Apple ID / account switch; do not move without evidence |
| Legacy balance queue | `pt-support.sh legacy-queue [limit]` | `pending` / `review` / `rejected` (JIT-only claims arrive as `review`) |
| Resolve a legacy balance | `PT_CONFIRM=yes pt-support.sh legacy-resolve <uid> <balance> <ticket> "<reason>"` | Balance capped at what the player had (max of legacy candidate / balance); sets `accepted`; owned items untouched |
| Disputed balance / goodwill | `PT_CONFIRM=yes pt-support.sh adjust <uid> <±delta> <ticket> "<reason>"` | ±50,000 max, never below zero, requires an accepted legacy status, one adjustment per ticket |
| Refund abuse monitor | `pt-support.sh refund-watch [days]` | players with refunds in the window, coin refunds, purchases, balance |
| Economy abuse monitor | `pt-support.sh economy-watch [days] [limit]` | top earners, capped amounts, days at cap |
| Emergency containment | `PT_CONFIRM=yes pt-support.sh contain economy|purchases <ticket> "<reason>"` | Runs `supabase/rollback/*containment.sql` and logs it. Preserves every ledger row |

Suggested review cadence after activation: `refund-watch 7` and
`economy-watch 1 50` daily for 14 days, then weekly (runbook §14).

## Refund policy (RC, owner-approved for testing 2026-11-27)

Refunded coin packs deduct the available balance down to zero; spent coins
are not clawed back and `coin_debt` stays disabled. Repeat refunders show up
in `refund-watch`; any action beyond that is a manual owner decision.

## Verified locally

pgTAP 27/27 (`support_operations.test.sql`) and CLI smoke test against the
local stack (find, user, adjust with/without `PT_CONFIRM`, injection string
returns 0 rows, containment drill logged).
