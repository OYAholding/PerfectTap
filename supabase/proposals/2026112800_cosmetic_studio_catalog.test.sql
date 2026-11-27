-- pgTAP for the Cosmetic Studio PROPOSAL (2026112800_cosmetic_studio_catalog.sql).
-- Not part of supabase/tests/database until the proposal becomes a migration.
-- Run against a throwaway database that has every migration + the proposal applied.
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(26);

insert into auth.users (id, email, aud, role) values
  ('cccccccc-0000-0000-0000-000000000001', 'cosmetics@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;

-- Shape: inactive, disabled, existing config untouched ------------------------
select pg_temp.as_admin();
select ok(exists (select 1 from private.economy_configs where version = 'cosmetic-studio-rc1' and not active),
  'cosmetic-studio-rc1 exists and is inactive');
select ok((select bool_and(not active) from private.economy_configs), 'no config activated by the proposal');
select is((select count(*)::int from private.economy_shop_items where config_version = 'balanced-premium-rc1'), 23,
  'balanced-premium-rc1 catalog unchanged');
select is((select count(*)::int from private.economy_shop_items where config_version = 'cosmetic-studio-rc1'), 23 + 27,
  'new version carries the existing catalog plus 27 cosmetic items');
select ok((select bool_and(not enabled) from private.economy_shop_items where config_version = 'cosmetic-studio-rc1'),
  'every new catalog row is disabled');
select is((select count(*)::int from private.economy_bundles where not enabled), 3, 'three bundles, all disabled');
select ok((select bool_and(rowsecurity) from pg_tables where schemaname = 'private' and tablename = 'economy_bundles'),
  'RLS enabled on economy_bundles');
select is((select count(*)::int from pg_policies where schemaname = 'private' and tablename = 'economy_bundles'), 0,
  'no client policies on economy_bundles');
select ok(not has_table_privilege('authenticated', 'private.economy_bundles', 'SELECT'),
  'clients cannot read economy_bundles');
select ok(has_function_privilege('authenticated', 'public.purchase_economy_bundle(uuid,text)', 'EXECUTE'),
  'invoker wrapper callable by authenticated');
select ok(not has_function_privilege('authenticated', 'private.purchase_economy_bundle(uuid,uuid,text)', 'EXECUTE'),
  'core bundle function is not client callable');
select ok(not has_function_privilege('anon', 'public.purchase_economy_bundle(uuid,text)', 'EXECUTE'),
  'anon cannot buy bundles');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'no client-callable SECURITY DEFINER function in public');

-- Disabled economy fails closed ----------------------------------------------
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"cosmetic_1","coins":0}'::jsonb) $$, 'player profile created');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000001', 'bundle.quack_attack') $$,
  'P0001', 'economy_disabled', 'bundle purchase fails closed while no config is active');

-- Activate the candidate in this transaction only -----------------------------
select pg_temp.as_admin();
update private.economy_configs set active = true, approved_by = 'pgtap', approved_at = now()
where version = 'cosmetic-studio-rc1';
update private.economy_shop_items set enabled = true where config_version = 'cosmetic-studio-rc1';
update private.economy_bundles set enabled = true where bundle_id in ('bundle.quack_attack', 'bundle.purrfect_tap');
update private.economy set confirmed_balance = 5000, legacy_status = 'accepted'
where user_id = 'cccccccc-0000-0000-0000-000000000001';
update private.profile_data set data = jsonb_set(data, '{coins}', '5000'::jsonb)
where id = 'cccccccc-0000-0000-0000-000000000001';

select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is((purchase_economy_item('30000000-0000-0000-0000-000000000002', 'quack_attack.tapButton')->>'status'),
  'applied', 'single cosmetic item purchasable through the existing RPC');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 4000::bigint, 'item charged its catalog price');

-- 3750 × (5500 − 1000) / 5500 = 3068.18 → 3068
select is((purchase_economy_bundle('30000000-0000-0000-0000-000000000003', 'bundle.quack_attack')->>'charged')::bigint,
  3068::bigint, 'bundle completion is pro-rated by missing list value');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 932::bigint, 'charged exactly once');
select is((select count(*)::int from jsonb_array_elements_text(get_my_profile()->'owned_items') x
  where x like 'quack_attack.%'), 9, 'every Quack Attack item owned, none duplicated');
select is((purchase_economy_bundle('30000000-0000-0000-0000-000000000004', 'bundle.quack_attack')->>'status'),
  'already_owned', 'complete bundle returns already_owned');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 932::bigint, 'already_owned charges nothing');

select is((purchase_economy_bundle('30000000-0000-0000-0000-000000000003', 'bundle.purrfect_tap')->>'status'),
  'duplicate', 'reused event key is a duplicate');
select ok(not (get_my_profile()->'owned_items' ? 'purrfect_tap.tapButton'), 'duplicate key grants nothing');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000005', 'bundle.purrfect_tap') $$,
  'P0001', 'insufficient_coins', 'insufficient balance rejects the whole bundle');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000006', 'bundle.boom_mode') $$,
  'P0001', 'item_unavailable', 'disabled bundle is unavailable');

select * from finish();
rollback;
