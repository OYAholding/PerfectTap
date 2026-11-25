# PerfectTap 1.2.0 — Monetization activation strategy (fail-closed)

Status: implemented on the client (`agent-c/storekit-asc`). The server signal in §4
is **specified, not deployed** (Supabase agent). Until it is deployed every binary,
including `Release-IAP`, keeps sales closed. No App Store Connect product has been
created; no real-money purchase has been enabled anywhere.

## 1. Problem

Up to 1.2.0 (6) the five `PT_IAP_*` keys and `PT_AUTHORITATIVE_ECONOMY_ENABLED` were
hard-coded `NO` in both Debug and Release. A production binary could therefore
never sell, and turning sales on meant shipping a new binary. App Review must be
able to buy (Sandbox) in the exact binary that is submitted, while App Store
customers (Production) must not be able to buy until the owner activates sales.

## 2. Two independent gates, both fail-closed

A **new** purchase starts only if all of these hold:

| # | Gate | Where | Default | Unknown / error |
|---|---|---|---|---|
| 1 | Build-time capability ceiling (`PT_IAP_*`) | xcconfig → Info.plist | OFF in `Debug` and `Release` | missing / malformed key ⇒ OFF |
| 2 | Server sales switch for the StoreKit environment (`sandbox` / `production`) | `public.get_iap_sales_status()` | both `false` | unreachable, RPC missing, undecodable, older than 10 min ⇒ closed |
| 3 | Product enabled on the server (`private.iap_products.enabled`) | same RPC (`enabledProducts`) | `false` | ⇒ closed |
| 4 | Account rules | client policy | — | coins need a permanent account (Sign in with Apple preferred); every purchase needs a Supabase UUID (`appAccountToken`) |

Gates never apply to **delivery**: `Transaction.updates` (attached at launch),
`Transaction.unfinished`, launch reconciliation and **Restore Purchases** always
run, so a player who already paid is never stranded by the kill switch, an
outage or a ceiling-OFF build. Restoring Remove Forced Ads and skins needs no
account and no server.

### StoreKit environment

`StoreEnvironmentResolver` reads Apple's signed `AppTransaction.environment`
(iOS 16+): `.sandbox` for TestFlight and App Review, `.production` for App Store
downloads, `.xcode` for the local `.storekit` file. If it cannot be determined
the client uses the **Production** switch (the stricter one before launch).

## 3. Build configurations (ceilings)

| Configuration | xcconfig | Ceiling | Verification | Use |
|---|---|---|---|---|
| `Debug` | `Config/Monetization.Off.xcconfig` | all OFF | — | day-to-day development, unit tests (they assert OFF) |
| `Debug-StoreKit` | `Config/Monetization.LocalStoreKit.xcconfig` | catalog + 3 categories ON, `PT_IAP_LOCAL_STOREKIT_TESTING=YES` | on-device JWS only | scheme `PerfectTap-StoreKit`: fake-money purchases against `StoreKit/PerfectTap.storekit`. Works **only** in the Xcode environment; the flag is compiled out of non-DEBUG builds |
| `Release` | `Config/Monetization.Off.xcconfig` | all OFF | — | default App Store archive (`fastlane build`) — today's shipping behaviour |
| `Release-IAP` | `Config/Monetization.AppStoreIAP.xcconfig` | catalog + server verification + 3 categories ON | `verify-purchase` Edge Function before `finish()` | the binary submitted with the IAPs. Sells only where the server opens sales. `fastlane build configuration:Release-IAP` requires `PT_CONFIRM_IAP_CEILING=yes` and checks the IPA's `PT_MONETIZATION_PROFILE` |

`PT_AUTHORITATIVE_ECONOMY_ENABLED` stays `NO` in every xcconfig. Its runtime gate
already exists (an active `economy_configs` row, otherwise `economy_disabled`).
It may be raised in `Release-IAP` only after the owner approves Model B **and** the
iOS economy client falls back to the legacy path on `economy_disabled`.

The PT_* monetization keys must never be set in `project.yml` target settings
again: target settings override xcconfig values.

## 4. Server signal (handoff to the Supabase agent)

Required objects (names are a contract with `ServerSalesStatus.decode`):

```sql
-- Per-environment sales switch. Both rows start closed.
create table private.iap_sales_control (
  environment   text primary key check (environment in ('Sandbox', 'Production')),
  sales_enabled boolean not null default false,
  updated_at    timestamptz not null default now(),
  updated_by    text,
  note          text
);
alter table private.iap_sales_control enable row level security;  -- no client grants
insert into private.iap_sales_control (environment) values ('Sandbox'), ('Production');

-- private.get_iap_sales_status(): security definer, stable, search_path = ''
-- public.get_iap_sales_status(): security invoker wrapper,
--   grant execute to authenticated only (guests are anonymous Supabase users,
--   i.e. role authenticated); revoke from public, anon.
```

