-- ============================================================================
-- 1.2.0 — server-side purchase ledger + economy guard on save_profile
-- ============================================================================
-- STATUS: written and tested against the LOCAL stack only (supabase test db).
-- Applying it to production needs owner approval (docs/PAYMENTS_READINESS.he.md).
--
-- What it does
--  * private.iap_products     product catalogue the server will grant (mirrors
--                              PurchaseManager / ShopItem.premium).
--  * private.purchase_ledger  one row per StoreKit transaction (unique id):
--                              idempotent grants, refunds/revocations.
--  * private.economy          server-owned entitlements per player: no_ads,
--                              premium items, IAP coins not yet synced.
--  * save_profile (client path only) no longer trusts the client for:
--      - no_ads            → always the server value
--      - premium skins     → only if the ledger granted them
--      - season_premium    → sticky, or earned (50 rewarded ads) — never just set
--      - coins             → increases above a generous, time-based allowance
--                            plus pending IAP coins are clamped and logged
--    Legacy claim / import paths call save_profile_for directly and are unchanged.
--
-- Data preservation
--  * No existing value is modified: economy rows are backfilled from each
--    player's current no_ads flag; coins, items and progress stay as they are.
-- ============================================================================

create table private.iap_products (
  product_id text primary key,
  kind       text not null check (kind in ('coins', 'remove_ads', 'premium_item')),
  coins      int  check ((kind = 'coins') = (coins is not null and coins > 0)),
  item_id    text check ((kind = 'premium_item') = (item_id is not null))
);
alter table private.iap_products enable row level security;

insert into private.iap_products (product_id, kind, coins, item_id) values
  ('com.perfecttap.coins.500',          'coins',        500,  null),
  ('com.perfecttap.coins.1200',         'coins',        1200, null),
  ('com.perfecttap.coins.3000',         'coins',        3000, null),
  ('com.perfecttap.coins.8000',         'coins',        8000, null),
  ('com.perfecttap.removeads',          'remove_ads',   null, null),
  ('com.perfecttap.skin.neonpulse',     'premium_item', null, 'theme_neonpulse'),
  ('com.perfecttap.skin.liquidchrome',  'premium_item', null, 'theme_chrome'),
  ('com.perfecttap.skin.glitchmode',    'premium_item', null, 'theme_glitch'),
  ('com.perfecttap.skin.cosmicgold',    'premium_item', null, 'theme_cosmicgold');

create table private.purchase_ledger (
  transaction_id          text primary key,
  original_transaction_id text not null,
  user_id                 uuid references auth.users(id) on delete set null,
  product_id              text not null references private.iap_products(product_id),
  environment             text not null check (environment in ('Production', 'Sandbox', 'Xcode', 'LocalTesting')),
  purchased_at            timestamptz not null,
  revoked_at              timestamptz,
  created_at              timestamptz not null default now()
);
create index purchase_ledger_user_idx on private.purchase_ledger (user_id);
alter table private.purchase_ledger enable row level security;

create table private.economy (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  no_ads            boolean not null default false,
  premium_items     text[]  not null default '{}',
  pending_iap_coins bigint  not null default 0 check (pending_iap_coins >= 0),
  updated_at        timestamptz not null default now()
);
alter table private.economy enable row level security;

