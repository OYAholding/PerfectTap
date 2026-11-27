-- pgTAP: regressions for the 2026-11-27 adversarial review (20261127110000_economy_hardening).
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(28);

insert into auth.users (id, email, aud, role) values
  ('ffffffff-0000-0000-0000-000000000001', 'h1@test.local', 'authenticated', 'authenticated'),
  ('ffffffff-0000-0000-0000-000000000002', 'h2@test.local', 'authenticated', 'authenticated'),
  ('ffffffff-0000-0000-0000-000000000003', 'h3@test.local', 'authenticated', 'authenticated'),
  ('ffffffff-0000-0000-0000-000000000004', 'h4@test.local', 'authenticated', 'authenticated'),
  ('ffffffff-0000-0000-0000-000000000005', 'h5@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.data(uid uuid) returns jsonb language sql security definer as $$
  select data from private.profile_data where id = uid
$$;
create function pg_temp.econ(uid uuid) returns private.economy language sql security definer as $$
  select * from private.economy where user_id = uid
$$;

-- ---------- pre-activation: legacy-path behaviour is unchanged ----------
select pg_temp.as_user('ffffffff-0000-0000-0000-000000000005');
select lives_ok($$ select save_profile('{"username":"pre_act","coins":10,"owned_items":["theme_neon"]}'::jsonb) $$,
  'before any approval a 1.1 client may still save coin-shop items');
select pg_temp.as_admin();
select ok(pg_temp.data('ffffffff-0000-0000-0000-000000000005')->'owned_items' ? 'theme_neon',
  'M3 filter is inert until a config has ever been approved');

-- ---------- activate (test DB only) ----------
update private.economy_configs set active = true, approved_by = 'pgtap', approved_at = now()
where version = 'balanced-premium-rc1';
update private.economy_shop_items set enabled = true where config_version = 'balanced-premium-rc1';

select pg_temp.as_user('ffffffff-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"hard_one","coins":0}'::jsonb) $$, 'profile');
select pg_temp.as_admin();
update private.economy set legacy_status = 'accepted', confirmed_balance = 5000
where user_id = 'ffffffff-0000-0000-0000-000000000001';
update private.profile_data set data = jsonb_set(data, '{coins}', '5000') where id = 'ffffffff-0000-0000-0000-000000000001';

-- ---------- C1: event-key replay never grants a second item ----------
select pg_temp.as_user('ffffffff-0000-0000-0000-000000000001');
select is(public.submit_economy_event('aaaa0000-0000-0000-0000-000000000001', 'wheel', '{}')->>'status', 'applied',
  'free wheel spin under key K');
select throws_ok($$ select purchase_economy_item('aaaa0000-0000-0000-0000-000000000001', 'theme_matrix') $$,
  'P0001', 'invalid_payload', 'C1: reusing the wheel key for a shop purchase is refused');
select ok(not coalesce(get_my_profile()->'owned_items' ? 'theme_matrix', false), 'C1: no free item');
select is(purchase_economy_item('aaaa0000-0000-0000-0000-000000000002', 'theme_neon')->>'status', 'applied',
  'a real purchase works');
select throws_ok($$ select purchase_economy_item('aaaa0000-0000-0000-0000-000000000002', 'avatar_dragon') $$,
  'P0001', 'invalid_payload', 'C1: reusing a purchase key for another item is refused');
select ok(not coalesce(get_my_profile()->'owned_items' ? 'avatar_dragon', false), 'C1: still no free item');
select is(purchase_economy_item('aaaa0000-0000-0000-0000-000000000002', 'theme_neon')->>'status', 'duplicate',
  'replaying the same purchase is a duplicate');
select pg_temp.as_admin();
select is((select count(*)::int from private.economy_events
           where user_id = 'ffffffff-0000-0000-0000-000000000001' and source = 'shop_purchase'), 1,
  'exactly one debit');

-- ---------- M2: season premium only from this season's verified ads ----------
update private.profile_data set data = data || '{"season_premium": true}'::jsonb
where id = 'ffffffff-0000-0000-0000-000000000001';
select pg_temp.as_user('ffffffff-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"hard_one","season_premium":true,"season_ad_progress":99}'::jsonb) $$, 'save');
select is(get_my_profile()->'season_premium', 'false'::jsonb, 'M2: a stored/sent premium flag is not sticky');
select pg_temp.as_admin();
insert into private.economy_reward_claims (user_id, source, server_day, claim_index, event_key)
select 'ffffffff-0000-0000-0000-000000000001', 'season_progress', (s.starts_at at time zone 'utc')::date + d, 1, gen_random_uuid()
from private.season_at((select config from private.economy_configs where active), now()) s,
     generate_series(0, 19) d;
