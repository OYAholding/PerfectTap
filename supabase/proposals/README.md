# supabase/proposals — NOT migrations

Files in this folder are **proposals for review**. The Supabase CLI never applies
them (`supabase db reset` / `db push` only read `supabase/migrations/`).

> **Never deploy anything from this folder, and never deploy from
> `feature/cosmetic-d-shop`.** Do not run these files against the cloud project.

## 2026112800_cosmetic_studio_catalog.sql

Server side of the Cosmetic Studio economy (docs/cosmetics/OWNERSHIP_AND_ECONOMY.md).

| Part | Change | State after applying |
|---|---|---|
| 1 | `private.economy_shop_items` primary key `(item_id)` → `(config_version, item_id)` | needed so a new config version can list the existing ids as well |
| 2 | config `cosmetic-studio-rc1` = copy of `balanced-premium-rc1` config | **inactive** |
| 3 | copies the 23 `balanced-premium-rc1` rows + 27 cosmetic items into the new version | **disabled** |
| 4 | `private.economy_bundles` (bundle_id, config_version, item_ids text[], price, enabled), RLS on, no policies, no client grants; 3 bundles | **disabled** |
| 5 | `private.purchase_economy_bundle(p_user, p_event_key, p_bundle_id)` + `private.purchase_economy_bundle_for_caller` + invoker `public.purchase_economy_bundle(p_event_key, p_bundle_id)` | callable, but fails `economy_disabled` until a config is activated |

It never touches the active config, `balanced-premium-rc1`'s config or rows, or any
existing function. `purchase_economy_item` works unchanged for single cosmetic
items once the new version is active (its lookup already filters by
`config_version`). `server_owned_items(cfg)` automatically protects cosmetic ids
(they are shop items of the active config).

Bundle function, following `purchase_economy_item`:
`require_active_economy` → `check_rate('economy_shop_purchase', 30/min)` → bundle
must be enabled in the active config and every component must be an enabled shop
item of the same config → `profile_data` row lock (`for update`) →
`already_owned` when nothing is missing → **one** `apply_economy_delta` with
`-round(price × missing_list_value / total_list_value)` clamped to
`[1, missing_list_value]` → `set_profile_item` for each missing item. A reused /
replayed `p_event_key` returns `duplicate` and grants nothing.

### Test status (exact)

Tested on 2026-11-27 in a **throwaway, isolated Docker container**
(`public.ecr.aws/supabase/postgres:17.11.0.018`, own port, removed afterwards). The
shared local stack (`supabase_db_perfecttap`) was **not** reset or modified, and
nothing was run against the cloud project.

1. Applied all 11 files of `supabase/migrations/` in order: OK.
   (The bare image ships the old `auth.uid()` that reads `request.jwt.claim.sub`;
   it was replaced in that container by the GoTrue form that also reads
   `request.jwt.claims`, which is what the CLI stack provides.)
2. `tests/database/economy_ledger.test.sql` before the proposal: 20/20.
3. Applied this proposal: OK.
4. `2026112800_cosmetic_studio_catalog.test.sql`: **26/26 ok**.
5. All existing suites again with the proposal applied: economy_ledger 20/20,
   economy_sources 122/122, perfecttap 70/70, purchase_ledger 42/42,
   sales_gate 30/30, season_calendar 35/35.

Not tested: `20261127110000_economy_hardening.sql` (it exists only in the
release worktree and was not available here), the cloud project, real PostgREST
calls from the app.

### Required before this can become a migration

- **Review by the economy (release/1.2.0) session.**
- **Merge with `20261127110000_economy_hardening.sql`.** That migration may change
  `economy_shop_items`, `purchase_economy_item`, rate limits or event-key handling;
  this proposal must be rebased onto it (and its pgTAP updated) rather than applied
  next to it.
- Decide whether the primary-key change (part 1) is acceptable, or whether the
  economy session prefers another way to version the catalog.
- Owner approval of prices (docs/cosmetics/SHOP_CATALOG_PROPOSAL.md) and of
  activating `cosmetic-studio-rc1` instead of `balanced-premium-rc1`.
- Client follow-up (not in this branch): an `EconomyConfig` entry with the
  authoritative cosmetic prices, `EconomyRemote.purchaseBundle`, and removing the
  "Preview only" gate in `EconomyManager.cosmeticPurchasesAvailable` for configs
  that carry cosmetics.

### Observation for the economy session (not verified by a test)

In the existing `private.purchase_economy_item`, `set_profile_item` runs even when
`apply_economy_delta` returns `duplicate` (a reused event key charges nothing). A
client that replays an *old* event key with a *different* item id would appear to
receive that item without being charged. The bundle function here explicitly
grants nothing on `duplicate`. Worth checking against the hardening migration.
