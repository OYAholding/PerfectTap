# PerfectTap 1.2.0 — staging strategy & production deployment plan

Status 2026-11-27: **nothing deployed**. Production (`pgvtaotdyspwnpqtxpju`,
org OYA Games, eu-central-1) is at `20261114120000`; 7 migrations pending
(`supabase migration list --linked`, read-only).

## 1. Staging decision (lowest cost, safe)

| Option | Cost | Status |
|---|---|---|
| 1. Local Supabase (Docker) for automated verification | free | **In use.** Full `db reset` of all 13 migrations + 8 pgTAP suites (374 tests) + Edge Functions served locally (`supabase functions serve`) and probed: `admob-ssv` → `invalid_signature`, `verify-purchase` → 401 without JWT, `app-store-notifications` → `verification_not_configured` without Apple secrets (fail closed) |
| 2. Separate free-tier Supabase project | free if a slot exists | **Not available today.** The free tier allows 2 active free projects counted across every org you own/admin; your account already has 3 active projects (Corelim, Corelim Test, PerfectTap). A free slot requires pausing a project — not done (Corelim is out of scope) |
| 3. Extra project in the paid org | ≈ $10/month compute (billed hourly; can be deleted after the rehearsal for a few dollars) | **Needs owner approval** (paid resource). Recommended only for one rehearsal with a restored production backup before G7 |

Recommendation: keep option 1 as the automated gate (it ran on every change
in this session). For the production migration, either approve option 3 for a
one-off rehearsal (restore yesterday's backup into it, run the migrations,
reconcile dry-run, delete it), or accept the local rehearsal + verified
production backup + containment scripts as the safety net. Production is never
used as an experimental staging environment.

## 2. What deploys (in this order)

| Step | Command (owner-gated) | What |
|---|---|---|
| D0 | Dashboard backup / PITR timestamp + `pg_dump` (schema + public/private/legacy) stored encrypted outside git | backup |
| D1 | `./scripts/deploy-supabase.sh` | dry run: CLI version, target guard (`verify_perfecttap_target`), plan |
| D2 | `./scripts/deploy-supabase.sh --apply` | `db push` of the 7 migrations: purchase ledger + guard, authoritative ledger, economy sources, sales gate, season calendar, **economy hardening**, **support operations**; Firebase secrets; claim/delete functions; auth config |
| D3 | read-only checks | `select count(*) from private.economy_configs where active` → 0; `… iap_products where enabled` → 0; `select * from public.get_iap_sales_status()` → both `salesEnabled:false`; live 1.1.x smoke (sign-in, save, leaderboard, duel) |
| D4 | `select * from private.reconcile_legacy_economy(true)` | **dry run only**; share the distribution with the owner |
| D5 | `PT_CONFIRM_PRODUCTION=yes APPLE_ROOT_CAS_B64=… APPLE_APP_APPLE_ID=6760975737 ./scripts/deploy-supabase.sh --apply-purchases` | `verify-purchase`, `app-store-notifications`, `admob-ssv` |
| D6 | ASC: ASSN V2 URL (Production + Sandbox) → `…/functions/v1/app-store-notifications`; *Request a Test Notification* | ASSN |
| D7 | AdMob console: SSV URL → `…/functions/v1/admob-ssv` per rewarded unit; verify-URL test returns `verified_no_claim` | SSV |

### Secrets (Supabase → Edge Functions → Secrets; never in git)

| Secret | Used by | Notes |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY` | all | provided by the platform |
| `FIREBASE_PROJECT_ID`, `FIREBASE_WEB_API_KEY`, `FIREBASE_IOS_BUNDLE_ID`, `FIREBASE_JWKS_URL`, `FIREBASE_IDENTITY_URL`, `FIRESTORE_URL` | claim-legacy-account | already deployed (v2) |
| `APPLE_APP_APPLE_ID` (`6760975737`), `APPLE_ROOT_CAS_B64`, `APPLE_ENABLED_ENVIRONMENTS` (`Production,Sandbox`) | verify-purchase, app-store-notifications | Sandbox needed for TestFlight + App Review |
| `ADMOB_ALLOWED_AD_UNITS` | admob-ssv | comma list of the app's rewarded unit ids (recommended) |

## 3. Rollback & containment

- No down-migrations. Containment preserves every ledger row:
  `pt-support.sh contain purchases|economy <ticket> "<reason>"`
  (`supabase/rollback/20261122120000_purchase_containment.sql`,
  `supabase/rollback/20261125200000_economy_containment.sql`). Both were
  drilled on the local stack.
- Per-product stop: `update private.iap_products set enabled = false where product_id = …`.
- Per-environment stop: `update private.iap_sales_control set sales_enabled = false where environment = …`.
- Full restore from PITR only by owner decision.

## 4. Activation prerequisites that are NOT part of 1.2.0 deploy

Activating the authoritative economy (`economy_configs.active`, then
`PT_AUTHORITATIVE_ECONOMY_ENABLED` in a later build) additionally requires:
1. owner approval of Model B values (RC values recorded in
   `docs/PRODUCT_DECISIONS_1.2.0_RC.md`);
2. reconcile applied for `accepted` accounts and the `review` queue worked
   (`pt-support.sh legacy-queue`);
3. a forced minimum app version (1.1.x cannot earn once a config is active —
   security review M4);
4. new Firebase sign-ups disabled (security review C2).
