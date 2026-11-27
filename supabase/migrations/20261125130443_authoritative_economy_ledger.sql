-- ============================================================================
-- 1.2.0 — authoritative economy ledger (disabled launch candidate)
-- ============================================================================
-- This migration is additive and preserves every existing balance and item.
-- The Balanced Premium config and shop rows are inserted disabled. Production
-- activation is a separate, explicit owner action after reconciliation.

alter table private.economy
  add column confirmed_balance bigint,
  add column coin_debt bigint not null default 0,
  add column config_version text,
  add column legacy_opening_balance bigint,
  add column legacy_status text not null default 'pending';

alter table private.economy
  add constraint economy_coin_debt_nonnegative check (coin_debt >= 0),
  add constraint economy_legacy_status_valid
    check (legacy_status in ('pending', 'accepted', 'review', 'rejected'));

-- Mirror, but do not change, the balance already stored for each player.
update private.economy e
set confirmed_balance = case when pd.data->>'coins' ~ '^[0-9]{1,15}$' then (pd.data->>'coins')::bigint else 0 end,
    legacy_opening_balance = case when pd.data->>'coins' ~ '^[0-9]{1,15}$' then (pd.data->>'coins')::bigint else 0 end
from private.profile_data pd
where pd.id = e.user_id;

update private.economy set confirmed_balance = 0 where confirmed_balance is null;
alter table private.economy
  alter column confirmed_balance set default 0,
  alter column confirmed_balance set not null,
  add constraint economy_confirmed_balance_nonnegative check (confirmed_balance >= 0);

create table private.economy_configs (
  version        text primary key,
  config         jsonb not null check (jsonb_typeof(config) = 'object'),
  active         boolean not null default false,
  approved_by    text,
  approved_at    timestamptz,
  created_at     timestamptz not null default now(),
  check (not active or (approved_by is not null and approved_at is not null))
);
create unique index economy_one_active_config_idx
  on private.economy_configs ((active)) where active;
alter table private.economy_configs enable row level security;

insert into private.economy_configs (version, config) values (
  'balanced-premium-rc1',
  jsonb_build_object(
    'status', 'candidate_not_approved',
    'daily_rewards', jsonb_build_array(10, 15, 20, 25, 30, 40, 60),
    'wheel_rewards', jsonb_build_array(5, 5, 10, 10, 15, 15, 20, 40),
    'quest_rewards', jsonb_build_object('easy', 25, 'medium', 45, 'hard', 75),
    'home_rewarded_coins', 15,
    'season_ads_required', 20,
    'season_coin_cycle', jsonb_build_array(25, 50, 75, 100, 125)
  )
);

create table private.economy_shop_items (
  item_id        text primary key,
  price          int not null check (price > 0),
  config_version text not null references private.economy_configs(version),
  enabled        boolean not null default false,
  created_at     timestamptz not null default now()
);
alter table private.economy_shop_items enable row level security;

insert into private.economy_shop_items (item_id, price, config_version) values
  ('theme_neon',250,'balanced-premium-rc1'), ('theme_fire',600,'balanced-premium-rc1'),
  ('theme_ice',650,'balanced-premium-rc1'), ('theme_gold',1200,'balanced-premium-rc1'),
  ('theme_galaxy',1400,'balanced-premium-rc1'), ('theme_midnight',700,'balanced-premium-rc1'),
  ('theme_sunset',1300,'balanced-premium-rc1'), ('theme_matrix',2500,'balanced-premium-rc1'),
  ('fx_ripple',250,'balanced-premium-rc1'), ('fx_spark',600,'balanced-premium-rc1'),
  ('fx_hearts',550,'balanced-premium-rc1'), ('fx_stars',1200,'balanced-premium-rc1'),
  ('fx_confetti',1100,'balanced-premium-rc1'), ('fx_shatter',2500,'balanced-premium-rc1'),
  ('avatar_cool',250,'balanced-premium-rc1'), ('avatar_ninja',550,'balanced-premium-rc1'),
  ('avatar_robot',600,'balanced-premium-rc1'), ('avatar_alien',1100,'balanced-premium-rc1'),
  ('avatar_wizard',1200,'balanced-premium-rc1'), ('avatar_king',1350,'balanced-premium-rc1'),
  ('avatar_devil',1250,'balanced-premium-rc1'), ('avatar_unicorn',2400,'balanced-premium-rc1'),
  ('avatar_dragon',2800,'balanced-premium-rc1');

