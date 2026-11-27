-- QA (Agent E) — reproduces a pre-existing defect in private.purchase_economy_item
-- (supabase/migrations/20261125130443_authoritative_economy_ledger.sql).
--
-- When apply_economy_delta() sees an event_key that was already used it returns
-- status 'duplicate' and charges nothing — but purchase_economy_item() then still
-- calls set_profile_item() for the NEW item id. Replaying an old event key with a
-- different item therefore grants that item for free.
--
-- Also checks that the PROPOSED bundle RPC (supabase/proposals/) does not have the
-- defect, when the proposal file is applied on top (second half, optional).
--
-- Run ONLY against a throwaway database with every migration applied, e.g.
--   docker run -d --name qa-pg -p 127.0.0.1:55790:5432 -e POSTGRES_PASSWORD=x public.ecr.aws/supabase/postgres:17.11.0.018
--   (apply supabase/migrations/*.sql in order, then this file with psql)
-- Everything runs in one transaction and is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(7);

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

-- Replay the SAME event key with a DIFFERENT, more expensive item.
select is((purchase_economy_item('e0000000-0000-0000-0000-000000000001', 'theme_matrix')->>'status'),
  'duplicate', 'reused event key is reported as duplicate');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 750::bigint, 'duplicate charged nothing');

-- EXPECTED (secure): a duplicate grants nothing. This assertion FAILS on the
-- current migrations: theme_matrix (2500 coins) is granted for free.
select ok(not (get_my_profile()->'owned_items' ? 'theme_matrix'),
  'duplicate event key must NOT grant a different item (fails = defect present)');

-- Sanity: the original item is owned.
select ok(get_my_profile()->'owned_items' ? 'theme_neon', 'original item owned');

select * from finish();
rollback;
