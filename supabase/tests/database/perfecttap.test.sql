-- pgTAP suite for the PerfectTap schema. Run: supabase test db --local
begin;
create extension if not exists pgtap with schema extensions;
-- pgTAP may live in a different schema locally vs. hosted: put it on the path.
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(70);

-- ---------- fixtures ----------
insert into auth.users (id, email, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'host@test.local',  'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'guest@test.local', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'third@test.local', 'authenticated', 'authenticated'),
  ('44444444-4444-4444-4444-444444444444', 'empty@test.local', 'authenticated', 'authenticated');

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

-- ---------- RLS is on everywhere exposed ----------
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity), 0,
  'every public table has RLS enabled');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'no SECURITY DEFINER function is client-callable in the exposed public schema');

-- ---------- profiles ----------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select save_profile('{"username":"HostOne","friend_code":"HOST01","coins":50,"level":3,
   "best_classic":1200,"equipped_avatar":"cat","stats":{"totalGames":4},"no_ads":true}'::jsonb) $$,
  'owner can save profile');
select is((get_my_profile()->>'coins')::int, 50, 'get_my_profile returns private coins');
select is(get_my_profile()->>'friend_code', 'HOST01', 'friend code stored');
select is((get_my_profile()->>'best_classic')::int, 1200, 'best score round-trips');
select throws_ok($$ select save_profile('{"username":"Renamed"}'::jsonb) $$, 'P0001', 'username_immutable',
  'username is permanent');
select throws_ok($$ select save_profile('{"username":"HostOne","coins":-5}'::jsonb) $$, 'P0001', 'invalid_coins',
  'negative coins rejected');
select throws_ok($$ select save_profile('{"username":"HostOne","coins":"lots"}'::jsonb) $$, 'P0001', 'invalid_coins',
  'non-numeric coins rejected');
select throws_ok($$ select save_profile('{"username":"HostOne","best_classic":99999999}'::jsonb) $$, 'P0001',
  'invalid_best_classic', 'out-of-range best score rejected');
select throws_ok($$ select save_profile('{"username":"HostOne","no_ads":"yes"}'::jsonb) $$, 'P0001', 'invalid_no_ads',
  'non-boolean flag rejected');
select throws_ok($$ select save_profile(jsonb_build_object('username','HostOne','quests_json', repeat('x', 300000))) $$,
  'P0001', 'payload_too_large', 'oversized payload rejected');
select lives_ok($$ select save_profile('{"username":"HostOne","friend_code":"CHANGED","coins":60,"equipped_avatar":"cat"}'::jsonb) $$,
  'resave works');
select is(get_my_profile()->>'friend_code', 'HOST01', 'friend code cannot be changed');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select save_profile('{"username":"hostone"}'::jsonb) $$, 'P0001', 'username_taken',
  'case-insensitive username uniqueness');
select throws_ok($$ select save_profile('{"username":"bad name!"}'::jsonb) $$, 'P0001', 'invalid_profile',
  'username format enforced');
select ok(not is_username_available('HOSTONE'), 'username availability is case-insensitive');
select lives_ok($$ select save_profile('{"username":"GuestTwo","friend_code":"GUEST2","coins":5}'::jsonb) $$,
  'second player saves');
select is((select (p->>'coins') from get_player_profiles(array['11111111-1111-1111-1111-111111111111'::uuid]) p), null,
  'other players cannot read private coins');
select is((select (p->>'equipped_avatar') from get_player_profiles(array['11111111-1111-1111-1111-111111111111'::uuid]) p),
  'cat', 'public cosmetics visible to others');
select throws_ok($$ insert into profiles (id, username) values ('22222222-2222-2222-2222-222222222222','x') $$,
  '42501', null, 'no direct inserts into profiles');
