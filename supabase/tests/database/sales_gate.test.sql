-- pgTAP: StoreKit server sales gate + containment scripts. Run: supabase test db --local
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(30);

insert into auth.users (id, email, aud, role) values
  ('dddddddd-0000-0000-0000-000000000001', 'gate@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_anon() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"anon"}', true);
  select set_config('role', 'anon', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;

-- ---------- defaults ----------
select pg_temp.as_admin();
select ok((select rowsecurity from pg_tables where schemaname = 'private' and tablename = 'iap_sales_control'),
  'RLS on iap_sales_control');
select is((select array_agg(environment order by environment) from private.iap_sales_control),
  array['Production','Sandbox'], 'one row per environment');
select ok((select bool_and(not sales_enabled) from private.iap_sales_control), 'both environments start closed');
select throws_ok($$ insert into private.iap_sales_control (environment) values ('Xcode') $$, '23514', null,
  'only Sandbox / Production rows');

-- ---------- grants ----------
select ok(not has_function_privilege('anon', 'public.get_iap_sales_status()', 'EXECUTE'), 'anon cannot execute');
select ok(has_function_privilege('authenticated', 'public.get_iap_sales_status()', 'EXECUTE'), 'authenticated can execute');
select ok(not has_table_privilege('authenticated', 'private.iap_sales_control', 'SELECT')
  and not has_table_privilege('authenticated', 'private.iap_sales_control', 'UPDATE')
  and not has_table_privilege('anon', 'private.iap_sales_control', 'SELECT'), 'no client table grants');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'no client-callable SECURITY DEFINER function in public');

select pg_temp.as_anon();
select throws_ok($$ select public.get_iap_sales_status() $$, '42501', null, 'anon call refused');
select pg_temp.as_user('dddddddd-0000-0000-0000-000000000001');
select throws_ok($$ update private.iap_sales_control set sales_enabled = true $$, '42501', null,
  'a player cannot open sales');

-- ---------- exact shape ----------
select is(public.get_iap_sales_status(),
  '{"schemaVersion":1,"sandbox":{"salesEnabled":false},"production":{"salesEnabled":false},"enabledProducts":[]}'::jsonb,
  'default response: closed, no products');
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_iap_sales_status()) k),
  array['enabledProducts','production','sandbox','schemaVersion'], 'exactly four top-level keys');

select pg_temp.as_admin();
update private.iap_sales_control set sales_enabled = true, updated_by = 'pgtap' where environment = 'Sandbox';
update private.iap_products set enabled = true
where product_id in ('com.perfecttap.removeads', 'com.perfecttap.coins.500');
select pg_temp.as_user('dddddddd-0000-0000-0000-000000000001');
select is(public.get_iap_sales_status(),
  '{"schemaVersion":1,"sandbox":{"salesEnabled":true},"production":{"salesEnabled":false},"enabledProducts":["com.perfecttap.coins.500","com.perfecttap.removeads"]}'::jsonb,
  'Sandbox open, sorted enabled products');
select is(jsonb_typeof(public.get_iap_sales_status()->'sandbox'->'salesEnabled'), 'boolean', 'salesEnabled is a JSON boolean');
select is(jsonb_typeof(public.get_iap_sales_status()->'schemaVersion'), 'number', 'schemaVersion is a JSON number');

select pg_temp.as_admin();
update private.iap_products set enabled = false where product_id = 'com.perfecttap.coins.500';
select is(public.get_iap_sales_status()->'enabledProducts', '["com.perfecttap.removeads"]'::jsonb,
  'disabling a product removes it from enabledProducts');
select ok((select updated_by = 'pgtap' from private.iap_sales_control where environment = 'Sandbox'), 'updated_by recorded');

delete from private.iap_sales_control where environment = 'Production';
select is(public.get_iap_sales_status()->'production', '{"salesEnabled":false}'::jsonb, 'missing row reads as closed');
insert into private.iap_sales_control (environment) values ('Production');

-- ---------- closed sales never refuse paid transactions ----------
update private.iap_sales_control set sales_enabled = false;
select ok((select bool_and(not sales_enabled) from private.iap_sales_control), 'kill switch closes both environments');
select pg_temp.as_user('dddddddd-0000-0000-0000-000000000001');
select save_profile('{"username":"gate_one"}'::jsonb);
select pg_temp.as_admin();
select is(public.record_verified_purchase('dddddddd-0000-0000-0000-000000000001', 'tg-1', 'tg-1',
  'com.perfecttap.removeads', 'Production', now()), 'granted', 'paid transaction granted while sales are closed');
