-- pgTAP: authoritative economy sources (contract v1). Run: supabase test db --local
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(120);

insert into auth.users (id, email, aud, role) values
  ('cccccccc-0000-0000-0000-000000000001', 'src1@test.local', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000002', 'src2@test.local', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000003', 'src3@test.local', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000004', 'src4@test.local', 'authenticated', 'authenticated'),
  ('cccccccc-0000-0000-0000-000000000005', 'src5@test.local', 'authenticated', 'authenticated');

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
create function pg_temp.data(uid uuid) returns jsonb language sql security definer as $$
  select data from private.profile_data where id = uid
$$;
create function pg_temp.bal(uid uuid) returns bigint language sql security definer as $$
  select confirmed_balance from private.economy where user_id = uid
$$;
create function pg_temp.ev(src text, payload jsonb, k uuid default gen_random_uuid()) returns jsonb language sql as $$
  select public.submit_economy_event(k, src, payload)
$$;
create function pg_temp.game(score int, combo int, taps int, duration_ms int, session uuid,
                             played interval default interval '1 minute', mode text default 'classic')
returns jsonb language sql as $$
  select jsonb_build_object('mode', mode, 'score', score, 'max_combo', combo, 'perfects', least(taps, 10),
    'taps', taps, 'duration_ms', duration_ms, 'played_at', to_char((now() - played) at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'session_id', session)
$$;
create function pg_temp.today() returns text language sql as $$
  select to_char((now() at time zone 'utc')::date, 'YYYY-MM-DD')
$$;
create function pg_temp.set_cfg(path text[], val jsonb) returns void language sql as $$
  update private.economy_configs set config = jsonb_set(config, path, val) where version = 'balanced-premium-rc1';
$$;

-- =========================== INACTIVE ===========================
select pg_temp.as_admin();
select ok(not (select active from private.economy_configs where version = 'balanced-premium-rc1'),
  'rc1 config stays inactive after the sources migration');
select ok((select config ?& array['achievement_rewards','challenge_rewards','starter_items','score_coin_divisor',
  'minimum_game_coins','combo_bonus','mode_bonus','gameplay_daily_cap','active_season','season_coin_cycle',
  'wheel_rewards','daily_rewards','quest_rewards','home_rewarded_coins','season_ads_required']
  from private.economy_configs where version = 'balanced-premium-rc1'), 'config carries every contract key');
select is((select (config->'achievement_rewards'->>'games_1')::int + (config->>'score_coin_divisor')::int
  + (config->'challenge_rewards'->'c4'->>'coins')::int from private.economy_configs where version = 'balanced-premium-rc1'),
  25 + 80 + 500, 'shared numbers pinned (games_1=25, divisor=80, c4=500)');
select is((select jsonb_object_keys_count from (select count(*)::int as jsonb_object_keys_count
  from private.economy_configs, jsonb_object_keys(config->'achievement_rewards') where version = 'balanced-premium-rc1') s),
  36, 'all 36 Swift achievements (Achievement.all) mirrored');

-- Players created while inactive: a legacy balance (u3), a plain one (u4), an implausible one (u5).
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
select save_profile('{"username":"src_three","coins":3000}'::jsonb);
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000005');
select save_profile('{"username":"src_five","coins":50000000}'::jsonb);
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000004');
select save_profile('{"username":"src_four","coins":100}'::jsonb);
select save_profile('{"coins":500}'::jsonb);
select is((get_my_profile()->>'coins')::bigint, 500::bigint, 'inactive: save_profile coin behaviour unchanged');
select throws_ok($$ select pg_temp.ev('wheel', '{}'::jsonb) $$, 'P0001', 'economy_disabled',
  'inactive: submit_economy_event fails economy_disabled');
select pg_temp.as_admin();
update private.iap_products set enabled = true;
select is(public.record_verified_purchase('cccccccc-0000-0000-0000-000000000004', 'ts-pending', 'ts-pending',
  'com.perfecttap.coins.500', 'Sandbox', now()), 'granted', 'inactive: coin pack uses the pending path');
select is((select pending_iap_coins from private.economy where user_id = 'cccccccc-0000-0000-0000-000000000004'),
  500::bigint, 'inactive: coins wait in pending_iap_coins');
select throws_ok($$ select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000004',
  gen_random_uuid(), 'home_rewarded', 'ad-inactive') $$, 'P0001', 'economy_disabled',
  'inactive: rewarded claims fail economy_disabled');

-- =========================== PRIVILEGES ===========================
select ok(has_function_privilege('authenticated', 'public.submit_economy_event(uuid,text,jsonb)', 'EXECUTE'),
  'players can submit economy events');
select ok(not has_function_privilege('anon', 'public.submit_economy_event(uuid,text,jsonb)', 'EXECUTE'),
  'anon cannot submit economy events');
select ok(not has_function_privilege('authenticated', 'private.submit_economy_event_for(uuid,uuid,text,jsonb)', 'EXECUTE'),
  'players cannot submit on behalf of another uid');
select ok(not has_function_privilege('authenticated', 'public.record_verified_rewarded_claim(uuid,uuid,text,text,uuid,smallint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.record_verified_rewarded_claim(uuid,uuid,text,text,uuid,smallint)', 'EXECUTE'),
  'anon/authenticated cannot record rewarded claims');
select ok(has_function_privilege('service_role', 'public.record_verified_rewarded_claim(uuid,uuid,text,text,uuid,smallint)', 'EXECUTE'),
  'service role records rewarded claims');
select ok(not has_function_privilege('authenticated', 'private.reconcile_legacy_economy(boolean,bigint,bigint,bigint,numeric)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.reconcile_legacy_economy(boolean,bigint,bigint,bigint,numeric)', 'EXECUTE'),
  'anon/authenticated cannot run reconciliation');
select ok(has_function_privilege('service_role', 'private.reconcile_legacy_economy(boolean,bigint,bigint,bigint,numeric)', 'EXECUTE'),
  'service role can run reconciliation');
select ok(not has_function_privilege('authenticated', 'private.apply_economy_delta(uuid,uuid,text,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role', 'private.apply_economy_delta(uuid,uuid,text,bigint,text,jsonb)', 'EXECUTE'),
  'raw delta is internal only');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'no client-callable SECURITY DEFINER function in public');
