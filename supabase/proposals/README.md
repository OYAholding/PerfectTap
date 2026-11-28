# supabase/proposals — NOT migrations

Files in this folder are **proposals for review**. The Supabase CLI never applies
them (`supabase db reset` / `db push` only read `supabase/migrations/`).

> **Never deploy anything from this folder, and never deploy from a cosmetic
> branch.** Do not run these files against the cloud project.

## 2026112800_cosmetic_studio_catalog.sql

Server side of the Cosmetic Studio economy (docs/cosmetics/OWNERSHIP_AND_ECONOMY.md),
target 1.2.1. **Rebased onto the release/1.2.0 migration set**, including
`20261127110000_economy_hardening.sql` and `20261127120000_support_operations.sql`.

| Part | Change | State after applying |
|---|---|---|
| 1 | `private.economy_shop_items` primary key `(item_id)` → `(config_version, item_id)`; helper `private.is_cosmetic_item_id(text)` | needed so a config can list ids that another config also lists (F1 registration, new catalog version) |
| 2 | config `cosmetic-studio-rc1` = copy of `balanced-premium-rc1` config + `cosmetic_studio: true` | **inactive** |
| 3 | copies the 23 `balanced-premium-rc1` rows + 27 cosmetic items into the new version | **disabled** |
| 4 | **F1:** the 27 cosmetic ids registered under every other config (today `balanced-premium-rc1`), and by trigger `economy_configs_register_cosmetic_ids` under every config created later; guard trigger `economy_shop_items_cosmetic_guard` keeps cosmetic rows disabled unless the config has `cosmetic_studio: true`; `private.strip_unpaid_cosmetic_items(p_dry_run default true)` (service role only) | **disabled**; cleanup is manual |
| 5 | `private.economy_bundles` (bundle_id, config_version, item_ids text[], price, enabled), RLS on, no policies, no client grants; 3 bundles | **disabled** |
| 6 | `private.purchase_economy_bundle(p_user, p_event_key, p_bundle_id)` + `private.purchase_economy_bundle_for_caller` + invoker `public.purchase_economy_bundle(p_event_key, p_bundle_id)` | callable, but fails `economy_disabled` until a config is activated |

It does not change the active config, `balanced-premium-rc1`'s config, or its existing 23 rows,
and it does not replace any existing function. It **adds** 27 disabled cosmetic rows to
`balanced-premium-rc1` (F1). The hardened `purchase_economy_item` works unchanged for
single cosmetic items once a cosmetic config is active, because its lookup filters by `config_version`.

### F1: why cosmetic ids are registered under every config

`server_owned_items(cfg)` returns every `economy_shop_items` row of `cfg` (enabled
or not), plus starter, challenge and season items. `sanitize_economy` (hardened) drops any
server-owned id that a client save adds, both while a config is active and during a containment
(the last approved config). Before this change the cosmetic ids existed only under the
inactive `cosmetic-studio-rc1`. With the 1.2.0 config (`balanced-premium-rc1`)
active, a client save could add `quack_attack.tapButton` to `owned_items`, and the id
would survive the later activation of the cosmetic config. The registered rows close
that. The guard trigger makes sure they are never sold under a non-cosmetic config, even by
`update private.economy_shop_items set enabled = true` (which the existing pgTAP suites run).

If an authoritative config was active **before** this proposal is applied, run
`select * from private.strip_unpaid_cosmetic_items(true)` (dry run), review, then
`(false)`. It removes cosmetic ids that no `shop_purchase` ledger entry paid for, and audits each removal as
`economy_events.kind = 'cosmetic_unpaid_stripped'`. Do not run it for legacy-economy
(pre-activation) purchases. Those are legitimate, the same as themes bought before activation.

### Bundle function (mirrors the hardened `purchase_economy_item`)

`require_active_economy` → `check_rate('economy_shop_purchase', 30/min)` → bundle
must be enabled in the active config, and every component must be an enabled shop
item of the same config → **lock `economy`, then `profile_data` (L1, F2)** →
**event-key check (F3):** the same key for the same bundle returns `duplicate` (no charge, no grant), any
other reuse (another bundle, a single-item key, a reward key) returns `invalid_payload`. This check runs
*before* the `already_owned` short-circuit. Then `already_owned` when nothing is missing →
**one** `apply_economy_delta` with `-round(price × missing_list_value / total_list_value)`
clamped to `[1, missing_list_value]` → `invalid_payload` unless the delta is `applied` →
`set_profile_item` for each missing item.

### Test status (exact)

Tested on 2026-11-28 in a **throwaway, isolated Docker container**
(`public.ecr.aws/supabase/postgres:17.11.0.018`, no published port, removed afterwards).
The shared local stack (`supabase_db_perfecttap`) was **not** touched, and nothing was run
against the cloud project. Migrations were read from `origin/release/1.2.0` @ `eb37310`.

Setup: `auth.uid()` / `auth.role()` replaced (as `supabase_admin`) with the CLI-stack
form that also reads `request.jwt.claims`. All migrations, the proposal and every test ran as
`postgres`, as the Supabase CLI does. Note: running them as `supabase_admin`, as earlier
runs did, makes every suite that does `set role postgres` fail with `permission denied`.
No test file was edited for the container.

1. All 13 files of release/1.2.0 `supabase/migrations/` applied in order: OK (incl.
   `20261127110000_economy_hardening.sql`, `20261127120000_support_operations.sql`).
2. Existing suites **before** the proposal: economy_hardening 31/31, economy_ledger 20/20,
   economy_sources 122/122, perfecttap 70/70, purchase_ledger 42/42, sales_gate 30/30,
   season_calendar 35/35, support_operations 27/27.
3. QA-01 regression `docs/cosmetics/qa/sql/purchase_item_duplicate_event_key.test.sql`: **10/10**
   (a replay with a different item raises `invalid_payload`, charges nothing, grants nothing).
4. Proposal applied: OK.
5. `2026112800_cosmetic_studio_catalog.test.sql`: **51/51**.
6. All existing suites **again with the proposal applied**: economy_hardening 31/31,
   economy_ledger 20/20, economy_sources 122/122, perfecttap 70/70, purchase_ledger 42/42,
   sales_gate 30/30, season_calendar 35/35, support_operations 27/27; QA-01 10/10.

Not tested: the cloud project, real PostgREST calls from the app, and concurrent sessions
(F2's lock order is asserted on the function source, not by a two-session deadlock test).

### Required before this can become a migration

- **Review by the economy (release/1.2.0) session**, including the F1–F3 resolution.
- Decide whether the primary-key change (part 1) is acceptable, or whether the
  economy session prefers another way to version the catalog. Without the PK change, F1
  could instead register the cosmetic ids only under the active config and activate cosmetics by
  enabling those rows; there would be no separate config version.
- Owner approval of prices (docs/cosmetics/SHOP_CATALOG_PROPOSAL.md) and of
  activating `cosmetic-studio-rc1` instead of `balanced-premium-rc1`.
- Order it after `20261127120000_support_operations.sql` (1.2.1 plan:
  docs/cosmetics/RELEASE_INTEGRATION_NOTES.md §5), and move the pgTAP into `supabase/tests/database/`.
- Client follow-up (not in this branch): an `EconomyConfig` entry with the
  authoritative cosmetic prices, `EconomyRemote.purchaseBundle`, and removing the
  "Preview only" gate in `EconomyManager.cosmeticPurchasesAvailable` for configs
  that carry cosmetics.
