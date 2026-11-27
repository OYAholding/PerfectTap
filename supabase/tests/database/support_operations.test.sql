-- pgTAP: internal support toolkit (owner-only, audited, bounded, idempotent).
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(27);

insert into auth.users (id, email, aud, role) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'support1@test.local', 'authenticated', 'authenticated'),
  ('eeeeeeee-0000-0000-0000-000000000002', 'support2@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;

-- ---------- privileges: owner only ----------
select ok(not has_function_privilege('authenticated', 'private.support_adjust_balance(uuid,bigint,text,text,text)', 'EXECUTE'),
  'players cannot adjust balances');
select ok(not has_function_privilege('service_role', 'private.support_adjust_balance(uuid,bigint,text,text,text)', 'EXECUTE'),
  'a leaked service key cannot adjust balances');
select ok(not has_function_privilege('anon', 'private.support_user_overview(uuid,int)', 'EXECUTE'),
  'anon cannot read support overviews');
select ok(not has_function_privilege('service_role', 'private.support_set_legacy_opening(uuid,bigint,text,text,text)', 'EXECUTE'),
  'service role cannot resolve legacy balances');
select ok(not has_table_privilege('service_role', 'private.support_actions', 'SELECT'),
  'audit log is not readable with the service key');
select ok((select rowsecurity from pg_tables where schemaname = 'private' and tablename = 'support_actions'),
  'audit log has RLS');

-- ---------- fixtures ----------
select pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"support_one","coins":4000,"owned_items":["theme_neon"]}'::jsonb) $$,
  'legacy-style player 1 profile');
select pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000002');
select lives_ok($$ select save_profile('{"username":"support_two","coins":0}'::jsonb) $$, 'player 2 profile');
select pg_temp.as_admin();
update private.economy set legacy_status = 'review', confirmed_balance = 0, legacy_opening_balance = 4000
where user_id = 'eeeeeeee-0000-0000-0000-000000000001';
update private.economy set legacy_status = 'accepted', confirmed_balance = 0
where user_id = 'eeeeeeee-0000-0000-0000-000000000002';

-- ---------- read helpers ----------
select is((select count(*)::int from private.support_find_user('SUPPORT_ONE')), 1, 'find by username (case-insensitive)');
select is((select count(*)::int from private.support_find_user('support2@test.local')), 1, 'find by email');
select is(private.support_user_overview('eeeeeeee-0000-0000-0000-000000000001')->'economy'->>'legacy_status', 'review',
  'overview shows legacy status');
select is((select count(*)::int from private.support_legacy_queue() where user_id = 'eeeeeeee-0000-0000-0000-000000000001'), 1,
  'legacy queue lists the review case');
select is(jsonb_array_length(private.support_purchase_lookup('no-such-txn')->'ledger'), 0, 'purchase lookup is empty-safe');

-- ---------- guards ----------
select throws_like($$ select private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', 100, 'op', 'T-1', 'short') $$,
  '%reason%', 'reason is mandatory');
select throws_like($$ select private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', 100, 'op', '', 'goodwill for outage') $$,
  '%ticket%', 'ticket is mandatory');
select throws_like($$ select private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', 60000, 'op', 'T-2', 'goodwill for outage') $$,
  '%within%', 'adjustments are bounded');
select throws_ok($$ select private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000001', 100, 'op', 'T-3', 'goodwill for outage') $$,
  'P0001', 'legacy_review_required', 'unresolved legacy blocks adjustments');
select throws_ok($$ select private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', -1, 'op', 'T-4', 'remove duplicate grant') $$,
  'P0001', 'insufficient_coins', 'balance never goes below zero');

-- ---------- adjust: applied once, audited ----------
select is(private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', 250, 'oya', 'T-10', 'missing purchase credit, Apple receipt seen')->>'status',
  'applied', 'adjustment applied');
select is(private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', 250, 'oya', 'T-10', 'missing purchase credit, Apple receipt seen')->>'status',
  'duplicate', 'same ticket replay is a duplicate');
select throws_like($$ select private.support_adjust_balance('eeeeeeee-0000-0000-0000-000000000002', 999, 'oya', 'T-10', 'missing purchase credit, Apple receipt seen') $$,
  '%already used%', 'a ticket cannot be reused for a different amount');
select is((select confirmed_balance from private.economy where user_id = 'eeeeeeee-0000-0000-0000-000000000002'), 250::bigint,
  'credited exactly once');
select is((select count(*)::int from private.economy_events where user_id = 'eeeeeeee-0000-0000-0000-000000000002'
           and source = 'support_adjustment'), 1, 'one ledger row');

-- ---------- legacy resolution ----------
select throws_like($$ select private.support_set_legacy_opening('eeeeeeee-0000-0000-0000-000000000001', 9000, 'oya', 'L-1', 'verified old purchase history') $$,
  '%ceiling%', 'cannot set more than the player had');
select is(private.support_set_legacy_opening('eeeeeeee-0000-0000-0000-000000000001', 3500, 'oya', 'L-1', 'verified old purchase history')->>'legacy_status',
  'accepted', 'legacy resolved to a verified balance');
select ok((select data->'owned_items' ? 'theme_neon' from private.profile_data where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  'owned items preserved through legacy resolution');

-- ---------- audit log is append-only ----------
select throws_like($$ delete from private.support_actions $$, '%append-only%', 'audit rows cannot be deleted');

select * from finish();
rollback;