select ok((select bool_and(rowsecurity) from pg_tables where schemaname = 'private'
  and tablename in ('economy_grants','rewarded_ad_receipts')), 'RLS on new private tables');
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select throws_ok($$ select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  gen_random_uuid(), 'home_rewarded', 'ad-self') $$, '42501', null, 'player cannot self-grant ad rewards');
select throws_ok($$ select * from private.reconcile_legacy_economy(true) $$, '42501', null,
  'player cannot call reconciliation');
select pg_temp.as_anon();
select throws_ok($$ select public.submit_economy_event(gen_random_uuid(), 'wheel', '{}'::jsonb) $$, '42501', null,
  'anon call is refused');

-- =========================== ACTIVATE ===========================
select pg_temp.as_admin();
update private.economy_configs set active = true, approved_by = 'pgtap', approved_at = now()
where version = 'balanced-premium-rc1';
update private.economy_shop_items set enabled = true;
select pg_temp.set_cfg('{active_season}', jsonb_build_object('id', 'season_test', 'starts_at', now() - interval '1 hour',
  'ends_at', now() + interval '30 days', 'tiers', 30, 'max_tiers_per_day', 15));

select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select save_profile('{"username":"src_one","coins":99999}'::jsonb);
select is((get_my_profile()->>'coins')::bigint, 0::bigint, 'active: a new profile cannot choose its balance');
select is(get_my_economy_state()->>'legacyStatus', 'accepted', 'active: a new profile is authoritative at once');
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000002');
select save_profile('{"username":"src_two","season_premium":true,"season_ad_progress":99}'::jsonb);
select is((pg_temp.data('cccccccc-0000-0000-0000-000000000002')->>'season_premium')::boolean, false,
  'active: season premium needs verified ad claims, not a client counter');

-- =========================== GAMEPLAY ===========================
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is(pg_temp.ev('gameplay', pg_temp.game(800, 12, 100, 60000, 'dddddddd-0000-0000-0000-000000000001'),
  'eeeeeeee-0000-0000-0000-000000000001')->>'status', 'applied', 'plausible classic game is paid');
select is(pg_temp.bal('cccccccc-0000-0000-0000-000000000001'), 17::bigint,
  'game coins = 800/80 + combo(12)=5 + classic=2 = 17');