alter table private.economy_events
  add column event_key uuid,
  add column source text,
  add column amount bigint,
  add column config_version text references private.economy_configs(version),
  add column metadata jsonb not null default '{}'::jsonb;
create unique index economy_events_idempotency_idx
  on private.economy_events (user_id, event_key) where event_key is not null;

create table private.economy_reward_claims (
  user_id       uuid not null references auth.users(id) on delete cascade,
  source        text not null check (source in ('daily_reward','wheel','home_rewarded','double_coins','revive','season_progress')),
  server_day    date not null,
  claim_index   smallint not null default 1 check (claim_index between 1 and 3),
  event_key     uuid not null,
  created_at    timestamptz not null default now(),
  primary key (user_id, source, server_day, claim_index),
  unique (user_id, event_key)
);
alter table private.economy_reward_claims enable row level security;

create table private.legacy_economy_reviews (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  snapshot            jsonb not null default '{}'::jsonb,
  verified_floor      bigint not null default 0 check (verified_floor >= 0),
  legacy_candidate    bigint not null default 0 check (legacy_candidate >= 0),
  confirmed_balance   bigint not null default 0 check (confirmed_balance >= 0),
  disputed_balance    bigint not null default 0 check (disputed_balance >= 0),
  plausibility_score  numeric,
  status              text not null default 'pending'
                      check (status in ('pending','accepted','review','rejected')),
  reason_code         text,
  reviewed_by         text,
  reviewed_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
alter table private.legacy_economy_reviews enable row level security;

-- A brand-new client profile may not choose its opening balance. The normal
-- save_profile path creates an economy row in sanitize_economy before the
-- profile insert; legacy/import paths do not, so their historical balance is
-- preserved for review instead of being destroyed.
create or replace function private.prepare_new_economy_profile()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from private.economy e
    where e.user_id = new.id and e.legacy_opening_balance is null
  ) and exists (select 1 from private.economy_configs where active) then
    new.data := jsonb_set(new.data, '{coins}', '0'::jsonb);
    update private.economy
    set confirmed_balance = 0, legacy_opening_balance = 0,
        legacy_status = 'accepted', updated_at = now()
    where user_id = new.id;
  end if;
  return new;
end $$;
revoke all on function private.prepare_new_economy_profile() from public, anon, authenticated;

create trigger prepare_new_economy_profile_before_insert
before insert on private.profile_data
for each row execute function private.prepare_new_economy_profile();

create or replace function private.capture_legacy_economy_profile()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare opening bigint := case when new.data->>'coins' ~ '^[0-9]{1,15}$' then (new.data->>'coins')::bigint else 0 end;
        status_value text;
begin
  insert into private.economy
    (user_id, confirmed_balance, legacy_opening_balance, legacy_status)
  values (new.id, opening, opening, 'pending')
  on conflict (user_id) do update
    set confirmed_balance = case
          when private.economy.legacy_opening_balance is null then opening
          else private.economy.confirmed_balance end,
        legacy_opening_balance = coalesce(private.economy.legacy_opening_balance, opening),
        updated_at = now();

  select legacy_status into status_value from private.economy where user_id = new.id;
  insert into private.legacy_economy_reviews
    (user_id, snapshot, verified_floor, legacy_candidate, confirmed_balance,
     disputed_balance, status)
  values (
    new.id,
    jsonb_build_object('captured_at', now(), 'profile_coins', opening,
                       'config_version', 'pre-authoritative'),
    0, opening, opening, 0, status_value
  )
  on conflict (user_id) do nothing;
  return new;
end $$;
revoke all on function private.capture_legacy_economy_profile() from public, anon, authenticated;

create trigger capture_legacy_economy_profile_after_insert
after insert on private.profile_data
for each row execute function private.capture_legacy_economy_profile();

insert into private.legacy_economy_reviews
  (user_id, snapshot, verified_floor, legacy_candidate, confirmed_balance, disputed_balance)
select e.user_id,
       jsonb_build_object(
         'captured_at', now(),
         'profile_coins', e.legacy_opening_balance,
         'config_version', 'pre-authoritative'
       ),
       0,
       e.legacy_opening_balance,
       e.confirmed_balance,
       0
from private.economy e
on conflict (user_id) do nothing;

