-- pgTAP: authoritative economy ledger remains disabled until owner activation.
begin;
create extension if not exists pgtap with schema extensions;
do $$
declare s text;
begin
  select n.nspname into s from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgtap';
  perform set_config('search_path', 'public, ' || quote_ident(coalesce(s, 'extensions')), false);
end $$;
select plan(20);

insert into auth.users (id, email, aud, role) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'economy@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;

select pg_temp.as_admin();
select ok((select bool_and(not active) from private.economy_configs), 'economy config disabled by default');
select ok((select bool_and(not enabled) from private.economy_shop_items), 'shop catalog disabled by default');
select ok((select bool_and(rowsecurity) from pg_tables where schemaname = 'private'
  and tablename in ('economy_configs','economy_shop_items','economy_reward_claims','legacy_economy_reviews')),
  'RLS enabled on every new private table');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'no client-callable SECURITY DEFINER function in public');
select ok(has_function_privilege('service_role',
  'public.record_verified_rewarded_claim(uuid,uuid,text,date,smallint,integer)', 'EXECUTE'),
  'service role can record verified rewarded claims');
select ok(not has_function_privilege('authenticated',
  'public.record_verified_rewarded_claim(uuid,uuid,text,date,smallint,integer)', 'EXECUTE'),
  'client cannot self-grant rewarded claims');

select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000001');
select lives_ok($$ select save_profile('{"username":"economy_1","coins":999999}'::jsonb) $$,
  'new player can create a profile');
select is((get_my_profile()->>'coins')::bigint, 999999::bigint,
  'disabled migration preserves the pre-authoritative opening balance');
select is(get_my_economy_state()->>'legacyStatus', 'pending',
  'pre-authoritative opening balance waits for reconciliation');
select throws_ok($$ select claim_daily_economy_reward('10000000-0000-0000-0000-000000000001') $$,
  'P0001', 'economy_disabled', 'claims fail closed before owner activation');

select pg_temp.as_admin();
update private.economy_configs
set active = true, approved_by = 'pgtap', approved_at = now()
where version = 'balanced-premium-rc1';
update private.economy_shop_items set enabled = true where config_version = 'balanced-premium-rc1';
update private.economy
set confirmed_balance = 0, legacy_status = 'accepted'
where user_id = 'bbbbbbbb-0000-0000-0000-000000000001';
update private.profile_data set data = jsonb_set(data, '{coins}', '0'::jsonb)
where id = 'bbbbbbbb-0000-0000-0000-000000000001';

select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000001');
select is((claim_daily_economy_reward('10000000-0000-0000-0000-000000000001')->>'status'),
  'applied', 'daily reward is server-computed after activation');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 10::bigint,
  'day-one Balanced reward credited exactly once');
select throws_ok($$ select claim_daily_economy_reward('10000000-0000-0000-0000-000000000002') $$,
  'P0001', 'already_claimed', 'second daily claim is rejected');
select pg_temp.as_admin();
select is((select count(*)::int from private.economy_events
  where user_id = 'bbbbbbbb-0000-0000-0000-000000000001' and source = 'daily_reward'), 1,
  'daily reward has one ledger event');

update private.economy set confirmed_balance = 300
where user_id = 'bbbbbbbb-0000-0000-0000-000000000001';
update private.profile_data set data = jsonb_set(data, '{coins}', '300'::jsonb)
where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000001');
select is((purchase_economy_item('20000000-0000-0000-0000-000000000001', 'theme_neon')->>'status'),
  'applied', 'shop purchase is atomic');
select is((get_my_economy_state()->>'confirmedBalance')::bigint, 50::bigint,
  'shop purchase debits the configured price');
select ok(get_my_profile()->'owned_items' ? 'theme_neon', 'purchased item granted');
select is((purchase_economy_item('20000000-0000-0000-0000-000000000001', 'theme_neon')->>'status'),
  'already_owned', 'repeat item purchase does not debit again');
select throws_ok($$ select * from private.economy_configs $$, '42501', null,
  'client cannot read private economy configuration directly');
select throws_ok($$ select private.apply_economy_delta(
  'bbbbbbbb-0000-0000-0000-000000000001', gen_random_uuid(), 'cheat', 999999,
  'balanced-premium-rc1', '{}'::jsonb) $$, '42501', null,
  'client cannot call the raw balance mutation');

select * from finish();
rollback;

