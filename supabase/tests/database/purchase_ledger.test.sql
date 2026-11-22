-- pgTAP: purchase ledger + economy guard (1.2.0). Run: supabase test db --local
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
  ('aaaaaaaa-0000-0000-0000-000000000001', 'buyer@test.local', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'other@test.local', 'authenticated', 'authenticated');

create function pg_temp.as_user(uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  select set_config('role', 'authenticated', true);
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select set_config('role', 'postgres', true);
  select set_config('request.jwt.claims', '', true);
$$;
create function pg_temp.data(uid uuid) returns jsonb language sql as $$
  select data from private.profile_data where id = uid
$$;

-- Existing player with a balance, an item and Remove Ads from before 1.2.0.
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.save_profile('{"username":"buyer_1","coins":1200,"owned_items":["theme_fire"],"no_ads":false,"season_premium":false,"season_ad_progress":3}'::jsonb);
select pg_temp.as_admin();

-- ---------- privileges ----------
select ok(not has_function_privilege('authenticated', 'public.record_verified_purchase(uuid,text,text,text,text,timestamptz,timestamptz)', 'EXECUTE'),
  'players cannot record purchases');
select ok(not has_function_privilege('anon', 'public.revoke_purchase(text,timestamptz)', 'EXECUTE'),
  'anon cannot revoke purchases');
select ok(has_function_privilege('service_role', 'public.record_verified_purchase(uuid,text,text,text,text,timestamptz,timestamptz)', 'EXECUTE'),
  'service role (edge function) can record purchases');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE')), 0,
  'still no SECURITY DEFINER function callable by players in public');
select ok((select bool_and(rowsecurity) from pg_tables where schemaname = 'private'
           and tablename in ('purchase_ledger','economy','economy_events','iap_products')), 'RLS on new tables');

-- ---------- save_profile guard ----------
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.save_profile('{"coins":99999999,"no_ads":true,"owned_items":["theme_fire","theme_glitch"],"season_premium":true,"season_ad_progress":3}'::jsonb);
select pg_temp.as_admin();
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'coins')::bigint, 11200::bigint,
  'tampered coin jump is clamped to previous + allowance (1200 + 10000)');
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'no_ads')::boolean, false, 'client cannot switch on Remove Ads');
select is(pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->'owned_items', '["theme_fire"]'::jsonb,
  'unpaid premium skin is dropped, coin item kept');
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'season_premium')::boolean, false,
  'season premium needs 50 rewarded ads');
select is((select count(*)::int from private.economy_events where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and kind = 'coins_clamped'), 1,
  'clamp is logged for review');

select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.save_profile('{"coins":11000,"season_premium":true,"season_ad_progress":50}'::jsonb);
select pg_temp.as_admin();
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'coins')::bigint, 11000::bigint, 'spending is always allowed');
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'season_premium')::boolean, true, 'earned season premium is kept');

-- ---------- purchases ----------
select is(public.record_verified_purchase('aaaaaaaa-0000-0000-0000-000000000001', 't-1', 't-1', 'com.perfecttap.coins.8000', 'Sandbox', now()),
  'granted', 'coin pack granted');
select is(public.record_verified_purchase('aaaaaaaa-0000-0000-0000-000000000001', 't-1', 't-1', 'com.perfecttap.coins.8000', 'Sandbox', now()),
  'already_granted', 'same transaction is granted once');
select is((select pending_iap_coins from private.economy where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 8000::bigint,
  'coins wait for the next save');

select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.save_profile('{"coins":29000}'::jsonb);   -- 11000 + 8000 IAP + 10000 allowance
select pg_temp.as_admin();
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'coins')::bigint, 29000::bigint,
  'IAP coins raise the allowance');
select is((select pending_iap_coins from private.economy where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0::bigint,
  'pending IAP coins consumed by the save');

select is(public.record_verified_purchase('aaaaaaaa-0000-0000-0000-000000000001', 't-2', 't-2', 'com.perfecttap.skin.glitchmode', 'Sandbox', now()),
  'granted', 'premium skin granted');
select ok(pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->'owned_items' ? 'theme_glitch', 'skin added to the stored profile');
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.save_profile('{"coins":29000,"owned_items":["theme_fire"],"equipped_theme":"glitch"}'::jsonb);   -- stale client copy
select pg_temp.as_admin();
select ok(pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->'owned_items' ? 'theme_glitch', 'a stale client save cannot lose a paid skin');

select is(public.record_verified_purchase('aaaaaaaa-0000-0000-0000-000000000001', 't-3', 't-3', 'com.perfecttap.removeads', 'Sandbox', now()),
  'granted', 'remove ads granted');
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'no_ads')::boolean, true, 'no_ads set server-side');

-- ---------- refunds ----------
select is(public.revoke_purchase('t-2', now()), 'revoked', 'skin refund recorded');
select ok(not (pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->'owned_items' ? 'theme_glitch')
          and pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'equipped_theme' = 'default',
  'refunded skin removed and unequipped');
select is(public.revoke_purchase('t-2', now()), 'already_revoked', 'refund applied once');
select is(public.revoke_purchase('t-1', now()), 'revoked', 'coin refund recorded');
select is((pg_temp.data('aaaaaaaa-0000-0000-0000-000000000001')->>'coins')::bigint, 21000::bigint,
  'refunded coins debited (29000 - 8000), never below zero');

select * from finish();
rollback;
