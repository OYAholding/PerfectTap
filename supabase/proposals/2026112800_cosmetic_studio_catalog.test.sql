-- pgTAP for the Cosmetic Studio PROPOSAL (2026112800_cosmetic_studio_catalog.sql).
-- Not part of supabase/tests/database until the proposal becomes a migration.
-- Run against a throwaway database that has every release/1.2.0 migration
-- (incl. 20261127110000_economy_hardening.sql) + the proposal applied.
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(51);

insert into auth.users (id, email, aud, role) values
  ('cccccccc-0000-0000-0000-000000000001', 'cosmetics@test.local', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000002', 'cosmetics-f1@test.local', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000003', 'cosmetics-f1b@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.owned(uid uuid) returns jsonb language sql security definer as $$
  select coalesce(data->'owned_items', '[]'::jsonb) from private.profile_data where id = uid
$$;

-- Shape: inactive, disabled, existing config untouched ------------------------
select pg_temp.as_admin();
select ok(exists (select 1 from private.economy_configs where version = 'cosmetic-studio-rc1' and not active),
  'cosmetic-studio-rc1 exists and is inactive');
select ok((select bool_and(not active) from private.economy_configs), 'no config activated by the proposal');
select is((select count(*)::int from private.economy_shop_items
           where config_version = 'balanced-premium-rc1' and not private.is_cosmetic_item_id(item_id)), 23,
  'balanced-premium-rc1 non-cosmetic catalog unchanged');
select is((select count(*)::int from private.economy_shop_items
           where config_version = 'balanced-premium-rc1' and private.is_cosmetic_item_id(item_id) and not enabled), 27,
  'F1: the 27 cosmetic ids are registered, disabled, under balanced-premium-rc1');
select is((select count(*)::int from private.economy_shop_items where config_version = 'cosmetic-studio-rc1'), 23 + 27,
  'new version carries the existing catalog plus 27 cosmetic items');
select ok((select bool_and(not enabled) from private.economy_shop_items where config_version = 'cosmetic-studio-rc1'),
  'every new catalog row is disabled');
select ok((select private.server_owned_items(c) @> array(select item_id from private.economy_shop_items
             where config_version = 'cosmetic-studio-rc1' and private.is_cosmetic_item_id(item_id))
           from private.economy_configs c where c.version = 'balanced-premium-rc1'),
  'F1: server_owned_items(balanced-premium-rc1) protects every cosmetic id');
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
select ok(not has_function_privilege('authenticated', 'private.strip_unpaid_cosmetic_items(boolean)', 'EXECUTE'),
  'cleanup function is not client callable');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'no client-callable SECURITY DEFINER function in public');
select ok((select strpos(prosrc, 'from private.economy where user_id = p_user for update') between 1
                  and strpos(prosrc, 'from private.profile_data where id = p_user for update') - 1
           from pg_proc where oid = 'private.purchase_economy_bundle(uuid,uuid,text)'::regprocedure),
  'F2: bundle purchase locks economy before profile_data (L1)');

-- New config versions get the cosmetic ids too (trigger) -----------------------
insert into private.economy_configs (version, config) values ('pgtap-future', '{}'::jsonb);
select is((select count(*)::int from private.economy_shop_items
           where config_version = 'pgtap-future' and private.is_cosmetic_item_id(item_id) and not enabled), 27,
  'F1: a config created later registers the 27 cosmetic ids, disabled');
update private.economy_shop_items set enabled = true where config_version = 'pgtap-future';
select ok((select bool_and(not enabled) from private.economy_shop_items where config_version = 'pgtap-future'),
  'guard: cosmetic rows cannot be enabled in a non-cosmetic config');

-- Disabled economy fails closed ----------------------------------------------
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"cosmetic_1","coins":0}'::jsonb) $$, 'player profile created');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000001', 'bundle.quack_attack') $$,
  'P0001', 'economy_disabled', 'bundle purchase fails closed while no config is active');

-- F1: the 1.2.0 config (balanced-premium-rc1) active, cosmetics not sold -------
select pg_temp.as_admin();
update private.economy_configs set active = true, approved_by = 'pgtap', approved_at = now()
where version = 'balanced-premium-rc1';
update private.economy_shop_items set enabled = true where config_version = 'balanced-premium-rc1';
select ok((select bool_and(not enabled) from private.economy_shop_items
           where config_version = 'balanced-premium-rc1' and private.is_cosmetic_item_id(item_id)),
  'guard: enabling the whole balanced-premium-rc1 shop leaves cosmetic rows disabled');

select pg_temp.as_user('cccccccc-0000-0000-0000-000000000002');
select lives_ok($$ select save_profile('{"username":"cosmetic_f1","coins":0,
  "owned_items":["quack_attack.tapButton","boom_mode.haptics","badge_custom"]}'::jsonb) $$,
  'F1: new profile saved with forged cosmetic ids');
select ok(not (pg_temp.owned('cccccccc-0000-0000-0000-000000000002') ?| array['quack_attack.tapButton','boom_mode.haptics']),
  'F1: a new profile cannot add cosmetic ids while a config is active');
select ok(pg_temp.owned('cccccccc-0000-0000-0000-000000000002') ? 'badge_custom',
  'F1: non-server-owned ids are still kept (filter is targeted)');