select throws_ok($$ update profiles set level = 999 where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501', null, 'no direct updates of profiles');
select throws_ok($$ select * from private.profile_data $$, '42501', null, 'private schema not readable');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select lives_ok($$ select save_profile('{"username":"ThirdP","friend_code":"THIRD3"}'::jsonb) $$, 'third player saves');

-- ---------- anon is locked out ----------
select pg_temp.as_anon();
select throws_ok($$ select save_profile('{"username":"Anon"}'::jsonb) $$, '42501', null, 'anon cannot call RPCs');
select throws_ok($$ select * from profiles $$, '42501', null, 'anon cannot read profiles');

-- ---------- duel lifecycle ----------
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select throws_ok($$ select * from create_duel('duel') $$, 'P0001', 'username_required',
  'player without username cannot host');

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
create temp table t_duel as select * from create_duel('duel');
grant select on t_duel to authenticated;
select is((select count(*)::int from t_duel), 1, 'host creates duel');
select matches((select code from t_duel), '^[A-Z0-9]{6}$', 'duel code format');
select throws_ok($$ select * from create_duel('zen') $$, 'P0001', 'invalid_mode', 'unscored mode cannot be dueled');
select throws_ok($$ select * from join_duel((select code from t_duel)) $$, 'P0001', 'cannot_join_own_duel',
  'host cannot join own duel');
select throws_ok($$ insert into duels (code, mode, host_name) values ('ABCDEF','duel','x') $$, '42501', null,
  'no direct duel inserts');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from duels), 0, 'non-participant cannot see the duel');
select is((select count(*)::int from join_duel('ZZZZZZ')), 0, 'unknown code returns no duel');
select is((select count(*)::int from join_duel('x''; drop table duels;--')), 0, 'malformed code returns no duel');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select host_name from join_duel((select lower(code) from t_duel))), 'HostOne',
  'guest joins by code (case-insensitive)');
select is((select status from duels where id = (select duel_id from t_duel)), 'in_progress', 'duel in progress');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from join_duel((select code from t_duel))), 0, 'full duel cannot be joined');
select throws_ok($$ select submit_duel_score((select duel_id from t_duel), null, 100, 1, 1, 1) $$, 'P0001',
  'duel_not_found', 'outsider cannot submit a duel score');

-- host plays with a server-timed session
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
create temp table t_sess as select start_game_session('duel', (select duel_id from t_duel)) as id;
grant select on t_sess to authenticated;
select throws_ok($$ select start_game_session('classic', (select duel_id from t_duel)) $$, 'P0001', 'mode_mismatch',
  'session mode must match duel');
-- backdate the session so the tap-rate bound allows a real score
select pg_temp.as_admin();
update private.game_sessions set started_at = now() - interval '60 seconds' where id = (select id from t_sess);
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((submit_duel_score((select duel_id from t_duel), (select id from t_sess), 4000, 30, 40, 30))->>'accepted',
  'true', 'host score accepted');
select is((submit_duel_score((select duel_id from t_duel), (select id from t_sess), 9999, 30, 40, 30))->>'duplicate',
  'true', 'duplicate submission is idempotent');
select is((select host_score from duels where id = (select duel_id from t_duel)), 4000,
  'duplicate did not overwrite the score');
select is((select host_verified from duels where id = (select duel_id from t_duel)), true, 'host score verified');

-- guest submits an impossible score without a session → flagged as 0, duel completes
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((submit_duel_score((select duel_id from t_duel), null, 500000, 10, 10, 10))->>'reason',
  'score_exceeds_taps', 'implausible duel score flagged');
select is((select status from duels where id = (select duel_id from t_duel)), 'completed',
  'second submission completes the duel');
select is((select guest_score from duels where id = (select duel_id from t_duel)), 0, 'flagged score recorded as 0');
select is((submit_duel_score((select duel_id from t_duel), null, 1, 1, 1, 1))->>'duplicate', 'true',
  'completed duel cannot be modified');

