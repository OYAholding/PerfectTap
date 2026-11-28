-- QA-01 REGRESSION TEST (was: Agent E's reproduction of a defect in
-- private.purchase_economy_item, 20261125130443_authoritative_economy_ledger.sql).
--
-- The defect: apply_economy_delta() answered `duplicate` for a reused event_key
-- (no charge) and purchase_economy_item() still granted the NEW item, so
-- replaying an old key with a different item granted it for free.
--
-- FIXED on release/1.2.0 by supabase/migrations/20261127110000_economy_hardening.sql
-- (finding C1): a replay of the SAME purchase returns `duplicate`; reusing the key
-- for a different item fails `invalid_payload` and grants / charges nothing.
-- The server fix lives only there (also covered by
-- supabase/tests/database/economy_hardening.test.sql); this file only asserts it.
--
-- Run ONLY against a throwaway database with every release/1.2.0 migration
-- applied (see supabase/proposals/README.md for the container recipe), then this
-- file with psql. Everything runs in one transaction and is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(10);

insert into auth.users (id, email, aud, role) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'qa-dup@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', session_user, true);
  select set_config('request.jwt.claims', '', true);
$$;

select pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"qa_dup_1","coins":0}'::jsonb) $$, 'player profile created');

-- Activate the existing candidate config in this transaction only.
select pg_temp.as_admin();
update private.economy_configs set active = true, approved_by = 'qa', approved_at = now()
where version = 'balanced-premium-rc1';
update private.economy_shop_items set enabled = true where config_version = 'balanced-premium-rc1';
update private.economy set confirmed_balance = 1000, legacy_status = 'accepted'
where user_id = 'eeeeeeee-0000-0000-0000-000000000001';
update private.profile_data set data = jsonb_set(data, '{coins}', '1000'::jsonb)
where id = 'eeeeeeee-0000-0000-0000-000000000001';

select pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000001');
select is((purchase_economy_item('e0000000-0000-0000-0000-000000000001', 'theme_neon')->>'status'),
  'applied', 'first purchase (theme_neon, 250) applied');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 750::bigint, 'charged 250 once');

-- Replay the SAME event key with a DIFFERENT, more expensive item: refused.
select throws_ok($$ select purchase_economy_item('e0000000-0000-0000-0000-000000000001', 'theme_matrix') $$,
  'P0001', 'invalid_payload', 'QA-01: reused event key with a different item is refused (invalid_payload)');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 750::bigint, 'QA-01: refused replay charged nothing');
select ok(not coalesce(get_my_profile()->'owned_items' ? 'theme_matrix', false),
  'QA-01: reused event key does NOT grant a different item');

-- Replay of the SAME purchase stays idempotent.
select is((purchase_economy_item('e0000000-0000-0000-0000-000000000001', 'theme_neon')->>'status'),
  'duplicate', 'replaying the same purchase is a duplicate');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 750::bigint, 'duplicate charged nothing');

-- Sanity: the original item is owned, exactly one debit recorded.
select ok(get_my_profile()->'owned_items' ? 'theme_neon', 'original item owned');
select pg_temp.as_admin();
select is((select count(*)::int from private.economy_events
           where user_id = 'eeeeeeee-0000-0000-0000-000000000001' and source = 'shop_purchase'), 1,
  'exactly one shop debit');

select * from finish();
rollback;