create table private.economy_events (
  id         bigserial primary key,
  user_id    uuid references auth.users(id) on delete cascade,
  kind       text not null,
  detail     jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index economy_events_user_idx on private.economy_events (user_id, created_at desc);
alter table private.economy_events enable row level security;

-- Backfill: keep every player's current no_ads flag (nothing else changes).
insert into private.economy (user_id, no_ads)
select pd.id, coalesce((pd.data->>'no_ads')::boolean, false)
from private.profile_data pd
join auth.users u on u.id = pd.id
on conflict (user_id) do nothing;

-- Coin allowance per save: 10k + 20k per hour since the last stored save,
-- capped at 500k. Generous for real play (incl. long offline streaks), but a
-- tampered "coins: 99 999 999" is clamped.
create or replace function private.coin_allowance(since timestamptz)
returns bigint language sql stable set search_path = '' as $$
  select least(500000, 10000 + floor(greatest(0, extract(epoch from (now() - coalesce(since, now()))) / 3600.0) * 20000))::bigint
$$;

create or replace function private.sanitize_economy(uid uuid, p jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  stored jsonb;
  stored_at timestamptz;
  e private.economy;
  old_coins bigint;
  new_coins bigint;
  allowed bigint;
  premium_ids text[];
  items jsonb;
  stored_sp boolean;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return p; end if;

  select data, updated_at into stored, stored_at from private.profile_data where id = uid;
  insert into private.economy (user_id) values (uid) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = uid for update;

  -- Coins: decreases (spending) always allowed; increases bounded. Invalid
  -- values (negative, fractional, wrong type) are left for save_profile_for's
  -- validation to reject.
  if jsonb_typeof(p->'coins') = 'number' and (p->>'coins')::numeric >= 0
     and (p->>'coins')::numeric = trunc((p->>'coins')::numeric) then
    new_coins := (p->>'coins')::numeric::bigint;
    old_coins := nullif(stored->>'coins', '')::bigint;
    if old_coins is not null then
      allowed := old_coins + private.coin_allowance(stored_at) + e.pending_iap_coins;
      if new_coins > allowed then
        insert into private.economy_events (user_id, kind, detail)
        values (uid, 'coins_clamped', jsonb_build_object('sent', new_coins, 'kept', allowed, 'previous', old_coins));
        new_coins := allowed;
      end if;
      e.pending_iap_coins := greatest(0, e.pending_iap_coins - greatest(0, new_coins - old_coins));
    end if;
    p := jsonb_set(p, '{coins}', to_jsonb(new_coins));
  end if;

  -- Remove Ads: server-owned (a wrong type is left for validation to reject).
  if jsonb_typeof(p->'no_ads') not in ('boolean', 'null') then return p; end if;
  if p ? 'no_ads' and coalesce((p->>'no_ads')::boolean, false) <> e.no_ads then
    insert into private.economy_events (user_id, kind, detail)
    values (uid, 'no_ads_ignored', jsonb_build_object('sent', p->'no_ads', 'kept', e.no_ads));
  end if;
  p := p || jsonb_build_object('no_ads', e.no_ads);

  -- Premium skins: only ledger-granted ones survive; granted ones are kept
  -- even if the client copy lost them.
  select coalesce(array_agg(item_id), '{}') into premium_ids from private.iap_products where item_id is not null;
  if jsonb_typeof(p->'owned_items') = 'array' then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into items
    from (
      select x from jsonb_array_elements_text(p->'owned_items') as t(x)
      where not (x = any(premium_ids)) or x = any(e.premium_items)
      union
      select unnest(e.premium_items)
    ) s;
    p := jsonb_set(p, '{owned_items}', items);
  end if;

  -- Season premium: sticky once stored, otherwise only with 50 rewarded ads.
  stored_sp := coalesce((stored->>'season_premium')::boolean, false);
  if jsonb_typeof(p->'season_premium') = 'boolean' then
    p := p || jsonb_build_object('season_premium',
      stored_sp or (coalesce((p->>'season_premium')::boolean, false)
                    and coalesce((p->>'season_ad_progress')::numeric, 0) >= 50));
  end if;

  update private.economy set pending_iap_coins = e.pending_iap_coins, updated_at = now() where user_id = uid;
  return p;
end $$;
revoke all on function private.sanitize_economy(uuid, jsonb) from public, anon, authenticated;

-- Client save path (body behind the public.save_profile invoker wrapper).
create or replace function private.save_profile(p jsonb)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid();
begin
  perform private.check_rate(uid, 'save_profile', 120, interval '1 minute');
  perform private.save_profile_for(uid, private.sanitize_economy(uid, p));
end $$;

-- ---------------------------------------------------------------------------
-- Purchase recording (service role only: called by edge functions after the
-- signed transaction was verified with Apple's certificates).
-- ---------------------------------------------------------------------------

create or replace function private.set_profile_item(uid uuid, item text, owned boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update private.profile_data
  set data = case
    when owned then jsonb_set(data, '{owned_items}',
      coalesce(data->'owned_items', '[]'::jsonb) ||
      case when coalesce(data->'owned_items', '[]'::jsonb) ? item then '[]'::jsonb else jsonb_build_array(item) end)
    else jsonb_set(
      jsonb_set(data, '{owned_items}',
        coalesce((select jsonb_agg(x) from jsonb_array_elements_text(coalesce(data->'owned_items', '[]'::jsonb)) t(x) where x <> item), '[]'::jsonb)),
      '{equipped_theme}',
      case when 'theme_' || coalesce(data->>'equipped_theme', '') = item then '"default"'::jsonb
           else coalesce(data->'equipped_theme', '"default"'::jsonb) end)
    end
  where id = uid;
end $$;
revoke all on function private.set_profile_item(uuid, text, boolean) from public, anon, authenticated;

create or replace function private.revoke_purchase(p_transaction_id text, p_revoked_at timestamptz)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  l private.purchase_ledger;
  prod private.iap_products;
  e private.economy;
  debit bigint;
  from_pending bigint;
begin
  select * into l from private.purchase_ledger where transaction_id = p_transaction_id for update;
  if not found then return 'unknown_transaction'; end if;
  if l.revoked_at is not null then return 'already_revoked'; end if;
  update private.purchase_ledger set revoked_at = coalesce(p_revoked_at, now()) where transaction_id = p_transaction_id;
  if l.user_id is null then return 'revoked'; end if;

  select * into prod from private.iap_products where product_id = l.product_id;
  insert into private.economy (user_id) values (l.user_id) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = l.user_id for update;

  if prod.kind = 'coins' then
    -- Not yet synced coins are taken back first, then the stored balance (≥ 0).
    from_pending := least(e.pending_iap_coins, prod.coins);
    debit := prod.coins - from_pending;
    update private.economy set pending_iap_coins = pending_iap_coins - from_pending, updated_at = now()
    where user_id = l.user_id;
    if debit > 0 then
      update private.profile_data
      set data = jsonb_set(data, '{coins}', to_jsonb(greatest(0, coalesce((data->>'coins')::bigint, 0) - debit)))
      where id = l.user_id;
    end if;
  elsif prod.kind = 'remove_ads' then
    if not exists (select 1 from private.purchase_ledger
                   where user_id = l.user_id and product_id = l.product_id and revoked_at is null) then
      update private.economy set no_ads = false, updated_at = now() where user_id = l.user_id;
      update private.profile_data set data = data || '{"no_ads": false}'::jsonb where id = l.user_id;
    end if;
  else
    update private.economy set premium_items = array_remove(premium_items, prod.item_id), updated_at = now()
    where user_id = l.user_id;
    perform private.set_profile_item(l.user_id, prod.item_id, false);
  end if;
  insert into private.economy_events (user_id, kind, detail)
  values (l.user_id, 'purchase_revoked', jsonb_build_object('transaction_id', p_transaction_id, 'product_id', l.product_id));
  return 'revoked';
end $$;
revoke all on function private.revoke_purchase(text, timestamptz) from public, anon, authenticated;

create or replace function private.record_verified_purchase(
  p_user uuid, p_transaction_id text, p_original_transaction_id text, p_product_id text,
  p_environment text, p_purchased_at timestamptz, p_revoked_at timestamptz default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  prod private.iap_products;
  inserted text;
begin
  if p_user is null or coalesce(p_transaction_id, '') = '' then perform private.fail('invalid_payload'); end if;
  select * into prod from private.iap_products where product_id = p_product_id;
  if not found then perform private.fail('unknown_product'); end if;

  insert into private.purchase_ledger
    (transaction_id, original_transaction_id, user_id, product_id, environment, purchased_at)
  values (p_transaction_id, coalesce(nullif(p_original_transaction_id, ''), p_transaction_id), p_user,
          p_product_id, p_environment, coalesce(p_purchased_at, now()))
  on conflict (transaction_id) do nothing
  returning transaction_id into inserted;

  if inserted is null then
    if p_revoked_at is not null then return private.revoke_purchase(p_transaction_id, p_revoked_at); end if;
    return 'already_granted';
  end if;

  if p_revoked_at is not null then
    -- Delivered already revoked (e.g. refunded before the app reported it): record, grant nothing.
    update private.purchase_ledger set revoked_at = p_revoked_at where transaction_id = p_transaction_id;
    return 'revoked';
  end if;

  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  if prod.kind = 'coins' then
    update private.economy set pending_iap_coins = pending_iap_coins + prod.coins, updated_at = now() where user_id = p_user;
  elsif prod.kind = 'remove_ads' then
    update private.economy set no_ads = true, updated_at = now() where user_id = p_user;
    update private.profile_data set data = data || '{"no_ads": true}'::jsonb where id = p_user;
  else
    update private.economy
    set premium_items = case when prod.item_id = any(premium_items) then premium_items else premium_items || prod.item_id end,
        updated_at = now()
    where user_id = p_user;
    perform private.set_profile_item(p_user, prod.item_id, true);
  end if;
  return 'granted';
end $$;
revoke all on function private.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function private.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz) to service_role;
grant execute on function private.revoke_purchase(text, timestamptz) to service_role;

-- Public invoker wrappers so edge functions (service role) can reach them via
-- /rest/v1/rpc. Not executable by anon / authenticated.
create or replace function public.record_verified_purchase(
  p_user uuid, p_transaction_id text, p_original_transaction_id text, p_product_id text,
  p_environment text, p_purchased_at timestamptz, p_revoked_at timestamptz default null)
returns text language sql volatile security invoker set search_path = '' as $$
  select private.record_verified_purchase(p_user, p_transaction_id, p_original_transaction_id, p_product_id,
                                          p_environment, p_purchased_at, p_revoked_at)
$$;
create or replace function public.revoke_purchase(p_transaction_id text, p_revoked_at timestamptz)
returns text language sql volatile security invoker set search_path = '' as $$
  select private.revoke_purchase(p_transaction_id, p_revoked_at)
$$;
revoke all on function public.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke all on function public.revoke_purchase(text, timestamptz) from public, anon, authenticated;
grant execute on function public.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz) to service_role;
grant execute on function public.revoke_purchase(text, timestamptz) to service_role;
grant usage on schema private to service_role;
