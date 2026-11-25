-- ============================================================================
-- 1.2.0 — authoritative economy: every coin source (contract v1)
-- ============================================================================
-- Implements docs/ECONOMY_SERVICE_CONTRACT.md on top of
-- 20261125130443_authoritative_economy_ledger.sql. Additive only:
--   * public.submit_economy_event(event_key, source, payload)   (client RPC)
--   * service-role record_verified_rewarded_claim (AdMob SSV, no amount arg)
--   * StoreKit coin credits / refunds through the ledger when a config is active
--   * save_profile pins coins + server-owned items when a config is active
--   * private.reconcile_legacy_economy(dry_run)                 (service role)
--   * balanced-premium-rc1 config gets every reward table (stays INACTIVE)
--
-- Behaviour while NO economy config is active (= production today) is
-- unchanged: sanitize_economy dispatches to the previous body verbatim, and the
-- purchase functions keep their pending_iap_coins path byte-for-byte.
-- No balance, item or ledger row is modified by this migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Deterministic event key for server-originated events (e.g. one StoreKit
-- transaction ⇒ one ledger key). md5-based UUID; namespaced so it can never
-- collide with a client-generated v4 key by accident.
create or replace function private.deterministic_uuid(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select md5('perfecttap-economy:' || p_name)::uuid
$$;
revoke all on function private.deterministic_uuid(text) from public, anon, authenticated;

create or replace function private.payload_int(p jsonb, k text, lo bigint, hi bigint)
returns bigint language plpgsql immutable set search_path = '' as $$
declare v jsonb := p->k; n numeric;
begin
  if v is null or jsonb_typeof(v) <> 'number' then perform private.fail('invalid_payload'); end if;
  n := (v #>> '{}')::numeric;
  if n <> trunc(n) or n < lo or n > hi then perform private.fail('invalid_payload'); end if;
  return n::bigint;
end $$;
revoke all on function private.payload_int(jsonb, text, bigint, bigint) from public, anon, authenticated;

create or replace function private.payload_text(p jsonb, k text, pattern text)
returns text language plpgsql immutable set search_path = '' as $$
declare v jsonb := p->k;
begin
  if v is null or jsonb_typeof(v) <> 'string' or (v #>> '{}') !~ pattern then
    perform private.fail('invalid_payload');
  end if;
  return v #>> '{}';
end $$;
revoke all on function private.payload_text(jsonb, text, text) from public, anon, authenticated;

create or replace function private.payload_uuid(p jsonb, k text)
returns uuid language plpgsql immutable set search_path = '' as $$
begin
  return private.payload_text(p, k,
    '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')::uuid;
end $$;
revoke all on function private.payload_uuid(jsonb, text) from public, anon, authenticated;

create or replace function private.payload_timestamptz(p jsonb, k text)
returns timestamptz language plpgsql stable set search_path = '' as $$
declare s text := private.payload_text(p, k, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:?\d{2})$');
begin
  return s::timestamptz;
exception when others then
  perform private.fail('invalid_payload');
end $$;
revoke all on function private.payload_timestamptz(jsonb, text) from public, anon, authenticated;

-- Port of EconomyConfig.gameCoins: max(minimum, score/divisor + combo + mode).
create or replace function private.economy_game_coins(c jsonb, p_mode text, p_score bigint, p_max_combo bigint)
returns bigint language plpgsql immutable set search_path = '' as $$
declare base bigint; combo bigint := 0; tier jsonb;
begin
  base := greatest(0, p_score) / greatest(1, (c->>'score_coin_divisor')::bigint);
  for tier in select value from jsonb_array_elements(coalesce(c->'combo_bonus', '[]'::jsonb)) loop
    if p_max_combo >= (tier->>'min')::bigint then combo := greatest(combo, (tier->>'coins')::bigint); end if;
  end loop;
  return greatest(coalesce((c->>'minimum_game_coins')::bigint, 0),
                  base + combo + coalesce((c->'mode_bonus'->>p_mode)::bigint, 0));
end $$;
revoke all on function private.economy_game_coins(jsonb, text, bigint, bigint) from public, anon, authenticated;

-- Items that only the server may add to owned_items while a config is active
-- (sold for coins, starter picks, challenge / season premium rewards).
create or replace function private.server_owned_items(cfg private.economy_configs)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct x), '{}') from (
    select item_id as x from private.economy_shop_items where config_version = cfg.version
    union all
    select jsonb_array_elements_text(coalesce(cfg.config->'starter_items', '[]'::jsonb))
    union all
    select value->>'item' from jsonb_each(coalesce(cfg.config->'challenge_rewards', '{}'::jsonb))
    union all
    select value #>> '{}' from jsonb_each(coalesce(cfg.config->'season_premium_items', '{}'::jsonb))
  ) s where x is not null and x <> ''
$$;
revoke all on function private.server_owned_items(private.economy_configs) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Config: every reward table the server needs (candidate, still INACTIVE).
-- Values mirror ios/PerfectTap (EconomyConfig.balancedPremiumRC1,
-- Achievement.all, Challenge.all, DailyQuest pool, SeasonTier.season1Tiers,
-- TutorialView.starterItems). Never touches an active row.
-- ---------------------------------------------------------------------------
update private.economy_configs
set config = config || jsonb_build_object(
  'score_coin_divisor', 80,
  'minimum_game_coins', 4,
  'combo_bonus', jsonb_build_array(
    jsonb_build_object('min', 20, 'coins', 8),
    jsonb_build_object('min', 10, 'coins', 5),
    jsonb_build_object('min', 5,  'coins', 3),
    jsonb_build_object('min', 0,  'coins', 1)),
  -- Modes that earn coins. `duel` is paid through the `duel` source only.
  'mode_bonus', jsonb_build_object('classic', 2, 'duel', 6),
  'gameplay_daily_cap', 1500,
  'gameplay_max_age_hours', 72,
  'gameplay_clock_skew_seconds', 300,
  'quest_daily_limit', 3,
  'quest_difficulties', jsonb_build_object(
    'q_games_3', 'easy', 'q_games_5', 'easy', 'q_score_500', 'easy',
    'q_score_1000', 'medium', 'q_score_2000', 'hard', 'q_combo_10', 'easy',
    'q_combo_20', 'medium', 'q_combo_30', 'hard', 'q_coins_100', 'easy',
    'q_perfect_20', 'medium', 'q_duel_1', 'medium', 'q_sudden_300', 'hard'),
  'achievement_rewards', jsonb_build_object(
    'games_1', 25, 'games_10', 50, 'games_50', 150, 'games_100', 300,
    'games_500', 1000, 'games_1000', 2500,
    'score_500', 50, 'score_1000', 100, 'score_2000', 250, 'score_5000', 500,
    'combo_10', 50, 'combo_20', 150, 'combo_50', 500,
    'duel_1', 50, 'duel_10', 300, 'duel_50', 1000,
    'coins_1000', 100, 'coins_10000', 500,
    'perfect_100', 100, 'perfect_1000', 500,
    'streak_7', 200, 'streak_30', 1000,
    'score_10000', 1000, 'combo_100', 1000,
    'coins_50000', 1000, 'coins_100000', 2500,
    'perfect_5000', 500, 'perfect_10000', 1000,
    'sudden_500', 300, 'sudden_1000', 750, 'timed_3000', 500, 'endless_5000', 500,
    'games_2500', 2000, 'games_5000', 5000, 'duel_100', 2000, 'first_combo_5', 25),
  'challenge_rewards', jsonb_build_object(
    'c1',  jsonb_build_object('coins', 50,  'item', null),
    'c2',  jsonb_build_object('coins', 100, 'item', null),
    'c3',  jsonb_build_object('coins', 200, 'item', null),
    'c4',  jsonb_build_object('coins', 500, 'item', null),
    'c5',  jsonb_build_object('coins', 75,  'item', null),
    'c6',  jsonb_build_object('coins', 300, 'item', null),
    'c7',  jsonb_build_object('coins', 150, 'item', null),
    'c8',  jsonb_build_object('coins', 400, 'item', null),
    'c9',  jsonb_build_object('coins', 0,   'item', 'theme_fire'),
    'c10', jsonb_build_object('coins', 250, 'item', null)),
  'starter_items', jsonb_build_array('theme_neon', 'fx_ripple', 'avatar_cool'),
  'season_premium_items', jsonb_build_object(
    '1', 'avatar_cool', '3', 'theme_neon', '5', 'avatar_robot', '7', 'theme_fire',
    '10', 'avatar_alien', '15', 'theme_galaxy', '20', 'avatar_dragon',
    '25', 'badge_neon', '30', 'avatar_king'),
  -- Dates are placeholders pending the owner's season calendar.
  'active_season', jsonb_build_object(
    'id', 'season_1_neon_nights',
    'starts_at', '2026-12-01T00:00:00Z',
    'ends_at', '2027-03-01T00:00:00Z',
    'tiers', 30,
    'max_tiers_per_day', 15)
)
where version = 'balanced-premium-rc1' and not active;

-- ---------------------------------------------------------------------------
-- Grants ledger: one row per "once per X" reward (uniqueness + caps). The coin
-- movement itself is always private.economy_events via apply_economy_delta.
-- ---------------------------------------------------------------------------
create table private.economy_grants (
  user_id     uuid not null references auth.users(id) on delete cascade,
  source      text not null check (source in ('gameplay','duel','quest','achievement','challenge',
                                              'season_tier','wheel','starter_item','double_coins')),
  grant_key   text not null check (char_length(grant_key) between 1 and 200),
  server_day  date not null,
  event_key   uuid not null,
  amount      bigint not null default 0 check (amount >= 0),
  capped      bigint not null default 0 check (capped >= 0),
  item_id     text,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  primary key (user_id, source, grant_key),
  unique (user_id, event_key)
);
create index economy_grants_daily_idx on private.economy_grants (user_id, source, server_day);
alter table private.economy_grants enable row level security;

-- One AdMob rewarded impression (SSV transaction_id) credits one user, once.
create table private.rewarded_ad_receipts (
  ad_transaction_id text primary key check (char_length(ad_transaction_id) between 1 and 128),
  user_id           uuid not null references auth.users(id) on delete cascade,
  event_key         uuid not null,
  source            text not null,
  created_at        timestamptz not null default now()
);
alter table private.rewarded_ad_receipts enable row level security;

-- A StoreKit transaction's coin credit key is globally unique: even a bug that
-- reached apply_economy_delta for a second user would hit this index.
create unique index economy_events_iap_credit_once_idx
  on private.economy_events (event_key) where source = 'iap_coins';

revoke all on table private.economy_grants, private.rewarded_ad_receipts
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- apply_economy_delta: same contract, two changes.
--  1. Paid-money sources (iap_coins / iap_revoke / iap_reinstate) bypass the
--     legacy_status gate: legacy status only governs the opening balance.
--  2. For a not-yet-accepted account the profile balance is moved by the delta
--     (never overwritten with confirmed_balance), so an unreconciled legacy
--     balance is never silently reduced.
--  It also no longer pre-creates an economy row with legacy_opening_balance 0
--  (that would make a later brand-new profile look like a legacy one).
-- ---------------------------------------------------------------------------
create or replace function private.apply_economy_delta(
  p_user uuid, p_event_key uuid, p_source text, p_amount bigint,
  p_config_version text, p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e private.economy; existing private.economy_events;
        paid boolean := p_source in ('iap_coins', 'iap_revoke', 'iap_reinstate');
begin
  if p_user is null or p_event_key is null or coalesce(p_source, '') = '' or p_amount is null or p_amount = 0 then
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

  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;
  if e.legacy_status <> 'accepted' and not paid then perform private.fail('legacy_review_required'); end if;
  if e.confirmed_balance + p_amount < 0 then perform private.fail('insufficient_coins'); end if;

  update private.economy
  set confirmed_balance = confirmed_balance + p_amount,
      config_version = p_config_version,
      updated_at = now()
  where user_id = p_user
  returning * into e;

  if e.legacy_status = 'accepted' then
    update private.profile_data
    set data = jsonb_set(data, '{coins}', to_jsonb(e.confirmed_balance)), updated_at = now()
    where id = p_user;
  else
    update private.profile_data
    set data = jsonb_set(data, '{coins}', to_jsonb(greatest(0,
          case when data->>'coins' ~ '^[0-9]{1,15}$' then (data->>'coins')::bigint else 0 end + p_amount))),
        updated_at = now()
    where id = p_user;
  end if;

  insert into private.economy_events
    (user_id, kind, detail, event_key, source, amount, config_version, metadata)
  values
    (p_user, 'ledger_delta', '{}'::jsonb, p_event_key, p_source, p_amount, p_config_version, p_metadata);

  return jsonb_build_object('status','applied','balance',e.confirmed_balance,'coinDebt',e.coin_debt);
end $$;
revoke all on function private.apply_economy_delta(uuid, uuid, text, bigint, text, jsonb)
  from public, anon, authenticated;

-- Zero-coin ledger record (fully capped grant, item-only grant, revive …):
-- reserves the event key and keeps the audit trail complete.
create or replace function private.record_economy_event(
  p_user uuid, p_event_key uuid, p_source text, p_config_version text, p_metadata jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into private.economy_events (user_id, kind, detail, event_key, source, amount, config_version, metadata)
  values (p_user, 'ledger_record', '{}'::jsonb, p_event_key, p_source, 0, p_config_version, coalesce(p_metadata, '{}'::jsonb))
$$;
revoke all on function private.record_economy_event(uuid, uuid, text, text, jsonb) from public, anon, authenticated;

-- A brand-new profile created while a config is active starts from its
-- verified ledger credits (e.g. a coin pack bought before the first save),
-- never from a client-chosen balance — and never loses those paid credits.
create or replace function private.prepare_new_economy_profile()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare e private.economy;
begin
  select * into e from private.economy where user_id = new.id;
  if found and e.legacy_opening_balance is null
     and exists (select 1 from private.economy_configs where active) then
    new.data := jsonb_set(new.data, '{coins}', to_jsonb(e.confirmed_balance));
    update private.economy
    set legacy_opening_balance = 0, legacy_status = 'accepted', updated_at = now()
    where user_id = new.id;
  end if;
  return new;
end $$;
revoke all on function private.prepare_new_economy_profile() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- submit_economy_event — every client-reported coin source.
-- ---------------------------------------------------------------------------
create or replace function private.submit_economy_event_for(
  p_user uuid, p_event_key uuid, p_source text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cfg private.economy_configs;
  c jsonb;
  e private.economy;
  pd private.profile_data;
  g private.economy_grants;
  d public.duels;
  gs private.game_sessions;
  today date := (now() at time zone 'utc')::date;
  p jsonb := coalesce(p_payload, '{}'::jsonb);
  v_key text;
  grant_day date := today;
  coins bigint := 0;
  granted bigint := 0;
  capped bigint := 0;
  item text;
  premium_item text;
  seg int;
  meta jsonb := '{}'::jsonb;
  out jsonb;
  status text;
  -- per-source scratch
  v_mode text; v_score bigint; v_combo bigint; v_taps bigint; v_perfects bigint; v_duration bigint;
  v_played timestamptz; v_session uuid; v_elapsed numeric; v_verdict text;
  v_id text; v_day date; v_tier bigint; v_reward jsonb; v_season jsonb; v_days bigint;
  v_used bigint; v_count int; v_premium boolean;
begin
  cfg := private.require_active_economy();
  c := cfg.config;
  if p_event_key is null or p_source is null
     or p_source not in ('gameplay','duel','quest','achievement','challenge','season_tier','wheel','starter_item')
     or jsonb_typeof(p) <> 'object' or octet_length(p::text) > 2048 then
    perform private.fail('invalid_payload');
  end if;
  perform private.check_rate(p_user, 'economy_event', 120, interval '1 minute');

  if not exists (select 1 from private.profile_data where id = p_user) then
    perform private.fail('profile_required');
  end if;
  -- Serialise every economy write of this player (caps, uniqueness, balance).
  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;
  select * into pd from private.profile_data where id = p_user;

  -- Idempotency: the same event_key always answers `duplicate`.
  select * into g from private.economy_grants where user_id = p_user and event_key = p_event_key;
  if found then
    return jsonb_strip_nulls(jsonb_build_object(
      'status', 'duplicate', 'granted', g.amount, 'balance', e.confirmed_balance, 'coinDebt', e.coin_debt,
      'segmentIndex', (g.metadata->>'segment_index')::int, 'itemID', g.item_id));
  end if;
  if exists (select 1 from private.economy_events where user_id = p_user and event_key = p_event_key) then
    return jsonb_build_object('status','duplicate','granted',0,'balance',e.confirmed_balance,'coinDebt',e.coin_debt);
  end if;
  if e.legacy_status <> 'accepted' then perform private.fail('legacy_review_required'); end if;

  case p_source
  when 'gameplay' then
    v_mode := private.payload_text(p, 'mode', '^[a-z_]{1,32}$');
    if v_mode = 'duel' or not coalesce(c->'mode_bonus', '{}'::jsonb) ? v_mode then
      perform private.fail('invalid_payload');      -- mode does not earn coins
    end if;
    v_score    := private.payload_int(p, 'score', 0, private.max_score());
    v_combo    := private.payload_int(p, 'max_combo', 0, 1000000);
    v_perfects := private.payload_int(p, 'perfects', 0, 1000000);
    v_taps     := private.payload_int(p, 'taps', 0, 1000000);
    v_duration := private.payload_int(p, 'duration_ms', 1, 7200000);
    v_played   := private.payload_timestamptz(p, 'played_at');
    v_session  := private.payload_uuid(p, 'session_id');
    if v_played > now() + make_interval(secs => coalesce((c->>'gameplay_clock_skew_seconds')::int, 300))
       or v_played < now() - make_interval(hours => coalesce((c->>'gameplay_max_age_hours')::int, 72)) then
      perform private.fail('implausible_result');
    end if;
    v_elapsed := v_duration / 1000.0;
    -- A server-timed session with this id (start_game_session) tightens the bound.
    select * into gs from private.game_sessions where id = v_session and user_id = p_user;
    if found then
      if gs.mode <> v_mode then perform private.fail('implausible_result'); end if;
      v_elapsed := least(v_elapsed, extract(epoch from now() - gs.started_at));
    end if;
    v_verdict := private.check_plausibility(v_mode, v_score::int, v_combo::int, v_taps::int,
                                            v_perfects::int, v_elapsed, false);
    if v_verdict is not null then
      raise log 'submit_economy_event gameplay rejected uid=% reason=%', p_user, v_verdict;
      perform private.fail('implausible_result');
    end if;
    coins := private.economy_game_coins(c, v_mode, v_score, v_combo);
    v_key := 'gameplay:' || v_session::text;
    meta := jsonb_build_object('mode', v_mode, 'score', v_score, 'max_combo', v_combo,
                               'session_id', v_session, 'played_at', v_played);

  when 'duel' then
    select * into d from public.duels where id = private.payload_uuid(p, 'duel_id');
    if not found or (p_user is distinct from d.host_id and p_user is distinct from d.guest_id) then
      perform private.fail('duel_not_found');
    end if;
    if p_user = d.host_id then
      v_score := d.host_score; v_combo := d.host_combo; v_played := d.host_submitted_at;
    else
      v_score := d.guest_score; v_combo := d.guest_combo; v_played := d.guest_submitted_at;
    end if;
    if v_score is null then perform private.fail('duel_score_pending'); end if;
    if v_played < now() - make_interval(hours => coalesce((c->>'gameplay_max_age_hours')::int, 72)) then
      perform private.fail('implausible_result');
    end if;
    coins := private.economy_game_coins(c, 'duel', v_score, coalesce(v_combo, 0));
    v_key := 'duel:' || d.id::text;
    meta := jsonb_build_object('duel_id', d.id, 'score', v_score, 'max_combo', v_combo);

  when 'quest' then
    v_id := private.payload_text(p, 'quest_id', '^[a-z0-9_]{1,48}$');
    v_mode := private.payload_text(p, 'difficulty', '^(easy|medium|hard)$');
    v_day := private.payload_text(p, 'server_day', '^\d{4}-\d{2}-\d{2}$')::date;
    if v_day not in (today, today - 1) then perform private.fail('invalid_payload'); end if;
    if c ? 'quest_difficulties' and (c->'quest_difficulties'->>v_id) is distinct from v_mode then
      perform private.fail('invalid_payload');
    end if;
    coins := (c->'quest_rewards'->>v_mode)::bigint;
    if coins is null then perform private.fail('invalid_payload'); end if;
    v_key := 'quest:' || v_day::text || ':' || v_id;
    grant_day := v_day;
    meta := jsonb_build_object('quest_id', v_id, 'difficulty', v_mode, 'server_day', v_day);

  when 'achievement' then
    v_id := private.payload_text(p, 'achievement_id', '^[a-z0-9_]{1,48}$');
    coins := (c->'achievement_rewards'->>v_id)::bigint;
    if coins is null then perform private.fail('invalid_payload'); end if;
    v_key := 'achievement:' || v_id;
    meta := jsonb_build_object('achievement_id', v_id);

  when 'challenge' then
    v_id := private.payload_text(p, 'challenge_id', '^[a-z0-9_]{1,48}$');
    v_reward := c->'challenge_rewards'->v_id;
    if v_reward is null or jsonb_typeof(v_reward) <> 'object' then perform private.fail('invalid_payload'); end if;
    coins := coalesce((v_reward->>'coins')::bigint, 0);
    item := nullif(v_reward->>'item', '');
    v_key := 'challenge:' || v_id;
    meta := jsonb_build_object('challenge_id', v_id);

  when 'season_tier' then
    v_season := c->'active_season';
    v_id := private.payload_text(p, 'season_id', '^[A-Za-z0-9_.-]{1,64}$');
    v_tier := private.payload_int(p, 'tier', 1, 1000);
    if v_season is null or v_season->>'id' is distinct from v_id
       or now() < (v_season->>'starts_at')::timestamptz or now() > (v_season->>'ends_at')::timestamptz
       or v_tier > coalesce((v_season->>'tiers')::bigint, 30) then
      perform private.fail('invalid_payload');
    end if;
    -- Plausibility: tiers unlocked so far cannot exceed the season's daily pace.
    v_days := floor(extract(epoch from now() - (v_season->>'starts_at')::timestamptz) / 86400)::bigint + 1;
    if v_tier > coalesce((v_season->>'max_tiers_per_day')::bigint, 15) * v_days then
      perform private.fail('implausible_result');
    end if;
    coins := (c->'season_coin_cycle'->>(((v_tier - 1) % greatest(1, jsonb_array_length(c->'season_coin_cycle')))::int))::bigint;
    v_key := 'season:' || v_id || ':' || v_tier::text;
    premium_item := c->'season_premium_items'->>v_tier::text;
    v_premium := coalesce(pd.data->'season_premium' = 'true'::jsonb, false);
    meta := jsonb_build_object('season_id', v_id, 'tier', v_tier);
    if exists (select 1 from private.economy_grants
               where user_id = p_user and source = 'season_tier' and grant_key = 'season:' || v_id || ':' || v_tier::text) then
      -- Coins already paid. Premium unlocked later: this event pays the premium item only.
      if premium_item is null or not v_premium or exists (
        select 1 from private.economy_grants where user_id = p_user and source = 'season_tier'
          and grant_key = 'season_premium:' || v_id || ':' || v_tier::text) then
        perform private.fail('already_claimed');
      end if;
      v_key := 'season_premium:' || v_id || ':' || v_tier::text;
      coins := 0;
      item := premium_item;
      premium_item := null;
    elsif not v_premium then
      premium_item := null;
    end if;

  when 'wheel' then
    v_key := 'wheel:' || today::text;
    seg := floor(random() * jsonb_array_length(c->'wheel_rewards'))::int;
    coins := (c->'wheel_rewards'->>seg)::bigint;
    meta := jsonb_build_object('segment_index', seg, 'server_day', today);

  when 'starter_item' then
    v_id := private.payload_text(p, 'item_id', '^[a-z0-9_]{1,64}$');
    if not coalesce(c->'starter_items', '[]'::jsonb) ? v_id then perform private.fail('item_unavailable'); end if;
    v_key := 'starter';
    if not exists (select 1 from private.economy_grants
                   where user_id = p_user and source = 'starter_item' and grant_key = 'starter') then
      -- A 1.1 client already granted a starter (marker + item): that was the one pick.
      if coalesce(pd.data->'owned_items', '[]'::jsonb) ? 'grant_starter_v1' and exists (
        select 1 from jsonb_array_elements_text(coalesce(pd.data->'owned_items', '[]'::jsonb)) o(x)
        where coalesce(c->'starter_items', '[]'::jsonb) ? o.x) then
        perform private.fail('already_claimed');
      end if;
      if coalesce(pd.data->'owned_items', '[]'::jsonb) ? v_id then
        return jsonb_build_object('status','already_owned','granted',0,'balance',e.confirmed_balance,
                                  'coinDebt',e.coin_debt,'itemID',v_id);
      end if;
    end if;
    item := v_id;
    meta := jsonb_build_object('item_id', v_id);
  end case;

  if exists (select 1 from private.economy_grants
             where user_id = p_user and source = p_source and grant_key = v_key) then
    perform private.fail('already_claimed');
  end if;

  -- Limits / caps.
  if p_source = 'quest' then
    select count(*) into v_count from private.economy_grants
    where user_id = p_user and source = 'quest' and server_day = grant_day;
    if v_count >= coalesce((c->>'quest_daily_limit')::int, 3) then perform private.fail('claim_limit'); end if;
  end if;
  granted := coins;
  if p_source in ('gameplay', 'duel') then
    select coalesce(sum(amount), 0) into v_used from private.economy_grants
    where user_id = p_user and source in ('gameplay', 'duel') and server_day = today;
    granted := least(coins, greatest(0, coalesce((c->>'gameplay_daily_cap')::bigint, coins) - v_used));
    capped := coins - granted;
  end if;
  meta := meta || jsonb_build_object('computed', coins, 'capped', capped);

  insert into private.economy_grants
    (user_id, source, grant_key, server_day, event_key, amount, capped, item_id, metadata)
  values (p_user, p_source, v_key, grant_day, p_event_key, granted, capped, item, meta);
  if premium_item is not null then
    insert into private.economy_grants
      (user_id, source, grant_key, server_day, event_key, amount, item_id, metadata)
    values (p_user, 'season_tier', 'season_premium:' || v_id || ':' || v_tier::text, grant_day,
            private.deterministic_uuid('season_premium:' || p_event_key::text), 0, premium_item, meta);
  end if;

  if granted > 0 then
    out := private.apply_economy_delta(p_user, p_event_key, p_source, granted, cfg.version, meta);
  else
    perform private.record_economy_event(p_user, p_event_key, p_source, cfg.version, meta);
    out := jsonb_build_object('balance', e.confirmed_balance, 'coinDebt', e.coin_debt);
  end if;
  if item is not null then perform private.set_profile_item(p_user, item, true); end if;
  if premium_item is not null then perform private.set_profile_item(p_user, premium_item, true); end if;

  status := case when capped > 0 then 'capped'
                 when granted > 0 or item is not null then 'applied'
                 else 'recorded' end;
  return jsonb_strip_nulls(out || jsonb_build_object(
    'status', status, 'granted', granted,
    'segmentIndex', seg, 'itemID', coalesce(item, premium_item)));
exception when unique_violation then
  perform private.fail('already_claimed');
end $$;
revoke all on function private.submit_economy_event_for(uuid, uuid, text, jsonb) from public, anon, authenticated;

create or replace function private.submit_economy_event(p_event_key uuid, p_source text, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid();
begin
  return private.submit_economy_event_for(uid, p_event_key, p_source, p_payload);
end $$;
revoke all on function private.submit_economy_event(uuid, text, jsonb) from public, anon;

create or replace function public.submit_economy_event(p_event_key uuid, p_source text, p_payload jsonb)
returns jsonb
language sql volatile security invoker set search_path = '' as $$
  select private.submit_economy_event(p_event_key, p_source, p_payload)
$$;
revoke all on function public.submit_economy_event(uuid, text, jsonb) from public, anon;
grant execute on function private.submit_economy_event(uuid, text, jsonb),
  public.submit_economy_event(uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Rewarded ads (AdMob SSV → Edge Function admob-ssv → here). Replaces the
-- amount-taking candidate signature: the server computes every grant.
-- ---------------------------------------------------------------------------
drop function if exists public.record_verified_rewarded_claim(uuid, uuid, text, date, smallint, int);

create or replace function private.record_verified_rewarded_claim(
  p_user uuid, p_event_key uuid, p_source text, p_ad_transaction_id text,
  p_reference_event_key uuid default null, p_claim_index smallint default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cfg private.economy_configs;
  e private.economy;
  r private.rewarded_ad_receipts;
  ref private.economy_grants;
  today date := (now() at time zone 'utc')::date;
  max_claims int;
  n int;
  amount bigint := 0;
  meta jsonb;
  out jsonb;
begin
  cfg := private.require_active_economy();
  if p_user is null or p_event_key is null
     or coalesce(p_ad_transaction_id, '') !~ '^[A-Za-z0-9._:-]{1,128}$' then
    perform private.fail('invalid_payload');
  end if;
  if p_source is null or p_source not in ('home_rewarded','double_coins','revive','season_progress') then
    perform private.fail('invalid_source');
  end if;
  if not exists (select 1 from private.profile_data where id = p_user) then
    perform private.fail('profile_required');
  end if;

  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;

  -- One ad impression pays once, to one player.
  select * into r from private.rewarded_ad_receipts where ad_transaction_id = p_ad_transaction_id;
  if found then
    if r.user_id = p_user and r.event_key = p_event_key then
      return jsonb_build_object('status','duplicate','granted',0,'balance',e.confirmed_balance,'coinDebt',e.coin_debt);
    end if;
    perform private.fail('already_claimed');
  end if;
  if exists (select 1 from private.economy_reward_claims where user_id = p_user and event_key = p_event_key) then
    return jsonb_build_object('status','duplicate','granted',0,'balance',e.confirmed_balance,'coinDebt',e.coin_debt);
  end if;

  max_claims := case when p_source = 'revive' then 3 else 1 end;
  select count(*) into n from private.economy_reward_claims
  where user_id = p_user and source = p_source and server_day = today;
  if n >= max_claims then perform private.fail('claim_limit'); end if;

  meta := jsonb_build_object('server_day', today, 'claim_index', n + 1,
                             'client_claim_index', p_claim_index, 'ad_transaction_id', p_ad_transaction_id);
  if p_source = 'home_rewarded' then
    amount := coalesce((cfg.config->>'home_rewarded_coins')::bigint, 0);
  elsif p_source = 'double_coins' then
    select * into ref from private.economy_grants
    where user_id = p_user and event_key = p_reference_event_key and source in ('gameplay', 'duel');
    if not found or ref.created_at < now() - interval '24 hours' then perform private.fail('invalid_payload'); end if;
    amount := ref.amount;
    meta := meta || jsonb_build_object('reference_event_key', p_reference_event_key);
    insert into private.economy_grants (user_id, source, grant_key, server_day, event_key, amount, metadata)
    values (p_user, 'double_coins', 'double:' || p_reference_event_key::text, today, p_event_key, amount, meta);
  end if;

  insert into private.economy_reward_claims (user_id, source, server_day, claim_index, event_key)
  values (p_user, p_source, today, n + 1, p_event_key);
  insert into private.rewarded_ad_receipts (ad_transaction_id, user_id, event_key, source)
  values (p_ad_transaction_id, p_user, p_event_key, p_source);

  if amount > 0 then
    out := private.apply_economy_delta(p_user, p_event_key, p_source, amount, cfg.version, meta);
    return out || jsonb_build_object('granted', amount);
  end if;
  perform private.record_economy_event(p_user, p_event_key, p_source, cfg.version, meta);
  return jsonb_build_object('status','recorded','granted',0,'balance',e.confirmed_balance,'coinDebt',e.coin_debt);
exception when unique_violation then
  perform private.fail('already_claimed');
end $$;
revoke all on function private.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint)
  from public, anon, authenticated;

create or replace function public.record_verified_rewarded_claim(
  p_user uuid, p_event_key uuid, p_source text, p_ad_transaction_id text,
  p_reference_event_key uuid default null, p_claim_index smallint default null)
returns jsonb
language sql volatile security invoker set search_path = '' as $$
  select private.record_verified_rewarded_claim(p_user, p_event_key, p_source, p_ad_transaction_id,
                                                p_reference_event_key, p_claim_index)
$$;
revoke all on function public.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint)
  from public, anon, authenticated;
grant execute on function private.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint),
  public.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint) to service_role;

-- ---------------------------------------------------------------------------
-- save_profile guard. Inactive: previous body, unchanged (renamed). Active:
--   * coins pinned: accepted → confirmed_balance; not yet reconciled → the
--     stored balance (frozen, never reduced)
--   * server-owned items can only come from the stored profile (server grants)
--   * daily_reward_last_claim / daily_reward_streak are server-owned
--   * season_premium: sticky, or season_ads_required verified SSV claims
--   * leftover pending_iap_coins are moved into the ledger first
-- ---------------------------------------------------------------------------
alter function private.sanitize_economy(uuid, jsonb) rename to sanitize_economy_legacy;

create or replace function private.sanitize_economy(uid uuid, p jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cfg private.economy_configs;
  stored jsonb;
  stored_coins bigint;
  e private.economy;
  out jsonb;
  server_items text[];
  stored_items jsonb;
  items jsonb;
  verified_ads int;
  k text;
begin
  select * into cfg from private.economy_configs where active;
  if not found then return private.sanitize_economy_legacy(uid, p); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return p; end if;

  select data into stored from private.profile_data where id = uid;
  stored_coins := case when stored->>'coins' ~ '^[0-9]{1,15}$' then (stored->>'coins')::bigint end;
  if stored is not null then
    -- Existing profile without an economy row: preserve it as a legacy balance.
    insert into private.economy (user_id, confirmed_balance, legacy_opening_balance, legacy_status)
    values (uid, coalesce(stored_coins, 0), coalesce(stored_coins, 0), 'pending')
    on conflict (user_id) do nothing;
  else
    insert into private.economy (user_id) values (uid) on conflict (user_id) do nothing;
  end if;
  select * into e from private.economy where user_id = uid for update;

  if e.pending_iap_coins > 0 then
    perform private.apply_economy_delta(uid, gen_random_uuid(), 'iap_coins', e.pending_iap_coins, cfg.version,
      jsonb_build_object('from', 'pending_iap_coins'));
    update private.economy set pending_iap_coins = 0, updated_at = now() where user_id = uid returning * into e;
    select data into stored from private.profile_data where id = uid;
    stored_coins := case when stored->>'coins' ~ '^[0-9]{1,15}$' then (stored->>'coins')::bigint end;
  end if;

  -- no_ads / premium skins / season (legacy rules), without its coin budget.
  out := private.sanitize_economy_legacy(uid, p - 'coins');
  if out is null or jsonb_typeof(out) <> 'object' then return out; end if;

  out := out || jsonb_build_object('coins',
    case when e.legacy_status = 'accepted' or stored_coins is null then e.confirmed_balance else stored_coins end);

  server_items := private.server_owned_items(cfg);
  stored_items := case when jsonb_typeof(stored->'owned_items') = 'array' then stored->'owned_items' else '[]'::jsonb end;
  if jsonb_typeof(out->'owned_items') = 'array' then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into items from (
      select x from jsonb_array_elements_text(out->'owned_items') t(x)
      where not (x = any(server_items)) or stored_items ? x
      union
      select x from jsonb_array_elements_text(stored_items) t(x) where x = any(server_items)
    ) s;
    out := jsonb_set(out, '{owned_items}', items);
  elsif stored ? 'owned_items' then
    out := out || jsonb_build_object('owned_items', stored_items);
  end if;

  foreach k in array array['daily_reward_last_claim', 'daily_reward_streak'] loop
    if stored ? k then out := out || jsonb_build_object(k, stored->k); else out := out - k; end if;
  end loop;

  select count(*) into verified_ads from private.economy_reward_claims
  where user_id = uid and source = 'season_progress'
    and server_day >= coalesce(((cfg.config->'active_season'->>'starts_at')::timestamptz at time zone 'utc')::date, '-infinity'::date);
  out := out || jsonb_build_object('season_premium',
    coalesce(stored->'season_premium' = 'true'::jsonb, false)
    or verified_ads >= coalesce((cfg.config->>'season_ads_required')::int, 2147483647));
  return out;
end $$;
revoke all on function private.sanitize_economy(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.sanitize_economy_legacy(uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- StoreKit: coin packs through the ledger while a config is active. Every
-- inactive branch below is the 20261122120000 body unchanged.
-- ---------------------------------------------------------------------------
create or replace function private.record_verified_purchase(
  p_user uuid, p_transaction_id text, p_original_transaction_id text, p_product_id text,
  p_environment text, p_purchased_at timestamptz, p_revoked_at timestamptz default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  prod private.iap_products;
  inserted text;
  existing private.purchase_ledger;
  cfg private.economy_configs;
begin
  if p_user is null or coalesce(p_transaction_id, '') = '' then perform private.fail('invalid_payload'); end if;
  select * into prod from private.iap_products where product_id = p_product_id;
  if not found then perform private.fail('unknown_product'); end if;
  if not prod.enabled and not exists (
    select 1 from private.purchase_ledger where transaction_id = p_transaction_id
  ) then perform private.fail('disabled_product'); end if;

  insert into private.purchase_ledger
    (transaction_id, original_transaction_id, user_id, product_id, environment, purchased_at)
  values (p_transaction_id, coalesce(nullif(p_original_transaction_id, ''), p_transaction_id), p_user,
          p_product_id, p_environment, coalesce(p_purchased_at, now()))
  on conflict (transaction_id) do nothing
  returning transaction_id into inserted;

  if inserted is null then
    select * into existing from private.purchase_ledger where transaction_id = p_transaction_id;
    if existing.revoked_at is not null then return 'revoked'; end if;   -- incl. refund tombstones
    -- A transaction belongs to the first account that recorded it: replaying
    -- another player's signed transaction must not "verify".
    if existing.user_id is distinct from p_user then perform private.fail('owned_by_other_account'); end if;
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
    select * into cfg from private.economy_configs where active;
    if found then
      -- Verified money: credited even while the legacy balance awaits review.
      perform private.apply_economy_delta(p_user, private.deterministic_uuid('iap_coins:' || p_transaction_id),
        'iap_coins', prod.coins, cfg.version,
        jsonb_build_object('transaction_id', p_transaction_id, 'product_id', p_product_id));
    else
      update private.economy set pending_iap_coins = pending_iap_coins + prod.coins, updated_at = now() where user_id = p_user;
    end if;
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

create or replace function private.revoke_purchase(
  p_transaction_id text, p_revoked_at timestamptz,
  p_product_id text default null, p_original_transaction_id text default null,
  p_environment text default 'Production', p_user uuid default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  l private.purchase_ledger;
  prod private.iap_products;
  e private.economy;
  cfg private.economy_configs;
  debit bigint;
  from_pending bigint;
  revoked timestamptz := coalesce(p_revoked_at, now());
  revoke_key uuid;
begin
  select * into l from private.purchase_ledger where transaction_id = p_transaction_id for update;
  if not found then
    -- Refund arrived before the purchase was recorded: leave a tombstone so a
    -- later delivery of the same transaction is never granted.
    if p_product_id is null or not exists (select 1 from private.iap_products where product_id = p_product_id) then
      return 'unknown_transaction';
    end if;
    insert into private.purchase_ledger
      (transaction_id, original_transaction_id, user_id, product_id, environment, purchased_at, revoked_at)
    values (p_transaction_id, coalesce(nullif(p_original_transaction_id, ''), p_transaction_id), p_user, p_product_id,
            coalesce(p_environment, 'Production'), revoked, revoked)
    on conflict (transaction_id) do nothing;
    return 'revoked';
  end if;
  if l.revoked_at is not null then return 'already_revoked'; end if;
  update private.purchase_ledger set revoked_at = revoked where transaction_id = p_transaction_id;
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
    select * into cfg from private.economy_configs where active;
    if found then
      -- Ledger debit down to zero. The shortfall is recorded, never turned
      -- into coin_debt (no debt policy is active).
      revoke_key := private.deterministic_uuid('iap_revoke:' || p_transaction_id || ':' || extract(epoch from revoked)::text);
      if least(debit, e.confirmed_balance) > 0 then
        perform private.apply_economy_delta(l.user_id, revoke_key, 'iap_revoke', -least(debit, e.confirmed_balance),
          cfg.version, jsonb_build_object('transaction_id', p_transaction_id, 'product_id', l.product_id,
            'from_pending', from_pending, 'debited', least(debit, e.confirmed_balance),
            'uncollected', debit - least(debit, e.confirmed_balance)));
      else
        perform private.record_economy_event(l.user_id, revoke_key, 'iap_revoke', cfg.version,
          jsonb_build_object('transaction_id', p_transaction_id, 'product_id', l.product_id,
            'from_pending', from_pending, 'debited', 0, 'uncollected', debit));
      end if;
    elsif debit > 0 then
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
  elsif not exists (select 1 from private.purchase_ledger
                    where user_id = l.user_id and product_id = l.product_id and revoked_at is null) then
    -- Only when no other valid transaction for the same skin remains.
    update private.economy set premium_items = array_remove(premium_items, prod.item_id), updated_at = now()
    where user_id = l.user_id;
    perform private.set_profile_item(l.user_id, prod.item_id, false);
  end if;
  insert into private.economy_events (user_id, kind, detail)
  values (l.user_id, 'purchase_revoked', jsonb_build_object('transaction_id', p_transaction_id, 'product_id', l.product_id));
  return 'revoked';
end $$;
revoke all on function private.revoke_purchase(text, timestamptz, text, text, text, uuid) from public, anon, authenticated;

create or replace function private.reinstate_purchase(p_transaction_id text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  l private.purchase_ledger;
  prod private.iap_products;
  cfg private.economy_configs;
  rev private.economy_events;
  restore bigint;
begin
  select * into l from private.purchase_ledger where transaction_id = p_transaction_id for update;
  if not found then return 'unknown_transaction'; end if;
  if l.revoked_at is null then return 'already_active'; end if;
  if l.user_id is null then return 'unknown_owner'; end if;
  select * into prod from private.iap_products where product_id = l.product_id;
  if not found then return 'unknown_product'; end if;

  update private.purchase_ledger set revoked_at = null where transaction_id = p_transaction_id;
  insert into private.economy (user_id) values (l.user_id) on conflict (user_id) do nothing;
  if prod.kind = 'coins' then
    select * into cfg from private.economy_configs where active;
    if found then
      -- Give back exactly what this refund took (pending + debited), via the
      -- ledger. Revocations from before activation have no record: full pack.
      select * into rev from private.economy_events
      where user_id = l.user_id and event_key = private.deterministic_uuid(
        'iap_revoke:' || p_transaction_id || ':' || extract(epoch from l.revoked_at)::text);
      restore := case when found
        then coalesce((rev.metadata->>'from_pending')::bigint, 0) + coalesce((rev.metadata->>'debited')::bigint, 0)
        else prod.coins end;
      if restore > 0 then
        perform private.apply_economy_delta(l.user_id,
          private.deterministic_uuid('iap_reinstate:' || p_transaction_id || ':' || extract(epoch from l.revoked_at)::text),
          'iap_reinstate', restore, cfg.version,
          jsonb_build_object('transaction_id', p_transaction_id, 'product_id', l.product_id));
      end if;
    else
      update private.economy set pending_iap_coins = pending_iap_coins + prod.coins, updated_at = now()
      where user_id = l.user_id;
    end if;
  elsif prod.kind = 'remove_ads' then
    update private.economy set no_ads = true, updated_at = now() where user_id = l.user_id;
    update private.profile_data set data = data || '{"no_ads": true}'::jsonb where id = l.user_id;
  else
    update private.economy
    set premium_items = case when prod.item_id = any(premium_items) then premium_items else premium_items || prod.item_id end,
        updated_at = now()
    where user_id = l.user_id;
    perform private.set_profile_item(l.user_id, prod.item_id, true);
  end if;
  insert into private.economy_events (user_id, kind, detail)
  values (l.user_id, 'purchase_reinstated', jsonb_build_object('transaction_id', p_transaction_id, 'product_id', l.product_id));
  return 'reinstated';
end $$;
revoke all on function private.reinstate_purchase(text) from public, anon, authenticated;
grant execute on function private.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz),
  private.revoke_purchase(text, timestamptz, text, text, text, uuid),
  private.reinstate_purchase(text) to service_role;

-- ---------------------------------------------------------------------------
-- Legacy reconciliation (service role / SQL editor only). Dry-run by default:
-- classifies every `pending` account and changes nothing. With
-- p_dry_run = false it writes the review queue and statuses; accepted accounts
-- keep their CURRENT balance (no reduction ever); review / rejected keep their
-- balance frozen for a human decision.
-- ---------------------------------------------------------------------------
create or replace function private.reconcile_legacy_economy(
  p_dry_run boolean default true,
  p_base_allowance bigint default 2000,
  p_daily_allowance bigint default 2500,
  p_per_game_allowance bigint default 120,
  p_review_factor numeric default 3)
returns table (
  user_id uuid, classification text, reason_code text, legacy_candidate bigint,
  verified_floor bigint, allowance bigint, account_age_days int, refunded_coin_purchases int,
  legacy_account boolean, applied boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  rec record;
  v_class text;
  v_reason text;
  v_allow bigint;
  v_game_allow bigint;
begin
  for rec in
    select e.user_id as uid, e.confirmed_balance,
           greatest(0, coalesce(case when pd.data->>'coins' ~ '^[0-9]{1,15}$' then (pd.data->>'coins')::bigint end,
                                e.legacy_opening_balance, 0)) as candidate,
           coalesce((select sum(ip.coins) from private.purchase_ledger pl
                     join private.iap_products ip on ip.product_id = pl.product_id
                     where pl.user_id = e.user_id and ip.kind = 'coins' and pl.revoked_at is null), 0)::bigint as paid,
           (select count(*) from private.purchase_ledger pl
            join private.iap_products ip on ip.product_id = pl.product_id
            where pl.user_id = e.user_id and ip.kind = 'coins' and pl.revoked_at is not null)::int as refunds,
           greatest(0, floor(extract(epoch from now() - least(u.created_at, coalesce(pr.created_at, u.created_at))) / 86400))::int as age_days,
           exists (select 1 from private.legacy_claims lc where lc.user_id = e.user_id) as is_legacy,
           case when jsonb_typeof(pd.data->'stats'->'totalGames') = 'number'
                then least(greatest((pd.data->'stats'->>'totalGames')::numeric, 0), 1000000)::bigint else 0 end as games
    from private.economy e
    join auth.users u on u.id = e.user_id
    left join public.profiles pr on pr.id = e.user_id
    left join private.profile_data pd on pd.id = e.user_id
    where e.legacy_status = 'pending'
    order by e.user_id
    for update of e
  loop
    -- Server evidence only: verified purchases + time since the account exists.
    v_allow := rec.paid + p_base_allowance + p_daily_allowance * greatest(rec.age_days, 1);
    -- Client-reported play history is weak evidence: it can only move an
    -- account to `review`, never to `accepted`.
    v_game_allow := rec.paid + p_base_allowance + p_per_game_allowance * rec.games;
    if rec.refunds > 0 then
      v_class := 'review'; v_reason := 'refunded_coin_purchase';
    elsif rec.candidate <= v_allow then
      v_class := 'accepted'; v_reason := case when rec.candidate <= rec.paid + p_base_allowance
                                              then 'within_verified_floor' else 'plausible_accrual' end;
    elsif rec.candidate <= v_allow * p_review_factor then
      v_class := 'review'; v_reason := 'above_accrual_allowance';
    elsif rec.is_legacy and rec.candidate <= v_game_allow then
      v_class := 'review'; v_reason := 'legacy_history_supported';
    else
      v_class := 'rejected'; v_reason := 'implausible_balance';
    end if;

    if not p_dry_run then
      insert into private.legacy_economy_reviews as lr
        (user_id, snapshot, verified_floor, legacy_candidate, confirmed_balance, disputed_balance,
         plausibility_score, status, reason_code, reviewed_by, reviewed_at)
      values (rec.uid,
              jsonb_build_object('reconciled_at', now(), 'profile_coins', rec.candidate, 'paid_coins', rec.paid,
                                 'account_age_days', rec.age_days, 'games', rec.games, 'legacy', rec.is_legacy),
              rec.paid, rec.candidate,
              case when v_class = 'accepted' then rec.candidate else rec.confirmed_balance end,
              case when v_class = 'accepted' then 0 else greatest(0, rec.candidate - least(rec.candidate, v_allow)) end,
              round(rec.candidate::numeric / greatest(v_allow, 1), 4), v_class, v_reason,
              'reconcile_legacy_economy', now())
      on conflict on constraint legacy_economy_reviews_pkey do update
        set snapshot = lr.snapshot || excluded.snapshot, verified_floor = excluded.verified_floor,
            legacy_candidate = excluded.legacy_candidate, confirmed_balance = excluded.confirmed_balance,
            disputed_balance = excluded.disputed_balance, plausibility_score = excluded.plausibility_score,
            status = excluded.status, reason_code = excluded.reason_code,
            reviewed_by = excluded.reviewed_by, reviewed_at = excluded.reviewed_at, updated_at = now();
      if v_class = 'accepted' then
        update private.economy
        set confirmed_balance = rec.candidate, legacy_status = 'accepted', updated_at = now()
        where private.economy.user_id = rec.uid;
        update private.profile_data set data = jsonb_set(data, '{coins}', to_jsonb(rec.candidate))
        where id = rec.uid;
        insert into private.economy_events (user_id, kind, detail, event_key, source, amount, metadata)
        values (rec.uid, 'legacy_reconciled', jsonb_build_object('from', rec.confirmed_balance, 'to', rec.candidate),
                private.deterministic_uuid('legacy_accept:' || rec.uid::text), 'legacy_opening',
                rec.candidate - rec.confirmed_balance, jsonb_build_object('reason', v_reason));
      else
        update private.economy set legacy_status = v_class, updated_at = now()
        where private.economy.user_id = rec.uid;
      end if;
    end if;

    user_id := rec.uid; classification := v_class; reason_code := v_reason;
    legacy_candidate := rec.candidate; verified_floor := rec.paid; allowance := v_allow;
    account_age_days := rec.age_days; refunded_coin_purchases := rec.refunds;
    legacy_account := rec.is_legacy; applied := not p_dry_run;
    return next;
  end loop;
end $$;
revoke all on function private.reconcile_legacy_economy(boolean, bigint, bigint, bigint, numeric)
  from public, anon, authenticated;
grant execute on function private.reconcile_legacy_economy(boolean, bigint, bigint, bigint, numeric) to service_role;

-- Guard: nothing client-callable in `public` may be SECURITY DEFINER.
do $check$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'public SECURITY DEFINER function still executable by authenticated';
  end if;
end
$check$;