select is(pg_temp.ev('gameplay', pg_temp.game(800, 12, 100, 60000, 'dddddddd-0000-0000-0000-000000000001'),
  'eeeeeeee-0000-0000-0000-000000000001')->>'status', 'duplicate', 'same event_key answers duplicate');
select is(pg_temp.bal('cccccccc-0000-0000-0000-000000000001'), 17::bigint, 'duplicate pays nothing');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 12, 100, 60000, 'dddddddd-0000-0000-0000-000000000001')) $$,
  'P0001', 'already_claimed', 'same session_id with a new event_key is refused');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(500, 5, 200, 2000, gen_random_uuid())) $$,
  'P0001', 'implausible_result', 'too many taps for the duration is rejected');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(1000000, 5, 10, 60000, gen_random_uuid())) $$,
  'P0001', 'implausible_result', 'score above taps x points x multipliers is rejected');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 5, 100, 60000, gen_random_uuid(), interval '4 days')) $$,
  'P0001', 'implausible_result', 'games older than 72h are rejected');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 5, 100, 60000, gen_random_uuid(), interval '-1 hour')) $$,
  'P0001', 'implausible_result', 'games in the future are rejected');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 5, 100, 60000, gen_random_uuid(), interval '1 minute', 'zen')) $$,
  'P0001', 'invalid_payload', 'a mode that does not earn coins is refused');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 5, 100, 60000, gen_random_uuid(), interval '1 minute', 'duel')) $$,
  'P0001', 'invalid_payload', 'duel games must use the duel source');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 5, 100, 60000, gen_random_uuid()) - 'taps') $$,
  'P0001', 'invalid_payload', 'missing field is refused');
select throws_ok($$ select pg_temp.ev('gameplay', pg_temp.game(800, 5, 100, 60000, gen_random_uuid()) || '{"coins":5000}'::jsonb
  || '{"score":"800"}'::jsonb) $$, 'P0001', 'invalid_payload', 'wrong type is refused (client amounts are never read)');

-- daily cap
select pg_temp.as_admin();
select pg_temp.set_cfg('{gameplay_daily_cap}', '40');
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is(pg_temp.ev('gameplay', pg_temp.game(800, 12, 100, 60000, gen_random_uuid()))->>'granted', '17',
  'second game under the cap is paid in full');
select is(pg_temp.ev('gameplay', pg_temp.game(800, 12, 100, 60000, gen_random_uuid())) - 'balance' - 'coinDebt',
  '{"status":"capped","granted":6}'::jsonb, 'game crossing the cap is paid up to the cap');
select is(pg_temp.ev('gameplay', pg_temp.game(800, 12, 100, 60000, gen_random_uuid()))->>'granted', '0',
  'game above the cap pays 0 (recorded as capped)');
select is(pg_temp.bal('cccccccc-0000-0000-0000-000000000001'), 40::bigint, 'daily gameplay coins never exceed the cap');
select pg_temp.as_admin();
select is((select sum(capped)::int from private.economy_grants
  where user_id = 'cccccccc-0000-0000-0000-000000000001' and source = 'gameplay'), 28, 'capped excess is recorded');
select pg_temp.set_cfg('{gameplay_daily_cap}', '1500');

-- =========================== DUEL ===========================
insert into public.duels (id, code, mode, status, host_id, host_name, host_score, host_combo, host_submitted_at,
  guest_id, guest_name, guest_score, guest_combo, guest_submitted_at, joined_at, completed_at) values
  ('ffffffff-0000-0000-0000-000000000001', 'DUEL01', 'duel', 'completed',
   'cccccccc-0000-0000-0000-000000000001', 'src_one', 1600, 20, now(),
   'cccccccc-0000-0000-0000-000000000002', 'src_two', 900, 4, now(), now(), now()),
  ('ffffffff-0000-0000-0000-000000000002', 'DUEL02', 'duel', 'in_progress',
   'cccccccc-0000-0000-0000-000000000001', 'src_one', null, null, null,
   'cccccccc-0000-0000-0000-000000000003', 'src_three', 700, 3, now(), now(), null);
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is(pg_temp.ev('duel', '{"duel_id":"ffffffff-0000-0000-0000-000000000001"}')->>'granted', '34',
  'duel pays the server-read score: 1600/80 + 8 + duel 6 = 34');