-- ---------- ranked score submission ----------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
create temp table t_rank as select start_game_session('classic') as id;
grant select on t_rank to authenticated;
select is((submit_score((select id from t_rank), 'classic', 100000, 50, 500, 400))->>'reason',
  'too_many_taps_for_time', 'taps impossible for elapsed time rejected');
select is((submit_score((select id from t_rank), 'classic', 10, 1, 1, 1))->>'reason', 'session_used',
  'session is single-use');
create temp table t_rank2 as select start_game_session('classic') as id;
grant select on t_rank2 to authenticated;
select pg_temp.as_admin();
update private.game_sessions set started_at = now() - interval '120 seconds' where id = (select id from t_rank2);
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((submit_score((select id from t_rank2), 'classic', 30000, 80, 300, 200))->>'accepted', 'true',
  'plausible ranked score accepted');
select is((select score from get_leaderboard('classic', 10) limit 1), 30000, 'verified leaderboard updated');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((submit_score((select id from t_rank2), 'classic', 1, 1, 1, 1))->>'reason', 'invalid_session',
  'another player cannot use my session');
select throws_ok($$ insert into leaderboard_scores (mode, user_id, score) values
  ('classic','22222222-2222-2222-2222-222222222222', 9999999) $$, '42501', null, 'leaderboard is not client-writable');

-- ---------- friends ----------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select throws_ok($$ select send_friend_request('HOST01') $$, 'P0001', 'cannot_add_self', 'cannot friend yourself');
select throws_ok($$ select send_duel_invitation('22222222-2222-2222-2222-222222222222', 'duel') $$, 'P0001',
  'not_friends', 'duel invites require friendship');
create temp table t_req as select send_friend_request('guest2') as id;
grant select on t_req to authenticated;
select throws_ok($$ select send_friend_request('GUEST2') $$, 'P0001', 'request_pending', 'duplicate request blocked');
select throws_ok($$ select respond_friend_request((select id from t_req), true) $$, 'P0001', 'request_not_found',
  'sender cannot accept own request');

select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from friend_requests), 0, 'third party cannot see the request');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select throws_ok($$ select send_friend_request('HOST01') $$, 'P0001', 'request_pending', 'reverse duplicate blocked');
select lives_ok($$ select respond_friend_request((select id from t_req), true) $$, 'receiver accepts');
select is((select count(*)::int from friendships), 1, 'friendship created');

-- ---------- duel invitations ----------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
create temp table t_inv as select * from send_duel_invitation('22222222-2222-2222-2222-222222222222', 'rush');
grant select on t_inv to authenticated;
select throws_ok($$ select send_duel_invitation('22222222-2222-2222-2222-222222222222', 'rush') $$, 'P0001',
  'invite_pending', 'one pending invite per pair');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(accept_duel_invitation((select id from t_inv)), (select duel_id from t_inv), 'accept joins the invite duel');
select is((select status from duels where id = (select duel_id from t_inv)), 'in_progress', 'invite duel started');
select throws_ok($$ select accept_duel_invitation((select id from t_inv)) $$, 'P0001', 'invitation_not_pending',
  'double accept rejected');

select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select ok(mark_duel_invitation_in_progress((select id from t_inv)), 'host marks invite in progress');

-- retry after the 2h session TTL: accepted as unverified, not zeroed
create temp table t_exp as select start_game_session('rush', (select duel_id from t_inv)) as id;
grant select on t_exp to authenticated;
select pg_temp.as_admin();
update private.game_sessions set started_at = now() - interval '3 hours', expires_at = now() - interval '1 hour'
 where id = (select id from t_exp);
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((submit_duel_score((select duel_id from t_inv), (select id from t_exp), 700, 5, 20, 10))->>'accepted', 'true',
  'late retry with expired session accepted');
select is((select host_score from duels where id = (select duel_id from t_inv)), 700, 'late retry keeps the real score');
select is((select host_verified from duels where id = (select duel_id from t_inv)), false, 'late retry marked unverified');

select * from finish();
rollback;