select pg_temp.as_user('ffffffff-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"hard_one"}'::jsonb) $$, 'save');
select is(get_my_profile()->'season_premium', 'true'::jsonb, 'M2: 20 verified ads this season unlock premium');

-- ---------- M5: achievement/challenge payouts are capped per day ----------
select is(public.submit_economy_event(gen_random_uuid(), 'achievement', '{"achievement_id":"games_1000"}')->>'status',
  'applied', 'first progress claim of the day always passes (2500)');
select throws_ok($$ select public.submit_economy_event(gen_random_uuid(), 'achievement', '{"achievement_id":"coins_100000"}') $$,
  'P0001', 'progress_daily_limit', 'M5: over the daily progress cap is deferred');
select is(public.submit_economy_event(gen_random_uuid(), 'achievement', '{"achievement_id":"games_1"}')->>'status',
  'applied', 'small claims still fit under the cap');

-- ---------- M3: during containment clients cannot add server-owned items ----------
select pg_temp.as_admin();
update private.economy_configs set active = false where active;   -- containment
select pg_temp.as_user('ffffffff-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"hard_one","owned_items":["theme_neon","avatar_unicorn"]}'::jsonb) $$, 'save');
select ok(not (get_my_profile()->'owned_items' ? 'avatar_unicorn'), 'M3: contained economy keeps shop items server-owned');
select ok(get_my_profile()->'owned_items' ? 'theme_neon', 'M3: owned items are preserved');
select pg_temp.as_admin();
update private.economy_configs set active = true where version = 'balanced-premium-rc1';

-- ---------- C2 / H1: legacy claims after activation ----------
insert into legacy.players (firebase_uid, username, friend_code, data) values
  ('fb_snapshot', 'old_timer', null, '{"coins": 800, "owned_items": ["theme_fire"], "season_premium": true}'::jsonb);
insert into private.legacy_snapshot_uids values ('fb_snapshot');
-- H1: account already accepted with 300 coins claims an honest snapshot player.
select pg_temp.as_user('ffffffff-0000-0000-0000-000000000002');
select lives_ok($$ select save_profile('{"username":"","coins":0}'::jsonb) $$, 'empty profile first');
select pg_temp.as_admin();
update private.economy set legacy_status = 'accepted', confirmed_balance = 300 where user_id = 'ffffffff-0000-0000-0000-000000000002';
select is(public.claim_legacy_profile_fresh('ffffffff-0000-0000-0000-000000000002', 'fb_snapshot')->>'status', 'claimed', 'claim');
select is((pg_temp.econ('ffffffff-0000-0000-0000-000000000002')).legacy_opening_balance, 1100::bigint,
  'H1: claimed coins join the balance as a reviewed candidate (800 + 300), not lost');

-- C2: a Firebase account that was never in the import snapshot.
select is(public.claim_legacy_profile_fresh('ffffffff-0000-0000-0000-000000000003', 'fb_forged',
  '{"username":"forged","coins":4500,"owned_items":["theme_matrix","avatar_dragon","theme_cosmicgold"],"season_premium":true,"no_ads":true}'::jsonb)->>'status',
  'claimed', 'JIT-only claim proceeds');
select ok(not (pg_temp.data('ffffffff-0000-0000-0000-000000000003')->'owned_items' ?| array['theme_matrix','avatar_dragon','theme_cosmicgold'])
          and (pg_temp.econ('ffffffff-0000-0000-0000-000000000003')).legacy_status = 'review'
          and pg_temp.data('ffffffff-0000-0000-0000-000000000003')->'season_premium' = 'false'::jsonb,
  'C2: forged document keeps no server items / premium; coins go to human review');

-- ---------- L6 / M1: refunds of deleted accounts, Sandbox evidence ----------
select pg_temp.as_admin();
select is(public.revoke_purchase('t-deleted-user', now(), 'com.perfecttap.coins.500', null, 'Production',
                                 '99999999-0000-0000-0000-000000000009'), 'revoked',
  'L6: refund for a deleted account leaves a tombstone instead of failing forever');
insert into private.economy (user_id, confirmed_balance, legacy_opening_balance, legacy_status)
values ('ffffffff-0000-0000-0000-000000000004', 0, 9000, 'pending') on conflict (user_id) do update set legacy_status = 'pending';
insert into private.purchase_ledger (transaction_id, original_transaction_id, user_id, product_id, environment, purchased_at)
values ('t-sandbox-1', 't-sandbox-1', 'ffffffff-0000-0000-0000-000000000004', 'com.perfecttap.coins.3000', 'Sandbox', now());
select is((select verified_floor from private.reconcile_legacy_economy(true)
           where user_id = 'ffffffff-0000-0000-0000-000000000004'), 0::bigint,
  'M1: Sandbox purchases are not paid evidence in reconciliation');

select * from finish();
rollback;