select throws_ok($$ select pg_temp.ev('duel', '{"duel_id":"ffffffff-0000-0000-0000-000000000001"}') $$,
  'P0001', 'already_claimed', 'a duel pays once per player');
select throws_ok($$ select pg_temp.ev('duel', '{"duel_id":"ffffffff-0000-0000-0000-000000000002"}') $$,
  'P0001', 'duel_score_pending', 'a duel without the player''s own score is not paid yet');
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000002');
select is(pg_temp.ev('duel', '{"duel_id":"ffffffff-0000-0000-0000-000000000001"}')->>'granted', '18',
  'the opponent is paid from their own row: 900/80 + 1 + 6 = 18');

-- =========================== QUEST ===========================
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is(pg_temp.ev('quest', jsonb_build_object('quest_id','q_score_1000','difficulty','medium','server_day',pg_temp.today()))->>'granted',
  '45', 'medium quest pays 45');
select throws_ok(format($$ select pg_temp.ev('quest', '{"quest_id":"q_score_1000","difficulty":"medium","server_day":"%s"}') $$, pg_temp.today()),
  'P0001', 'already_claimed', 'a quest pays once per day');
select throws_ok(format($$ select pg_temp.ev('quest', '{"quest_id":"q_games_3","difficulty":"hard","server_day":"%s"}') $$, pg_temp.today()),
  'P0001', 'invalid_payload', 'difficulty must match the quest');
select throws_ok(format($$ select pg_temp.ev('quest', '{"quest_id":"q_games_3","difficulty":"easy","server_day":"%s"}') $$,
  to_char((now() at time zone 'utc')::date - 2, 'YYYY-MM-DD')),
  'P0001', 'invalid_payload', 'server_day must be today or yesterday');
select is(pg_temp.ev('quest', jsonb_build_object('quest_id','q_games_3','difficulty','easy','server_day',pg_temp.today()))->>'granted',
  '25', 'easy quest pays 25');
select is(pg_temp.ev('quest', jsonb_build_object('quest_id','q_combo_30','difficulty','hard','server_day',pg_temp.today()))->>'granted',
  '75', 'hard quest pays 75');
select throws_ok(format($$ select pg_temp.ev('quest', '{"quest_id":"q_combo_10","difficulty":"easy","server_day":"%s"}') $$, pg_temp.today()),
  'P0001', 'claim_limit', 'at most 3 quests per day');
select is(pg_temp.ev('quest', jsonb_build_object('quest_id','q_games_3','difficulty','easy','server_day',
  to_char((now() at time zone 'utc')::date - 1, 'YYYY-MM-DD')))->>'status', 'applied', 'yesterday''s quests have their own limit');

-- =========================== ACHIEVEMENT / CHALLENGE ===========================
select is(pg_temp.ev('achievement', '{"achievement_id":"games_1"}')->>'granted', '25', 'achievement pays the config value');
select throws_ok($$ select pg_temp.ev('achievement', '{"achievement_id":"games_1"}') $$, 'P0001', 'already_claimed',
  'an achievement pays once forever');
select throws_ok($$ select pg_temp.ev('achievement', '{"achievement_id":"hack_9"}') $$, 'P0001', 'invalid_payload',
  'unknown achievement is refused');
select is(pg_temp.ev('challenge', '{"challenge_id":"c9"}') - 'balance' - 'coinDebt',
  '{"status":"applied","granted":0,"itemID":"theme_fire"}'::jsonb, 'item challenge grants its item');
select ok(pg_temp.data('cccccccc-0000-0000-0000-000000000001')->'owned_items' ? 'theme_fire', 'challenge item owned');
select is(pg_temp.ev('challenge', '{"challenge_id":"c1"}')->>'granted', '50', 'coin challenge pays the config value');
select throws_ok($$ select pg_temp.ev('challenge', '{"challenge_id":"c1"}') $$, 'P0001', 'already_claimed',
  'a challenge pays once forever');

-- =========================== SEASON ===========================
select is(pg_temp.ev('season_tier', '{"season_id":"season_test","tier":1}')->>'granted', '25', 'tier 1 pays cycle[0]');
select throws_ok($$ select pg_temp.ev('season_tier', '{"season_id":"season_test","tier":1}') $$, 'P0001', 'already_claimed',
  'a tier pays once per season');
