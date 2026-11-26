-- ============================================================================
-- 1.2.0 — season calendar alignment (client ↔ server)
-- ============================================================================
-- Additive. Replaces the single placeholder `active_season`
-- (season_1_neon_nights, 2026-12-01..2027-03-01) of the INACTIVE
-- balanced-premium-rc1 config with a deterministic calendar rule that iOS
-- (SeasonCalendar in ios/PerfectTap/Models/SeasonPass.swift) computes
-- identically:
--
--   season_calendar = {anchor: "2026-03-01", length_months: 3,
--                      id_format: "season_<n>", tiers: 30,
--                      max_tiers_per_day: 15, grace_hours: 72}
--
--   n      = floor(whole UTC months since anchor / length_months) + 1
--   start  = anchor + (n-1)*length_months months   (00:00:00 UTC, inclusive)
--   end    = start + length_months months          (exclusive)
--   id     = id_format with <n> replaced, e.g. 2026-11-26 → season_3
--            (Sep 1 – Nov 30), 2026-12-01 → season_4 (Dec 1 – Feb 28).
--
-- `season_tier` accepts the current season, or the previous season while
-- now < previous end + grace_hours (offline claims across a boundary). Tier
-- bound and per-day pace (max_tiers_per_day × days since that season began)
-- are kept. No grant, balance, item or ledger row is touched; the config
-- update only applies to the inactive row. anchor / length_months /
-- grace_hours are owner-tunable values still pending approval.
-- ============================================================================

update private.economy_configs
set config = (config - 'active_season') || jsonb_build_object(
  'season_calendar', jsonb_build_object(
    'anchor', '2026-03-01',
    'length_months', 3,
    'id_format', 'season_<n>',
    'tiers', 30,
    'max_tiers_per_day', 15,
    'grace_hours', 72))
where version = 'balanced-premium-rc1' and not active;

-- The season containing p_at (UTC). No row when the calendar is missing or
-- malformed, or p_at is before the anchor. The anchor must be the 1st of a
-- month so month arithmetic is exact (Swift uses the same rule).
create or replace function private.season_at(c jsonb, p_at timestamptz)
returns table (season_id text, season_number int, starts_at timestamptz, ends_at timestamptz)
language plpgsql stable set search_path = '' as $$
declare
  cal jsonb := c->'season_calendar';
  v_anchor date;
  v_len int;
  v_fmt text;
  t timestamp;
  v_months int;
  v_idx int;
  s timestamp;
begin
  if cal is null or jsonb_typeof(cal) <> 'object' or p_at is null then return; end if;
  begin
    v_anchor := (cal->>'anchor')::date;
    v_len := (cal->>'length_months')::int;
  exception when others then
    return;
  end;
  v_fmt := coalesce(cal->>'id_format', 'season_<n>');
  if v_anchor is null or extract(day from v_anchor) <> 1 or v_len is null or v_len < 1
     or position('<n>' in v_fmt) = 0 then
    return;
  end if;
  t := p_at at time zone 'utc';
  if t < v_anchor::timestamp then return; end if;
  v_months := (extract(year from t)::int - extract(year from v_anchor)::int) * 12
            + (extract(month from t)::int - extract(month from v_anchor)::int);
  v_idx := v_months / v_len;                     -- v_months >= 0
  s := v_anchor::timestamp + make_interval(months => v_idx * v_len);
  season_number := v_idx + 1;
  season_id := replace(v_fmt, '<n>', season_number::text);
  starts_at := s at time zone 'utc';
  ends_at := (s + make_interval(months => v_len)) at time zone 'utc';
  return next;
end $$;
revoke all on function private.season_at(jsonb, timestamptz) from public, anon, authenticated;

-- Validates a season_tier claim at p_now. Returns null when it is acceptable,
-- else the error code to raise: `invalid_payload` (unknown / closed / future
-- season, tier above `tiers`) or `implausible_result` (tier beyond the pace).
create or replace function private.season_tier_verdict(c jsonb, p_season_id text, p_tier bigint, p_now timestamptz)
returns text
language plpgsql stable set search_path = '' as $$
declare
  cal jsonb := coalesce(c->'season_calendar', '{}'::jsonb);
  cur record;
  prev record;
  v_start timestamptz;
  v_days bigint;
begin
  select * into cur from private.season_at(c, p_now);
  if not found or p_season_id is null or p_tier is null or p_tier < 1 then return 'invalid_payload'; end if;
  if p_season_id = cur.season_id then
    v_start := cur.starts_at;
  else
    select * into prev from private.season_at(c, cur.starts_at - interval '1 microsecond');
    if found and prev.season_id = p_season_id
       and p_now < prev.ends_at + make_interval(hours => coalesce((cal->>'grace_hours')::int, 72)) then
      v_start := prev.starts_at;
    else
      return 'invalid_payload';
    end if;
  end if;
  if p_tier > coalesce((cal->>'tiers')::bigint, 30) then return 'invalid_payload'; end if;
  -- Plausibility: tiers unlocked so far cannot exceed the season's daily pace.
  v_days := floor(extract(epoch from p_now - v_start) / 86400)::bigint + 1;
  if p_tier > coalesce((cal->>'max_tiers_per_day')::bigint, 15) * v_days then
    return 'implausible_result';
  end if;
  return null;
end $$;
revoke all on function private.season_tier_verdict(jsonb, text, bigint, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- submit_economy_event_for: body of 20261125200000 with only the season_tier
-- branch changed (calendar rule via season_tier_verdict).
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
  v_id text; v_day date; v_tier bigint; v_reward jsonb;
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
    v_id := private.payload_text(p, 'season_id', '^[A-Za-z0-9_.-]{1,64}$');
    v_tier := private.payload_int(p, 'tier', 1, 1000);
    -- Season calendar rule (current season, or the previous one inside the
    -- grace window) + tier bound + per-day pace. Same rule as iOS SeasonCalendar.
    v_verdict := private.season_tier_verdict(c, v_id, v_tier, now());
    if v_verdict is not null then perform private.fail(v_verdict); end if;
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

-- ---------------------------------------------------------------------------
-- sanitize_economy: body of 20261125200000 with only the season_progress
-- window changed (active_season.starts_at -> start of the current calendar season).
-- ---------------------------------------------------------------------------
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
    and server_day >= coalesce((select (s.starts_at at time zone 'utc')::date from private.season_at(cfg.config, now()) s), '-infinity'::date);
  out := out || jsonb_build_object('season_premium',
    coalesce(stored->'season_premium' = 'true'::jsonb, false)
    or verified_ads >= coalesce((cfg.config->>'season_ads_required')::int, 2147483647));
  return out;
end $$;
revoke all on function private.sanitize_economy(uuid, jsonb) from public, anon, authenticated;