Response (exact shape; any deviation closes sales on the client):

```json
{
  "schemaVersion": 1,
  "sandbox":    { "salesEnabled": false },
  "production": { "salesEnabled": false },
  "enabledProducts": ["com.perfecttap.removeads", "..."]
}
```

- `salesEnabled` = `iap_sales_control.sales_enabled` for that environment
  (missing row ⇒ `false`).
- `enabledProducts` = `product_id`s of `private.iap_products where enabled`
  (sorted, `[]` when none).
- Semantics stay separate: `iap_products.enabled` = "the server will **grant**
  this product" (needed for Sandbox review too); `sales_enabled` = "clients may
  **start** a sale in this environment". Closing `sales_enabled` must not make
  `record_verified_purchase` refuse already-paid transactions.
- pgTAP: default rows closed; anon cannot execute; authenticated gets the exact
  shape; disabling a product removes it from `enabledProducts`.
- Kill switch / containment: `update private.iap_sales_control set sales_enabled = false;`
  (add it to `supabase/rollback/…purchase_containment.sql`). Clients pick it up on
  the next refresh: launch, foreground, before every purchase, max 10 min cache.

## 5. Per-environment activation runbook

| Step | Sandbox (TestFlight / App Review) | Production (App Store) |
|---|---|---|
| 0 | Paid Apps Agreement, tax, banking active in ASC | same |
| 1 | `bundle exec fastlane iap_reconcile` (dry run) is clean except creations | — |
| 2 | Owner approval → `PT_CONFIRM=yes bundle exec fastlane iap_reconcile confirm_create:true` (creates the 9 products, localization, USD price, availability, screenshot, review note; read-back verified) | — |
| 3 | Deploy migration + Edge Functions (Supabase agent, with `PT_CONFIRM_PRODUCTION=yes`), Apple root CAs, App Apple ID; `iap_products.enabled = true` for the products under review | — |
| 4 | `update private.iap_sales_control set sales_enabled = true where environment = 'Sandbox';` | stays `false` |
| 5 | `PT_CONFIRM_IAP_CEILING=yes PT_CONFIRM=yes bundle exec fastlane beta configuration:Release-IAP` → internal TestFlight; run `docs/STOREKIT_DEVICE_SANDBOX_QA.he.md` | App Store customers on this binary see no store (Production closed) |
| 6 | Submit the same build with the IAPs attached to the version (first IAPs must be selected on the version page in ASC) | — |
| 7 | — | After approval and owner go-ahead: `update private.iap_sales_control set sales_enabled = true where environment = 'Production';` |
| Rollback | `sales_enabled = false` (environment-specific), or `iap_products.enabled = false` per product. Paid transactions keep being delivered/restored. | same |

Notes:
- App Review runs the submitted binary in Sandbox, so step 4 must be on for the
  whole review. Keeping Production closed during review is what lets the owner
  release the version before selling.
- A `Release` (ceiling OFF) binary never sells even if both switches are on.
- `Debug-StoreKit` never touches the live server for sales (Xcode environment).

## 6. Client behaviour summary (StoreKit 2)

- Only `.verified` JWS results are processed; unverified ones are left untouched.
- Checks before anything else: `appBundleID == Bundle.main.bundleIdentifier`,
  product ID in the bundled catalog, StoreKit product type matches the catalog
  kind. Failures are never granted and never finished.
- Consumables: `appAccountToken` must equal the signed-in Supabase UUID; otherwise
  the transaction is kept unfinished for the account that paid (no retry loop,
  re-tried on every UID change). They are credited only after the server
  acknowledges, and finished only then (survives app kill / server outage).
- Non-consumables: granted from Apple's signed history even while the server is
  unreachable (restore never blocked), kept unfinished until the server
  acknowledges; a definitive server rejection removes the provisional grant.
- Ledger: exactly-once per transaction ID; refunds (`revocationDate`) debit/revoke
  without the server; refund reversal (same transaction re-signed later without
  `revocationDate`) reinstates once; stale copies are ignored by `signedDate`.
- Restore / launch reconcile re-apply owned non-consumables to whichever profile is
  signed in (guests included); coins are never re-applied.
- Ask to Buy / pending: no grant until the approved transaction arrives through
  `Transaction.updates` with the same token. Cancellation grants nothing.