select throws_ok($$ select pg_temp.ev('season_tier', '{"season_id":"season_test","tier":16}') $$, 'P0001', 'implausible_result',
  'tier beyond the daily pace is rejected');
select throws_ok($$ select pg_temp.ev('season_tier', '{"season_id":"season_old","tier":2}') $$, 'P0001', 'invalid_payload',
  'another season is refused');
select pg_temp.as_admin();
update private.profile_data set data = data || '{"season_premium": true}'::jsonb
where id = 'cccccccc-0000-0000-0000-000000000001';
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is(pg_temp.ev('season_tier', '{"season_id":"season_test","tier":1}') - 'balance' - 'coinDebt',
  '{"status":"applied","granted":0,"itemID":"avatar_cool"}'::jsonb, 'premium unlocked later: tier pays its premium item');
select throws_ok($$ select pg_temp.ev('season_tier', '{"season_id":"season_test","tier":1}') $$, 'P0001', 'already_claimed',
  'premium item pays once');
select is(pg_temp.ev('season_tier', '{"season_id":"season_test","tier":3}') - 'balance' - 'coinDebt',
  '{"status":"applied","granted":75,"itemID":"theme_neon"}'::jsonb, 'premium player gets coins + item together');

-- =========================== WHEEL ===========================
create temp table wheel_out as
  select pg_temp.ev('wheel', '{"segment_index":7,"amount":9999}', 'eeeeeeee-0000-0000-0000-0000000000a1') as r;
select pg_temp.as_admin();
select ok((select (r->>'segmentIndex')::int between 0 and 7 from wheel_out), 'server picks a segment 0..7');
select is((select (r->>'granted')::bigint from wheel_out),
  (select (config->'wheel_rewards'->>((select (r->>'segmentIndex')::int from wheel_out)))::bigint
   from private.economy_configs where active), 'wheel pays the config amount of the server segment (client values ignored)');
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000001');
select is((pg_temp.ev('wheel', '{}', 'eeeeeeee-0000-0000-0000-0000000000a1')->>'segmentIndex')::int,
  (select (r->>'segmentIndex')::int from wheel_out), 'duplicate wheel event returns the same segment');
select throws_ok($$ select pg_temp.ev('wheel', '{}') $$, 'P0001', 'already_claimed', 'one wheel spin per UTC day');

-- =========================== STARTER ===========================
select throws_ok($$ select pg_temp.ev('starter_item', '{"item_id":"avatar_dragon"}') $$, 'P0001', 'item_unavailable',
  'only configured starter items');
select is(pg_temp.ev('starter_item', '{"item_id":"fx_ripple"}')->>'itemID', 'fx_ripple', 'starter item granted');
select ok(pg_temp.data('cccccccc-0000-0000-0000-000000000001')->'owned_items' ? 'fx_ripple', 'starter item owned');
select throws_ok($$ select pg_temp.ev('starter_item', '{"item_id":"theme_neon"}') $$, 'P0001', 'already_claimed',
  'one starter pick per player');

-- =========================== SPENDING / PIN ===========================
select throws_ok($$ select purchase_economy_item(gen_random_uuid(), 'avatar_dragon') $$, 'P0001', 'insufficient_coins',
  'shop refuses a purchase above the confirmed balance');
select save_profile(jsonb_build_object('coins', 999999, 'owned_items', jsonb_build_array('avatar_dragon','badge_custom','fx_ripple'),
  'daily_reward_streak', 6, 'daily_reward_last_claim', '2000-01-01'));
select is((pg_temp.data('cccccccc-0000-0000-0000-000000000001')->>'coins')::bigint,
  pg_temp.bal('cccccccc-0000-0000-0000-000000000001'), 'active: save_profile pins coins to confirmed_balance');
select ok(not (pg_temp.data('cccccccc-0000-0000-0000-000000000001')->'owned_items' ? 'avatar_dragon'),
  'active: client cannot add a coin-sold item');
select ok(pg_temp.data('cccccccc-0000-0000-0000-000000000001')->'owned_items' ?& array['badge_custom','theme_fire','avatar_cool','theme_neon'],
  'active: non-shop items kept, server-granted items survive a stale client list');
select ok(not (pg_temp.data('cccccccc-0000-0000-0000-000000000001') ?| array['daily_reward_streak','daily_reward_last_claim']),
  'active: daily-reward streak/last-claim are server-owned');