create or replace function private.require_active_economy()
returns private.economy_configs
language plpgsql stable security definer set search_path = '' as $$
declare cfg private.economy_configs;
begin
  select * into cfg from private.economy_configs where active;
  if not found then perform private.fail('economy_disabled'); end if;
  return cfg;
end $$;
revoke all on function private.require_active_economy() from public, anon, authenticated;

create or replace function private.apply_economy_delta(
  p_user uuid, p_event_key uuid, p_source text, p_amount bigint,
  p_config_version text, p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e private.economy; existing private.economy_events;
begin
  if p_user is null or p_event_key is null or coalesce(p_source, '') = '' or p_amount = 0 then
    perform private.fail('invalid_payload');
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' or pg_column_size(p_metadata) > 4096 then
    perform private.fail('invalid_metadata');
  end if;

  select * into existing from private.economy_events
  where user_id = p_user and event_key = p_event_key;
  if found then
    select * into e from private.economy where user_id = p_user;
    return jsonb_build_object('status','duplicate','balance',e.confirmed_balance,'coinDebt',e.coin_debt);
  end if;

  insert into private.economy (user_id, confirmed_balance, legacy_opening_balance)
  values (p_user, 0, 0) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;
  if e.legacy_status <> 'accepted' then perform private.fail('legacy_review_required'); end if;
  if e.confirmed_balance + p_amount < 0 then perform private.fail('insufficient_coins'); end if;

  update private.economy
  set confirmed_balance = confirmed_balance + p_amount,
      config_version = p_config_version,
      updated_at = now()
  where user_id = p_user
  returning * into e;

  update private.profile_data
  set data = jsonb_set(data, '{coins}', to_jsonb(e.confirmed_balance)), updated_at = now()
  where id = p_user;

  insert into private.economy_events
    (user_id, kind, detail, event_key, source, amount, config_version, metadata)
  values
    (p_user, 'ledger_delta', '{}'::jsonb, p_event_key, p_source, p_amount, p_config_version, p_metadata);

  return jsonb_build_object('status','applied','balance',e.confirmed_balance,'coinDebt',e.coin_debt);
end $$;
revoke all on function private.apply_economy_delta(uuid, uuid, text, bigint, text, jsonb)
  from public, anon, authenticated;

create or replace function private.claim_daily_reward(p_user uuid, p_event_key uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; e private.economy; pd private.profile_data;
        today date := (now() at time zone 'utc')::date; last_day date; streak int; reward int;
begin
  cfg := private.require_active_economy();
  perform private.check_rate(p_user, 'economy_daily_reward', 10, interval '1 hour');
  select * into pd from private.profile_data where id = p_user for update;
  if not found then perform private.fail('profile_required'); end if;
  last_day := nullif(pd.data->>'daily_reward_last_claim','')::date;
  if last_day = today then perform private.fail('already_claimed'); end if;
  streak := case when last_day = today - 1 then coalesce((pd.data->>'daily_reward_streak')::int,0) else 0 end;
  reward := ((cfg.config->'daily_rewards')->>(streak % 7))::int;

  insert into private.economy_reward_claims (user_id, source, server_day, event_key)
  values (p_user, 'daily_reward', today, p_event_key);
  update private.profile_data set data = data || jsonb_build_object(
    'daily_reward_last_claim', today::text,
    'daily_reward_streak', streak + 1
  ) where id = p_user;
  return private.apply_economy_delta(p_user, p_event_key, 'daily_reward', reward, cfg.version,
    jsonb_build_object('server_day', today, 'streak', streak + 1));
exception when unique_violation then
  perform private.fail('already_claimed');
end $$;
revoke all on function private.claim_daily_reward(uuid, uuid) from public, anon, authenticated;

create or replace function private.claim_daily_economy_reward(p_event_key uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid();
begin
  return private.claim_daily_reward(uid, p_event_key);
end $$;
revoke all on function private.claim_daily_economy_reward(uuid) from public, anon;

create or replace function public.claim_daily_economy_reward(p_event_key uuid)
returns jsonb
language sql volatile security invoker set search_path = '' as $$
  select private.claim_daily_economy_reward(p_event_key)
$$;
revoke all on function public.claim_daily_economy_reward(uuid) from public, anon;
grant execute on function private.claim_daily_economy_reward(uuid),
  public.claim_daily_economy_reward(uuid) to authenticated;

create or replace function private.purchase_economy_item(p_user uuid, p_event_key uuid, p_item_id text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; item private.economy_shop_items; pd private.profile_data; out jsonb;
begin
  cfg := private.require_active_economy();
  perform private.check_rate(p_user, 'economy_shop_purchase', 30, interval '1 minute');
  select * into item from private.economy_shop_items
  where item_id = p_item_id and enabled and config_version = cfg.version;
  if not found then perform private.fail('item_unavailable'); end if;
  select * into pd from private.profile_data where id = p_user for update;
  if coalesce(pd.data->'owned_items','[]'::jsonb) ? p_item_id then
    return jsonb_build_object('status','already_owned');
  end if;
  out := private.apply_economy_delta(p_user, p_event_key, 'shop_purchase', -item.price,
    cfg.version, jsonb_build_object('item_id', p_item_id));
  perform private.set_profile_item(p_user, p_item_id, true);
  return out || jsonb_build_object('itemID', p_item_id);
end $$;
revoke all on function private.purchase_economy_item(uuid, uuid, text) from public, anon, authenticated;

create or replace function private.purchase_economy_item_for_caller(p_event_key uuid, p_item_id text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid();
begin
  return private.purchase_economy_item(uid, p_event_key, p_item_id);
end $$;
revoke all on function private.purchase_economy_item_for_caller(uuid, text) from public, anon;

create or replace function public.purchase_economy_item(p_event_key uuid, p_item_id text)
returns jsonb
language sql volatile security invoker set search_path = '' as $$
  select private.purchase_economy_item_for_caller(p_event_key, p_item_id)
$$;
revoke all on function public.purchase_economy_item(uuid, text) from public, anon;
grant execute on function private.purchase_economy_item_for_caller(uuid, text),
  public.purchase_economy_item(uuid, text) to authenticated;

-- Rewarded-ad grants remain service-role only until the ad provider's SSV/token
-- is wired. The iOS client cannot call this function or choose its own amount.
create or replace function public.record_verified_rewarded_claim(
  p_user uuid, p_event_key uuid, p_source text, p_server_day date,
  p_claim_index smallint, p_amount int)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; max_claims int;
begin
  cfg := private.require_active_economy();
  if p_source not in ('home_rewarded','double_coins','revive','season_progress') then
    perform private.fail('invalid_source');
  end if;
  max_claims := case when p_source = 'revive' then 3 else 1 end;
  if p_claim_index not between 1 and max_claims then perform private.fail('claim_limit'); end if;
  if p_server_day <> (now() at time zone 'utc')::date then perform private.fail('wrong_day'); end if;
  insert into private.economy_reward_claims (user_id, source, server_day, claim_index, event_key)
  values (p_user, p_source, p_server_day, p_claim_index, p_event_key);
  if p_amount = 0 then return jsonb_build_object('status','recorded'); end if;
  return private.apply_economy_delta(p_user, p_event_key, p_source, p_amount, cfg.version,
    jsonb_build_object('server_day', p_server_day, 'claim_index', p_claim_index));
exception when unique_violation then
  perform private.fail('already_claimed');
end $$;
revoke all on function public.record_verified_rewarded_claim(uuid, uuid, text, date, smallint, int)
  from public, anon, authenticated;
grant execute on function public.record_verified_rewarded_claim(uuid, uuid, text, date, smallint, int)
  to service_role;

create or replace function private.get_my_economy_state()
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); e private.economy; r private.legacy_economy_reviews;
begin
  select * into e from private.economy where user_id = uid;
  select * into r from private.legacy_economy_reviews where user_id = uid;
  return jsonb_build_object(
    'confirmedBalance', coalesce(e.confirmed_balance,0),
    'coinDebt', coalesce(e.coin_debt,0),
    'configVersion', e.config_version,
    'legacyStatus', coalesce(e.legacy_status,'pending'),
    'disputedBalance', coalesce(r.disputed_balance,0)
  );
end $$;
revoke all on function private.get_my_economy_state() from public, anon;

create or replace function public.get_my_economy_state()
returns jsonb
language sql stable security invoker set search_path = '' as $$
  select private.get_my_economy_state()
$$;
revoke all on function public.get_my_economy_state() from public, anon;
grant execute on function private.get_my_economy_state(), public.get_my_economy_state()
  to authenticated;

-- Explicit grants only. Private tables have RLS and no client table grants.
revoke all on table private.economy_configs, private.economy_shop_items,
  private.economy_reward_claims, private.legacy_economy_reviews
  from public, anon, authenticated;
grant usage on schema private to service_role;
