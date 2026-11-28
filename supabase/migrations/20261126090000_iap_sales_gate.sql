-- ============================================================================
-- 1.2.0 — server sales gate for StoreKit (docs/MONETIZATION_ACTIVATION_STRATEGY.md §4)
-- ============================================================================
-- Additive. Per-environment switch telling clients whether they may START a
-- sale. Both rows are seeded closed. Separate from iap_products.enabled
-- ("the server will grant this product"): record_verified_purchase never reads
-- this table, so closing sales never refuses an already-paid transaction.
-- Kill switch: update private.iap_sales_control set sales_enabled = false;
-- ============================================================================

create table private.iap_sales_control (
  environment   text primary key check (environment in ('Sandbox', 'Production')),
  sales_enabled boolean not null default false,
  updated_at    timestamptz not null default now(),
  updated_by    text,
  note          text
);
alter table private.iap_sales_control enable row level security;
revoke all on table private.iap_sales_control from public, anon, authenticated;

insert into private.iap_sales_control (environment) values ('Sandbox'), ('Production')
on conflict (environment) do nothing;

create trigger iap_sales_control_updated_at before update on private.iap_sales_control
  for each row execute function private.set_updated_at();

-- Exact shape is a contract with ServerSalesStatus.decode (FeatureFlags.swift):
-- any deviation closes sales on the client. Missing row ⇒ false.
create or replace function private.get_iap_sales_status()
returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schemaVersion', 1,
    'sandbox', jsonb_build_object('salesEnabled', coalesce(
      (select sales_enabled from private.iap_sales_control where environment = 'Sandbox'), false)),
    'production', jsonb_build_object('salesEnabled', coalesce(
      (select sales_enabled from private.iap_sales_control where environment = 'Production'), false)),
    'enabledProducts', coalesce(
      (select jsonb_agg(product_id order by product_id) from private.iap_products where enabled),
      '[]'::jsonb))
$$;
revoke all on function private.get_iap_sales_status() from public, anon;

create or replace function public.get_iap_sales_status()
returns jsonb
language sql stable security invoker set search_path = '' as $$
  select private.get_iap_sales_status()
$$;
revoke all on function public.get_iap_sales_status() from public, anon;
grant execute on function private.get_iap_sales_status(), public.get_iap_sales_status()
  to authenticated;