-- pending legacy account: frozen, never reduced
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000003');
select save_profile('{"coins":10}'::jsonb);
select is((pg_temp.data('cccccccc-0000-0000-0000-000000000003')->>'coins')::bigint, 3000::bigint,
  'active: unreconciled legacy balance is frozen (no increase, no silent decrease)');
select throws_ok($$ select pg_temp.ev('wheel', '{}') $$, 'P0001', 'legacy_review_required',
  'unreconciled account cannot earn yet');

-- pending IAP coins from the inactive era move into the ledger on next save
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000004');
select save_profile('{"coins":0}'::jsonb);
select is((pg_temp.data('cccccccc-0000-0000-0000-000000000004')->>'coins')::bigint, 1000::bigint,
  'inactive-era paid coins are credited, not lost, when coins become pinned');
select pg_temp.as_admin();
select is((select pending_iap_coins from private.economy where user_id = 'cccccccc-0000-0000-0000-000000000004'), 0::bigint,
  'pending IAP coins drained exactly once');

-- =========================== STOREKIT (active) ===========================
select is(public.record_verified_purchase('cccccccc-0000-0000-0000-000000000002', 'ta-1', 'ta-1',
  'com.perfecttap.coins.500', 'Sandbox', now()), 'granted', 'active: coin pack granted');
select is(pg_temp.bal('cccccccc-0000-0000-0000-000000000002'), 518::bigint, 'active: pack credited to the ledger at once (18 + 500)');
select is(public.record_verified_purchase('cccccccc-0000-0000-0000-000000000002', 'ta-1', 'ta-1',
  'com.perfecttap.coins.500', 'Sandbox', now()), 'already_granted', 'replayed transaction is not credited twice');
select throws_ok($$ select public.record_verified_purchase('cccccccc-0000-0000-0000-000000000001', 'ta-1', 'ta-1',
  'com.perfecttap.coins.500', 'Sandbox', now()) $$, 'P0001', 'owned_by_other_account', 'a transaction never credits a second user');
select is((select count(*)::int from private.economy_events
  where event_key = private.deterministic_uuid('iap_coins:ta-1')), 1, 'exactly one ledger credit for the transaction');
select is(public.record_verified_purchase('cccccccc-0000-0000-0000-000000000003', 'ta-3', 'ta-3',
  'com.perfecttap.coins.500', 'Sandbox', now()), 'granted', 'pending-legacy account can buy coins');
select is((pg_temp.data('cccccccc-0000-0000-0000-000000000003')->>'coins')::bigint, 3500::bigint,
  'paid coins are added on top of the frozen legacy balance');

select pg_temp.as_user('cccccccc-0000-0000-0000-000000000002');
select is(purchase_economy_item(gen_random_uuid(), 'theme_neon')->>'status', 'applied', 'spend part of the pack (518 - 250)');
select pg_temp.as_admin();
select is(public.revoke_purchase('ta-1', now()), 'revoked', 'coin refund recorded');
select is(pg_temp.bal('cccccccc-0000-0000-0000-000000000002'), 0::bigint, 'refund debits to zero');
select is((select coin_debt from private.economy where user_id = 'cccccccc-0000-0000-0000-000000000002'), 0::bigint,
  'no coin_debt is created');
select is(public.revoke_purchase('ta-1', now()), 'already_revoked', 'refund is idempotent');
select is((select (metadata->>'uncollected')::int from private.economy_events
  where user_id = 'cccccccc-0000-0000-0000-000000000002' and source = 'iap_revoke'), 500 - 268,
  'shortfall is recorded for support, not collected');
select is(private.reinstate_purchase('ta-1'), 'reinstated', 'refund reversal reinstates');
select is(pg_temp.bal('cccccccc-0000-0000-0000-000000000002'), 268::bigint,
  'reversal restores exactly what the refund took');
select is(private.reinstate_purchase('ta-1'), 'already_active', 'reinstate is idempotent');

-- =========================== REWARDED ADS (service role) ===========================
select is(public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  'eeeeeeee-0000-0000-0000-0000000000b1', 'home_rewarded', 'ad-1')->>'granted', '15', 'home rewarded pays config value');
select is(public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  'eeeeeeee-0000-0000-0000-0000000000b1', 'home_rewarded', 'ad-1')->>'status', 'duplicate', 'SSV retry is a duplicate');
select throws_ok($$ select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000002',
  gen_random_uuid(), 'home_rewarded', 'ad-1') $$, 'P0001', 'already_claimed', 'one ad impression never pays two users');