select lives_ok($$ select save_profile('{"owned_items":["badge_custom","purrfect_tap.tapSound"]}'::jsonb) $$,
  'F1: existing profile saves a forged cosmetic id');
select ok(not (pg_temp.owned('cccccccc-0000-0000-0000-000000000002') ? 'purrfect_tap.tapSound'),
  'F1: an existing profile cannot add a cosmetic id either');
select throws_ok($$ select purchase_economy_item('31000000-0000-0000-0000-000000000001', 'quack_attack.tapButton') $$,
  'P0001', 'item_unavailable', 'cosmetics are not for sale under balanced-premium-rc1');

-- F1 during a containment (no active config, one approved before: M3 path) -----
select pg_temp.as_admin();
update private.economy_configs set active = false where version = 'balanced-premium-rc1';
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
select lives_ok($$ select save_profile('{"username":"cosmetic_f1b","coins":0,"owned_items":["boom_mode.tapButton"]}'::jsonb) $$,
  'F1: profile saved during a containment');
select ok(not (pg_temp.owned('cccccccc-0000-0000-0000-000000000003') ? 'boom_mode.tapButton'),
  'F1: containment (M3) filter also strips cosmetic ids');

-- Activate the cosmetic candidate in this transaction only ---------------------
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
  'applied', 'single cosmetic item purchasable through the hardened RPC');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 4000::bigint, 'item charged its catalog price');

-- 3750 × (5500 − 1000) / 5500 = 3068.18 → 3068
select is((purchase_economy_bundle('30000000-0000-0000-0000-000000000003', 'bundle.quack_attack')->>'charged')::bigint,
  3068::bigint, 'bundle completion is pro-rated by missing list value');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 932::bigint, 'charged exactly once');
select is((select count(*)::int from jsonb_array_elements_text(get_my_profile()->'owned_items') x
  where x like 'quack_attack.%'), 9, 'every Quack Attack item owned, none duplicated');

-- F3: replays and key reuse
select is((purchase_economy_bundle('30000000-0000-0000-0000-000000000003', 'bundle.quack_attack')->>'status'),
  'duplicate', 'F3: replaying the same bundle purchase is a duplicate');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 932::bigint, 'duplicate charges nothing');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000003', 'bundle.purrfect_tap') $$,
  'P0001', 'invalid_payload', 'F3: reusing a bundle key for another bundle is refused');
select ok(not (get_my_profile()->'owned_items' ? 'purrfect_tap.tapButton'), 'F3: refused reuse grants nothing');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000002', 'bundle.quack_attack') $$,
  'P0001', 'invalid_payload', 'F3: an item key reused for a complete bundle is refused before already_owned');
select throws_ok($$ select purchase_economy_item('30000000-0000-0000-0000-000000000003', 'purrfect_tap.haptics') $$,
  'P0001', 'invalid_payload', 'F3: a bundle key reused for a single item is refused (hardened item RPC)');
select is((purchase_economy_bundle('30000000-0000-0000-0000-000000000004', 'bundle.quack_attack')->>'status'),
  'already_owned', 'complete bundle with a fresh key returns already_owned');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 932::bigint, 'already_owned charges nothing');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000005', 'bundle.purrfect_tap') $$,
  'P0001', 'insufficient_coins', 'insufficient balance rejects the whole bundle');
select throws_ok($$ select purchase_economy_bundle('30000000-0000-0000-0000-000000000006', 'bundle.boom_mode') $$,
  'P0001', 'item_unavailable', 'disabled bundle is unavailable');
select pg_temp.as_admin();
select is((select count(*)::int from private.economy_events
           where user_id = 'cccccccc-0000-0000-0000-000000000001' and source = 'shop_purchase'), 2,
  'exactly two debits (item + bundle)');

-- F1 cleanup: ids planted while unprotected, without a ledger entry ------------
update private.profile_data
set data = jsonb_set(data, '{owned_items}', data->'owned_items' || '["boom_mode.tapButton"]'::jsonb)
where id = 'cccccccc-0000-0000-0000-000000000001';
select is((select count(*)::int from private.strip_unpaid_cosmetic_items(true)
           where user_id = 'cccccccc-0000-0000-0000-000000000001'), 1,
  'cleanup dry run finds only the unpaid cosmetic id');
select ok(pg_temp.owned('cccccccc-0000-0000-0000-000000000001') ? 'boom_mode.tapButton', 'dry run changes nothing');
select is((select array_agg(item_id) from private.strip_unpaid_cosmetic_items(false)
           where user_id = 'cccccccc-0000-0000-0000-000000000001'), array['boom_mode.tapButton'],
  'cleanup removes the unpaid id');
select ok(not (pg_temp.owned('cccccccc-0000-0000-0000-000000000001') ? 'boom_mode.tapButton')
          and (select count(*) from jsonb_array_elements_text(pg_temp.owned('cccccccc-0000-0000-0000-000000000001')) x
               where x like 'quack_attack.%') = 9,
  'cleanup keeps every paid cosmetic (item + bundle ledger entries)');
select is((select count(*)::int from private.economy_events
           where user_id = 'cccccccc-0000-0000-0000-000000000001' and kind = 'cosmetic_unpaid_stripped'), 1,
  'cleanup is audited');

select * from finish();
rollback;