update private.iap_products set enabled = false;
select is(public.record_verified_purchase('dddddddd-0000-0000-0000-000000000001', 'tg-1', 'tg-1',
  'com.perfecttap.removeads', 'Production', now()), 'already_granted',
  'redelivery still answers while sales and the product are closed');

-- ---------- purchase containment (rollback/20261122120000) effects ----------
update private.iap_sales_control set sales_enabled = true;
update private.iap_products set enabled = true;
-- statements of supabase/rollback/20261122120000_purchase_containment.sql (without begin/commit)
do $$
begin
  if to_regclass('private.iap_sales_control') is not null then
    update private.iap_sales_control
    set sales_enabled = false, updated_by = 'containment', note = 'purchase_containment';
  end if;
end $$;
update private.iap_products set enabled = false;
revoke execute on function public.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz)
  from service_role;
revoke execute on function public.revoke_purchase(text, timestamptz, text, text, text, uuid)
  from service_role;
revoke execute on function public.process_app_store_notification(text, text, text, timestamptz, text, text, text, text, uuid, timestamptz)
  from service_role;
insert into private.economy_events (user_id, kind, detail)
values (null, 'purchase_backend_contained', jsonb_build_object('at', now()));

select is(public.get_iap_sales_status(),
  '{"schemaVersion":1,"sandbox":{"salesEnabled":false},"production":{"salesEnabled":false},"enabledProducts":[]}'::jsonb,
  'purchase containment closes sales and empties enabledProducts');
select ok(not has_function_privilege('service_role',
  'public.record_verified_purchase(uuid,text,text,text,text,timestamptz,timestamptz)', 'EXECUTE'),
  'purchase containment revokes purchase recording');

-- ---------- economy containment (rollback/20261125200000) effects ----------
update private.economy_configs set active = true, approved_by = 'pgtap', approved_at = now()
where version = 'balanced-premium-rc1';
update private.economy_shop_items set enabled = true;
-- statements of supabase/rollback/20261125200000_economy_containment.sql (without begin/commit)
update private.economy_configs set active = false where active;
update private.economy_shop_items set enabled = false where enabled;
revoke execute on function public.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint)
  from service_role;
revoke execute on function public.submit_economy_event(uuid, text, jsonb)
  from authenticated;
revoke execute on function private.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint)
  from service_role;
revoke execute on function private.submit_economy_event(uuid, text, jsonb)
  from authenticated;
insert into private.economy_events (user_id, kind, detail)
values (null, 'economy_backend_contained', jsonb_build_object('at', now()));

select ok(not exists (select 1 from private.economy_configs where active), 'economy containment: no active config');
select ok(not exists (select 1 from private.economy_shop_items where enabled), 'economy containment: shop disabled');
select ok(not has_function_privilege('service_role', 'public.record_verified_rewarded_claim(uuid,uuid,text,text,uuid,smallint)', 'EXECUTE')
  and not has_function_privilege('service_role', 'private.record_verified_rewarded_claim(uuid,uuid,text,text,uuid,smallint)', 'EXECUTE'),
  'economy containment: rewarded-ad grants revoked');
select ok(not has_function_privilege('authenticated', 'public.submit_economy_event(uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.submit_economy_event(uuid,text,jsonb)', 'EXECUTE'),
  'economy containment: client economy events revoked');
select is((select count(*)::int from private.economy_events
  where kind in ('purchase_backend_contained', 'economy_backend_contained') and user_id is null), 2,
  'containment leaves audit rows');
select pg_temp.as_user('dddddddd-0000-0000-0000-000000000001');
select throws_ok($$ select public.submit_economy_event(gen_random_uuid(), 'wheel', '{}'::jsonb) $$, '42501', null,
  'contained: submit_economy_event refused');
select throws_ok($$ select public.claim_daily_economy_reward(gen_random_uuid()) $$, 'P0001', 'economy_disabled',
  'contained: remaining economy RPCs fail economy_disabled');

select * from finish();
rollback;