select throws_ok($$ select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  gen_random_uuid(), 'home_rewarded', 'ad-2') $$, 'P0001', 'claim_limit', 'home rewarded once per day');
select is(public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  gen_random_uuid(), 'double_coins', 'ad-3', 'eeeeeeee-0000-0000-0000-000000000001')->>'granted', '17',
  'double coins pays the referenced game grant');
select throws_ok($$ select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000002',
  gen_random_uuid(), 'double_coins', 'ad-4', 'eeeeeeee-0000-0000-0000-000000000001') $$, 'P0001', 'invalid_payload',
  'double coins cannot reference another player''s game');
select is(public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  gen_random_uuid(), 'revive', 'ad-5')->>'status', 'recorded', 'revive pays 0 coins');
select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001', gen_random_uuid(), 'revive', 'ad-6');
select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001', gen_random_uuid(), 'revive', 'ad-7');
select throws_ok($$ select public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000001',
  gen_random_uuid(), 'revive', 'ad-8') $$, 'P0001', 'claim_limit', 'revive capped at 3 per day');
select pg_temp.set_cfg('{season_ads_required}', '1');
select is(public.record_verified_rewarded_claim('cccccccc-0000-0000-0000-000000000002',
  gen_random_uuid(), 'season_progress', 'ad-9')->>'status', 'recorded', 'season progress recorded');
select pg_temp.as_user('cccccccc-0000-0000-0000-000000000002');
select save_profile('{"season_premium":false}'::jsonb);
select is((pg_temp.data('cccccccc-0000-0000-0000-000000000002')->>'season_premium')::boolean, true,
  'verified ad claims unlock season premium server-side');

-- =========================== UNIQUENESS (concurrency) ===========================
select pg_temp.as_admin();
select throws_ok($$ insert into private.economy_grants (user_id, source, grant_key, server_day, event_key)
  values ('cccccccc-0000-0000-0000-000000000001', 'achievement', 'achievement:games_1', current_date, gen_random_uuid()) $$,
  '23505', null, 'grant uniqueness is enforced by a unique index, not only by reads');
select throws_ok($$ insert into private.economy_grants (user_id, source, grant_key, server_day, event_key)
  values ('cccccccc-0000-0000-0000-000000000001', 'achievement', 'achievement:other', current_date,
          'eeeeeeee-0000-0000-0000-000000000001') $$,
  '23505', null, 'event_key uniqueness is enforced by a unique index');
select throws_ok($$ insert into private.economy_events (user_id, kind, event_key, source, amount)
  values ('cccccccc-0000-0000-0000-000000000001', 'ledger_delta', private.deterministic_uuid('iap_coins:ta-1'), 'iap_coins', 500) $$,
  '23505', null, 'a transaction credit key is globally unique across users');

-- =========================== RECONCILIATION ===========================
create temp table recon_dry as select * from private.reconcile_legacy_economy(true);
select is((select classification from recon_dry where user_id = 'cccccccc-0000-0000-0000-000000000003'), 'accepted',
  'plausible legacy balance classified accepted');
select is((select classification from recon_dry where user_id = 'cccccccc-0000-0000-0000-000000000005'), 'rejected',
  'implausible legacy balance classified rejected');
select is((select count(*)::int from private.economy where legacy_status <> 'pending'
  and user_id in ('cccccccc-0000-0000-0000-000000000003','cccccccc-0000-0000-0000-000000000005')), 0,
  'dry run changes nothing');
create temp table recon_apply as select * from private.reconcile_legacy_economy(false);
select is((select legacy_status || ':' || confirmed_balance from private.economy
  where user_id = 'cccccccc-0000-0000-0000-000000000003'), 'accepted:3500', 'applied: accepted keeps its current balance');
select is((select legacy_status from private.economy where user_id = 'cccccccc-0000-0000-0000-000000000005')
  || ':' || (pg_temp.data('cccccccc-0000-0000-0000-000000000005')->>'coins'), 'rejected:50000000',
  'applied: rejected is never reduced silently');

select * from finish();
rollback;
