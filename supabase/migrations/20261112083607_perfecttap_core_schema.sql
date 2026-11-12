-- ============================================================================
-- PerfectTap — core Supabase schema (replaces Firestore + Cloud Functions)
-- ============================================================================
-- Trust model
--   * Clients (anon/authenticated) can only SELECT rows they are allowed to see.
--   * Every write goes through a SECURITY DEFINER RPC below that re-derives the
--     caller from auth.uid(), validates input, enforces state transitions and
--     rate limits, and runs atomically (row locks, unique indexes).
--   * No table grants INSERT/UPDATE/DELETE to anon/authenticated.
--   * Internal state (sessions, rate limits, mode rules, legacy mapping) lives in
--     the non-exposed `private` schema.
-- Firestore → Postgres mapping is documented in docs/SUPABASE_MIGRATION.he.md.
-- ============================================================================

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------

-- Raises a client-safe error. Error text is a stable machine code the iOS app
-- maps to UI copy; details never contain internal state.
create or replace function private.fail(code text)
returns void language plpgsql immutable set search_path = '' as $$
begin
  raise exception using errcode = 'P0001', message = code;
end $$;

create or replace function private.require_uid()
returns uuid language plpgsql stable set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then perform private.fail('not_authenticated'); end if;
  return uid;
end $$;

-- Fixed-window rate limiter, one row per (user, action).
create table private.rate_limits (
  user_id      uuid not null references auth.users(id) on delete cascade,
  action       text not null,
  window_start timestamptz not null,
  hits         int not null,
  primary key (user_id, action)
);
alter table private.rate_limits enable row level security;

create or replace function private.check_rate(p_user uuid, p_action text, p_max int, p_window interval)
returns void language plpgsql set search_path = '' as $$
declare r private.rate_limits;
begin
  insert into private.rate_limits as rl (user_id, action, window_start, hits)
  values (p_user, p_action, now(), 1)
  on conflict (user_id, action) do update
    set hits         = case when rl.window_start > now() - p_window then rl.hits + 1 else 1 end,
        window_start = case when rl.window_start > now() - p_window then rl.window_start else now() end
  returning * into r;
  if r.hits > p_max then perform private.fail('rate_limited'); end if;
end $$;

create or replace function private.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

-- ---------------------------------------------------------------------------
-- Game mode rules (mirror of functions/src/scoring.ts + GameConfig.swift)
-- ---------------------------------------------------------------------------
create table private.mode_rules (
  mode                 text primary key,
  ranked               boolean not null,
  max_combo_multiplier int not null check (max_combo_multiplier between 1 and 100),
  timer_seconds        int check (timer_seconds > 0),
  boost_multiplier     int not null default 1 check (boost_multiplier between 1 and 10),
  best_score_key       text
);
alter table private.mode_rules enable row level security;

insert into private.mode_rules (mode, ranked, max_combo_multiplier, timer_seconds, boost_multiplier, best_score_key) values
  ('classic',        true,  2, null, 2, 'best_classic'),
  ('endless',        true,  2, null, 1, 'best_endless'),
  ('timed',          true,  2, 60,   1, 'best_timed'),
  ('sudden_death',   true,  2, null, 1, 'best_sudden'),
  ('combo_frenzy',   true,  6, null, 1, 'best_combofrenzy'),
  ('precision',      true,  2, null, 1, 'best_precision'),
  ('chaos',          true,  2, null, 1, 'best_chaos'),
  ('mirror',         true,  2, null, 1, 'best_mirror'),
  ('invisible_zone', true,  2, null, 1, 'best_invisiblezone'),
  ('rush',           true,  2, 30,   1, 'best_rush'),
  ('hardcore_combo', true,  2, null, 1, 'best_hardcorecombo'),
  ('tiny_window',    true,  2, null, 1, 'best_tinywindow'),
  ('zen',            false, 1, null, 1, null),
  ('focus',          false, 1, null, 1, 'best_focus'),
  ('duel',           false, 2, null, 1, null);

-- Constants shared with scoring.ts
create or replace function private.perfect_points()        returns int     language sql immutable set search_path = '' as 'select 100';
create or replace function private.max_taps_per_second()   returns int     language sql immutable set search_path = '' as 'select 12';
create or replace function private.elapsed_slack_seconds() returns numeric language sql immutable set search_path = '' as 'select 5::numeric';
create or replace function private.max_score()             returns int     language sql immutable set search_path = '' as 'select 10000000';

-- Port of checkPlausibility(). Returns NULL when plausible, else a reason code.
-- p_elapsed NULL = no server-timed session (only static bounds apply).
create or replace function private.check_plausibility(
  p_mode text, p_score int, p_max_combo int, p_taps int, p_perfects int,
  p_elapsed numeric, p_require_ranked boolean)
returns text language plpgsql stable set search_path = '' as $$
declare
  r private.mode_rules;
  playable numeric;
  max_taps int;
begin
  select * into r from private.mode_rules where mode = p_mode;
  if not found then return 'unknown_mode'; end if;
  if p_require_ranked and not r.ranked then return 'mode_not_ranked'; end if;
  if p_score < 0 or p_max_combo < 0 or p_taps < 0 or p_perfects < 0 then return 'negative_value'; end if;
  if p_score > private.max_score() then return 'score_out_of_range'; end if;
  if p_perfects > p_taps then return 'perfects_exceed_taps'; end if;
  if p_max_combo > p_taps then return 'combo_exceeds_taps'; end if;

  if p_elapsed is not null then
    playable := least(p_elapsed, coalesce(r.timer_seconds + 15, p_elapsed)) + private.elapsed_slack_seconds();
    max_taps := floor(greatest(0, playable - 3) * private.max_taps_per_second());
    if p_taps > max_taps then return 'too_many_taps_for_time'; end if;
  else
    -- No session: a run can't exceed the 2h session TTL.
    if p_taps > 7200 * private.max_taps_per_second() then return 'too_many_taps_for_time'; end if;
  end if;

  if p_score::bigint > p_taps::bigint * private.perfect_points() * r.max_combo_multiplier * r.boost_multiplier then
    return 'score_exceeds_taps';
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- Profiles
--   public.profiles        — social fields any signed-in player may read
--   private.profile_data   — everything else (economy, quests, friend code …)
-- The iOS app keeps its Firestore-shaped dictionary; save_profile() splits it.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null default ''
              check (username = '' or username ~ '^[A-Za-z0-9_]{2,20}$'),
  avatar      text not null default 'default' check (char_length(avatar) <= 64),
  level       int  not null default 1 check (level between 1 and 10000),
  best_scores jsonb not null default '{}'::jsonb
              check (jsonb_typeof(best_scores) = 'object' and octet_length(best_scores::text) <= 4096),
  public_data jsonb not null default '{}'::jsonb
              check (jsonb_typeof(public_data) = 'object' and octet_length(public_data::text) <= 8192),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index profiles_username_lower_key on public.profiles (lower(username)) where username <> '';
create trigger profiles_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();

create table private.profile_data (
  id          uuid primary key references public.profiles(id) on delete cascade,
  friend_code text unique check (friend_code ~ '^[A-Z0-9]{4,12}$'),
  data        jsonb not null default '{}'::jsonb
              check (jsonb_typeof(data) = 'object' and octet_length(data::text) <= 262144),
  updated_at  timestamptz not null default now()
);
alter table private.profile_data enable row level security;
create trigger profile_data_updated_at before update on private.profile_data
  for each row execute function private.set_updated_at();

alter table public.profiles enable row level security;
create policy "profiles readable by signed-in players" on public.profiles
  for select to authenticated using (true);

-- Keys exposed to other players (FriendDetailView / FriendsView / leaderboard).
create or replace function private.public_profile_keys()
returns text[] language sql immutable set search_path = '' as $$
  select array['equipped_avatar','equipped_badge','equipped_theme','stats']
$$;

-- Validates and stores the client's profile dictionary for the caller.
create or replace function private.save_profile_for(uid uuid, p jsonb)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  cur public.profiles;
  cur_code text;
  new_username text;
  new_code text;
  bests jsonb := '{}'::jsonb;
  pub jsonb := '{}'::jsonb;
  priv jsonb;
  k text; v jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then perform private.fail('invalid_payload'); end if;
  if octet_length(p::text) > 262144 then perform private.fail('payload_too_large'); end if;

  select * into cur from public.profiles where id = uid for update;
  select friend_code into cur_code from private.profile_data where id = uid;

  -- Username: format-checked by the column constraint, permanent once chosen.
  new_username := coalesce(p->>'username', coalesce(cur.username, ''));
  if cur.username is not null and cur.username <> '' and new_username <> cur.username then
    perform private.fail('username_immutable');
  end if;

  -- Friend code: set once.
  new_code := upper(nullif(p->>'friend_code', ''));
  if cur_code is not null then new_code := cur_code; end if;

  -- Numeric sanity (mirrors firestore.rules bounds).
  foreach k in array array['coins','level','xp','season_xp','season_tier','daily_reward_streak',
                           'revives_used_today','season_ad_progress'] loop
    v := p->k;
    if v is not null and jsonb_typeof(v) <> 'null' then
      if jsonb_typeof(v) <> 'number' or (v::text)::numeric <> trunc((v::text)::numeric) then
        perform private.fail('invalid_' || k);
      end if;
    end if;
  end loop;
  if coalesce((p->>'coins')::numeric, 0) not between 0 and 100000000 then perform private.fail('invalid_coins'); end if;
  if coalesce((p->>'level')::numeric, 1) not between 1 and 10000 then perform private.fail('invalid_level'); end if;
  if coalesce((p->>'xp')::numeric, 0) not between 0 and 100000000 then perform private.fail('invalid_xp'); end if;
  if coalesce((p->>'season_xp')::numeric, 0) not between 0 and 100000000 then perform private.fail('invalid_season_xp'); end if;
  if coalesce((p->>'season_tier')::numeric, 0) not between 0 and 1000 then perform private.fail('invalid_season_tier'); end if;
  foreach k in array array['no_ads','season_premium'] loop
    if p ? k and jsonb_typeof(p->k) not in ('boolean','null') then perform private.fail('invalid_' || k); end if;
  end loop;
  if p ? 'stats' and jsonb_typeof(p->'stats') not in ('object','null') then perform private.fail('invalid_stats'); end if;

  -- Best scores: every top-level best_* integer + best_scores_extra.
  for k, v in select key, value from jsonb_each(p) where key like 'best\_%' and key <> 'best_scores_extra' loop
    if jsonb_typeof(v) = 'number' then
      if (v::text)::numeric not between 0 and private.max_score() then perform private.fail('invalid_' || k); end if;
      bests := bests || jsonb_build_object(k, trunc((v::text)::numeric)::int);
    end if;
  end loop;
  if jsonb_typeof(p->'best_scores_extra') = 'object' then
    for k, v in select key, value from jsonb_each(p->'best_scores_extra') loop
      if jsonb_typeof(v) = 'number' and (v::text)::numeric between 0 and private.max_score() then
        bests := bests || jsonb_build_object(k, greatest(coalesce((bests->>k)::int, 0), trunc((v::text)::numeric)::int));
      end if;
    end loop;
  end if;

  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into pub
  from jsonb_each(p) where key = any(private.public_profile_keys());

  -- Private blob: drop keys that live in typed columns or are server-owned.
  priv := p - array['uid','username','username_lower','friend_code','server_day_probe_ts'];

  insert into public.profiles as pr (id, username, avatar, level, best_scores, public_data)
  values (uid, new_username, left(coalesce(p->>'avatar', 'default'), 64),
          coalesce((p->>'level')::int, 1), bests, pub)
  on conflict (id) do update
    set username = excluded.username, avatar = excluded.avatar, level = excluded.level,
        best_scores = excluded.best_scores, public_data = excluded.public_data;

  insert into private.profile_data as pd (id, friend_code, data)
  values (uid, new_code, priv)
  on conflict (id) do update set friend_code = excluded.friend_code, data = excluded.data;
exception
  when unique_violation then
    if sqlerrm like '%username%' then perform private.fail('username_taken'); end if;
    if sqlerrm like '%friend_code%' then perform private.fail('friend_code_taken'); end if;
    raise;
  when check_violation then
    perform private.fail('invalid_profile');
end $$;

create or replace function public.save_profile(p jsonb)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid();
begin
  perform private.check_rate(uid, 'save_profile', 120, interval '1 minute');
  perform private.save_profile_for(uid, p);
end $$;

-- Full profile for the caller, in the Firestore dictionary shape.
create or replace function public.get_my_profile()
returns jsonb
language sql stable security definer set search_path = '' as $$
  select d.data
         || pr.best_scores
         || jsonb_build_object('uid', pr.id, 'username', pr.username, 'avatar', pr.avatar,
                               'level', pr.level, 'friend_code', coalesce(d.friend_code, ''),
                               'best_scores_extra', pr.best_scores)
  from public.profiles pr
  left join private.profile_data d on d.id = pr.id
  where pr.id = auth.uid()
$$;

-- Public profile(s) of other players, same dictionary shape (private keys absent).
create or replace function public.get_player_profiles(p_ids uuid[])
returns setof jsonb
language sql stable security invoker set search_path = '' as $$
  select pr.public_data || pr.best_scores
         || jsonb_build_object('uid', pr.id, 'username', pr.username, 'avatar', pr.avatar,
                               'level', pr.level, 'best_scores_extra', pr.best_scores)
  from public.profiles pr
  where pr.id = any(p_ids[1:100])
$$;

create or replace function public.is_username_available(p_username text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1 from public.profiles
    where lower(username) = lower(trim(p_username)) and username <> '' and id <> auth.uid()
  )
$$;

-- Authoritative UTC day (replaces the Firestore server-timestamp probe write).
create or replace function public.server_day()
returns text language sql stable set search_path = '' as $$
  select to_char(now() at time zone 'utc', 'YYYY-MM-DD')
$$;

-- ---------------------------------------------------------------------------
-- Verified leaderboard (was leaderboard/{mode}/scores/{uid})
-- ---------------------------------------------------------------------------
create table public.leaderboard_scores (
  mode       text not null references private.mode_rules(mode),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  username   text not null default '',
  score      int  not null check (score between 0 and 10000000),
  max_combo  int  not null default 0 check (max_combo >= 0),
  session_id uuid,
  updated_at timestamptz not null default now(),
  primary key (mode, user_id)
);
create index leaderboard_scores_mode_score_idx on public.leaderboard_scores (mode, score desc);
alter table public.leaderboard_scores enable row level security;
create policy "leaderboard readable by signed-in players" on public.leaderboard_scores
  for select to authenticated using (true);

-- Verified board first; falls back to self-reported bests while empty (same as iOS 1.0.2).
create or replace function public.get_leaderboard(p_mode text, p_limit int default 20)
returns table (username text, score int, verified boolean)
language plpgsql stable security invoker set search_path = '' as $$
declare lim int := least(greatest(coalesce(p_limit, 20), 1), 100);
        key text;
begin
  return query
    select l.username, l.score, true from public.leaderboard_scores l
    where l.mode = p_mode and l.username <> ''
    order by l.score desc limit lim;
  if found then return; end if;
  select best_score_key into key from private.mode_rules where mode = p_mode;
  if key is null then return; end if;
  return query
    select pr.username, (pr.best_scores->>key)::int, false from public.profiles pr
    where pr.username <> '' and (pr.best_scores->>key)::int > 0
    order by (pr.best_scores->>key)::int desc limit lim;
end $$;
-- get_leaderboard reads private.mode_rules; give it a definer-free path via grant.
grant usage on schema private to authenticated;
grant select on private.mode_rules to authenticated;
create policy "mode rules readable" on private.mode_rules for select to authenticated using (true);

create index profiles_best_classic_idx on public.profiles (((best_scores->>'best_classic')::int) desc);

-- ---------------------------------------------------------------------------
-- Duels (was duels/{duelId})
-- ---------------------------------------------------------------------------
create table public.duels (
  id           uuid primary key default gen_random_uuid(),
  code         text not null check (code ~ '^[A-Z0-9]{6}$'),
  mode         text not null references private.mode_rules(mode),
  status       text not null default 'waiting' check (status in ('waiting','in_progress','completed')),
  host_id      uuid references auth.users(id) on delete set null,
  host_name    text not null check (char_length(host_name) <= 40),
  host_avatar  text check (char_length(host_avatar) <= 64),
  host_score   int check (host_score between 0 and 10000000),
  host_combo   int check (host_combo >= 0),
  host_verified boolean,
  host_submitted_at timestamptz,
  guest_id     uuid references auth.users(id) on delete set null,
  guest_name   text check (char_length(guest_name) <= 40),
  guest_avatar text check (char_length(guest_avatar) <= 64),
  guest_score  int check (guest_score between 0 and 10000000),
  guest_combo  int check (guest_combo >= 0),
  guest_verified boolean,
  guest_submitted_at timestamptz,
  created_at   timestamptz not null default now(),
  joined_at    timestamptz,
  completed_at timestamptz,
  check (host_id is null or guest_id is null or host_id <> guest_id),
  check (status = 'waiting' or guest_name is not null),
  check (status <> 'completed' or (host_score is not null and guest_score is not null))
);
-- A code identifies at most one open duel.
create unique index duels_open_code_key on public.duels (code) where status = 'waiting';
create index duels_host_idx  on public.duels (host_id, created_at desc);
create index duels_guest_idx on public.duels (guest_id, created_at desc);
create index duels_cleanup_idx on public.duels (status, created_at);

alter table public.duels enable row level security;
create policy "duel visible to its participants" on public.duels
  for select to authenticated
  using ((select auth.uid()) = host_id or (select auth.uid()) = guest_id);

create or replace function private.new_duel_code()
returns text language sql volatile set search_path = '' as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, 6)
$$;

create or replace function private.profile_identity(p_uid uuid, out username text, out avatar text)
language plpgsql stable set search_path = '' as $$
begin
  select pr.username, pr.avatar into username, avatar from public.profiles pr where pr.id = p_uid;
  if username is null or username = '' then perform private.fail('username_required'); end if;
end $$;

create or replace function private.create_duel_for(p_uid uuid, p_mode text)
returns public.duels language plpgsql set search_path = '' as $$
declare
  ident record;
  d public.duels;
  attempt int := 0;
begin
  if not exists (select 1 from private.mode_rules where mode = p_mode and mode not in ('zen','focus')) then
    perform private.fail('invalid_mode');
  end if;
  if (select count(*) from public.duels where host_id = p_uid and status = 'waiting'
        and created_at > now() - interval '24 hours') >= 10 then
    perform private.fail('too_many_open_duels');
  end if;
  select * into ident from private.profile_identity(p_uid);
  loop
    attempt := attempt + 1;
    begin
      insert into public.duels (code, mode, host_id, host_name, host_avatar)
      values (private.new_duel_code(), p_mode, p_uid, ident.username, ident.avatar)
      returning * into d;
      return d;
    exception when unique_violation then
      if attempt >= 5 then perform private.fail('code_generation_failed'); end if;
    end;
  end loop;
end $$;

create or replace function public.create_duel(p_mode text default 'duel')
returns table (duel_id uuid, code text)
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); d public.duels;
begin
  perform private.check_rate(uid, 'create_duel', 10, interval '1 minute');
  d := private.create_duel_for(uid, coalesce(p_mode, 'duel'));
  return query select d.id, d.code;
end $$;

create or replace function private.join_duel_row(p_uid uuid, p_duel public.duels)
returns public.duels language plpgsql set search_path = '' as $$
declare ident record; d public.duels;
begin
  if p_duel.host_id = p_uid then perform private.fail('cannot_join_own_duel'); end if;
  if p_duel.status <> 'waiting' or p_duel.guest_id is not null then perform private.fail('duel_unavailable'); end if;
  if p_duel.created_at < now() - interval '24 hours' then perform private.fail('duel_expired'); end if;
  select * into ident from private.profile_identity(p_uid);
  update public.duels
     set guest_id = p_uid, guest_name = ident.username, guest_avatar = ident.avatar,
         status = 'in_progress', joined_at = now()
   where id = p_duel.id
  returning * into d;
  return d;
end $$;

-- Join an open duel by its 6-character code. Row lock serialises racing joiners:
-- the loser re-reads the row as no longer 'waiting' and gets no row back.
create or replace function public.join_duel(p_code text)
returns table (duel_id uuid, host_name text)
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); d public.duels; norm text := upper(trim(coalesce(p_code, '')));
begin
  perform private.check_rate(uid, 'join_duel', 10, interval '1 minute');
  -- Unknown codes return ZERO ROWS instead of raising, so the transaction (and
  -- the rate-limit hit above) commits: code guessing stays rate limited.
  if norm !~ '^[A-Z0-9]{6}$' then return; end if;
  select * into d from public.duels where code = norm and status = 'waiting' for update;
  if not found then return; end if;
  d := private.join_duel_row(uid, d);
  return query select d.id, d.host_name;
end $$;

-- ---------------------------------------------------------------------------
-- Server-timed game sessions (was game_sessions + startGame callable)
-- ---------------------------------------------------------------------------
create table private.game_sessions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  mode       text not null references private.mode_rules(mode),
  duel_id    uuid references public.duels(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '2 hours',
  used_at    timestamptz,
  verdict    text
);
create index game_sessions_user_idx on private.game_sessions (user_id, started_at desc);
create index game_sessions_expiry_idx on private.game_sessions (expires_at);
alter table private.game_sessions enable row level security;

create or replace function public.start_game_session(p_mode text, p_duel_id uuid default null)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); d public.duels; sid uuid;
begin
  perform private.check_rate(uid, 'start_game', 20, interval '1 minute');
  if not exists (select 1 from private.mode_rules where mode = p_mode) then perform private.fail('unknown_mode'); end if;
  if p_duel_id is not null then
    select * into d from public.duels where id = p_duel_id;
    if not found or uid not in (d.host_id, d.guest_id) then perform private.fail('duel_not_found'); end if;
    if d.mode <> p_mode then perform private.fail('mode_mismatch'); end if;
    if d.status = 'completed' then perform private.fail('duel_completed'); end if;
  end if;
  insert into private.game_sessions (user_id, mode, duel_id) values (uid, p_mode, p_duel_id) returning id into sid;
  return sid;
end $$;

-- Burns a session (row-locked) and returns elapsed seconds, or a reason code.
create or replace function private.consume_session(p_uid uuid, p_session uuid, p_mode text, p_duel uuid,
                                                   out elapsed numeric, out reason text)
language plpgsql set search_path = '' as $$
declare s private.game_sessions;
begin
  select * into s from private.game_sessions where id = p_session for update;
  if not found or s.user_id <> p_uid then reason := 'invalid_session'; return; end if;
  if s.mode <> p_mode then reason := 'mode_mismatch'; return; end if;
  if p_duel is not null and s.duel_id is distinct from p_duel then reason := 'invalid_session'; return; end if;
  if s.used_at is not null then reason := 'session_used'; return; end if;
  if s.expires_at < now() then reason := 'session_expired'; return; end if;
  update private.game_sessions set used_at = now() where id = p_session;
  elapsed := extract(epoch from now() - s.started_at);
end $$;

-- Ranked score submission (port of the submitScore Cloud Function).
create or replace function public.submit_score(
  p_session_id uuid, p_mode text, p_score int, p_max_combo int, p_taps int, p_perfects int)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := private.require_uid();
  v_elapsed numeric;
  v_reason text;
  v_verdict text;
  prev int;
  uname text;
begin
  perform private.check_rate(uid, 'submit_score', 30, interval '1 minute');
  if p_session_id is null then return jsonb_build_object('accepted', false, 'reason', 'session_required'); end if;
  if p_score is null or p_max_combo is null or p_taps is null or p_perfects is null then
    perform private.fail('invalid_payload');
  end if;

  select c.elapsed, c.reason into v_elapsed, v_reason
    from private.consume_session(uid, p_session_id, p_mode, null) c;
  if v_reason is not null then return jsonb_build_object('accepted', false, 'reason', v_reason); end if;

  v_verdict := private.check_plausibility(p_mode, p_score, p_max_combo, p_taps, p_perfects, v_elapsed, true);
  update private.game_sessions set verdict = coalesce(v_verdict, 'accepted') where id = p_session_id;
  if v_verdict is not null then
    raise log 'submit_score rejected uid=% mode=% reason=%', uid, p_mode, v_verdict;
    return jsonb_build_object('accepted', false, 'reason', v_verdict);
  end if;

  select username into uname from public.profiles where id = uid;
  if uname is null then return jsonb_build_object('accepted', false, 'reason', 'profile_required'); end if;

  select score into prev from public.leaderboard_scores where mode = p_mode and user_id = uid for update;
  if prev is null or p_score > prev then
    insert into public.leaderboard_scores (mode, user_id, username, score, max_combo, session_id, updated_at)
    values (p_mode, uid, uname, p_score, p_max_combo, p_session_id, now())
    on conflict (mode, user_id) do update
      set username = excluded.username, score = excluded.score, max_combo = excluded.max_combo,
          session_id = excluded.session_id, updated_at = now();
  end if;
  return jsonb_build_object('accepted', true, 'ranked', true,
                            'newBest', prev is null or p_score > prev, 'verifiedScore', p_score);
end $$;

-- Duel score submission. Idempotent per session; completes the duel atomically
-- when the second score lands. Implausible scores are recorded as 0 (flagged)
-- so the match still resolves deterministically.
create or replace function public.submit_duel_score(
  p_duel_id uuid, p_session_id uuid, p_score int, p_max_combo int, p_taps int, p_perfects int)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := private.require_uid();
  d public.duels;
  is_host boolean;
  v_elapsed numeric;   -- NULL unless a valid server-timed session was consumed
  v_reason text;
  v_verdict text;
  final_score int;
  verified boolean;
begin
  perform private.check_rate(uid, 'submit_duel_score', 30, interval '1 minute');
  if p_score is null or p_max_combo is null or p_taps is null or p_perfects is null then
    perform private.fail('invalid_payload');
  end if;

  select * into d from public.duels where id = p_duel_id for update;
  if not found or (uid is distinct from d.host_id and uid is distinct from d.guest_id) then
    perform private.fail('duel_not_found');
  end if;
  is_host := uid = d.host_id;

  -- Duplicate submission: report the stored result instead of overwriting.
  if (is_host and d.host_score is not null) or (not is_host and d.guest_score is not null) then
    return jsonb_build_object('accepted', true, 'duplicate', true, 'status', d.status);
  end if;
  if d.status <> 'in_progress' then perform private.fail('duel_not_in_progress'); end if;

  if p_session_id is not null then
    select c.elapsed, c.reason into v_elapsed, v_reason
      from private.consume_session(uid, p_session_id, d.mode, d.id) c;
    if v_reason is not null and v_reason <> 'session_used' then
      v_verdict := v_reason;
    end if;
  end if;
  if v_verdict is null then
    v_verdict := private.check_plausibility(d.mode, p_score, p_max_combo, p_taps, p_perfects, v_elapsed, false);
  end if;
  verified := v_verdict is null and v_elapsed is not null;
  final_score := case when v_verdict is null then p_score else 0 end;
  if v_verdict is not null then
    raise log 'submit_duel_score flagged uid=% duel=% reason=%', uid, d.id, v_verdict;
  end if;

  if is_host then
    update public.duels set host_score = final_score, host_combo = case when v_verdict is null then p_max_combo else 0 end,
           host_verified = verified, host_submitted_at = now(),
           status = case when guest_score is not null then 'completed' else status end,
           completed_at = case when guest_score is not null then now() else completed_at end
     where id = d.id returning * into d;
  else
    update public.duels set guest_score = final_score, guest_combo = case when v_verdict is null then p_max_combo else 0 end,
           guest_verified = verified, guest_submitted_at = now(),
           status = case when host_score is not null then 'completed' else status end,
           completed_at = case when host_score is not null then now() else completed_at end
     where id = d.id returning * into d;
  end if;
  return jsonb_build_object('accepted', v_verdict is null, 'reason', v_verdict, 'status', d.status);
end $$;

-- ---------------------------------------------------------------------------
-- Friends (was friend_requests, friendships, friend_request_state)
-- ---------------------------------------------------------------------------
create table public.friend_requests (
  id            uuid primary key default gen_random_uuid(),
  from_uid      uuid not null references auth.users(id) on delete cascade,
  to_uid        uuid not null references auth.users(id) on delete cascade,
  from_username text not null default '',
  from_avatar   text not null default 'default',
  to_username   text not null default '',
  to_avatar     text not null default 'default',
  status        text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  check (from_uid <> to_uid)
);
-- One pending request per pair (replaces the friend_request_state guard doc).
create unique index friend_requests_pending_pair_key on public.friend_requests
  (least(from_uid, to_uid), greatest(from_uid, to_uid)) where status = 'pending';
create index friend_requests_to_idx   on public.friend_requests (to_uid, status, created_at desc);
create index friend_requests_from_idx on public.friend_requests (from_uid, status, created_at desc);
alter table public.friend_requests enable row level security;
create policy "friend request visible to sender and receiver" on public.friend_requests
  for select to authenticated
  using ((select auth.uid()) = from_uid or (select auth.uid()) = to_uid);

create table public.friendships (
  user_a     uuid not null references auth.users(id) on delete cascade,
  user_b     uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index friendships_user_b_idx on public.friendships (user_b);
alter table public.friendships enable row level security;
create policy "friendship visible to its members" on public.friendships
  for select to authenticated
  using ((select auth.uid()) = user_a or (select auth.uid()) = user_b);

create or replace function private.are_friends(a uuid, b uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.friendships where user_a = least(a, b) and user_b = greatest(a, b))
$$;

create or replace function public.send_friend_request(p_friend_code text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); target uuid; me record; them record; rid uuid;
begin
  perform private.check_rate(uid, 'friend_request', 10, interval '1 minute');
  select id into target from private.profile_data where friend_code = upper(trim(coalesce(p_friend_code, '')));
  -- NULL (not an exception) so the rate-limit hit commits: friend codes can't be enumerated.
  if target is null then return null; end if;
  if target = uid then perform private.fail('cannot_add_self'); end if;
  if private.are_friends(uid, target) then perform private.fail('already_friends'); end if;
  select * into me from private.profile_identity(uid);
  select username, avatar into them from public.profiles where id = target;
  begin
    insert into public.friend_requests (from_uid, to_uid, from_username, from_avatar, to_username, to_avatar)
    values (uid, target, me.username, me.avatar, coalesce(them.username, ''), coalesce(them.avatar, 'default'))
    returning id into rid;
  exception when unique_violation then
    perform private.fail('request_pending');
  end;
  return rid;
end $$;

create or replace function public.respond_friend_request(p_request_id uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); r public.friend_requests;
begin
  select * into r from public.friend_requests where id = p_request_id for update;
  if not found or r.to_uid <> uid then perform private.fail('request_not_found'); end if;
  if r.status <> 'pending' then perform private.fail('request_not_pending'); end if;
  update public.friend_requests
     set status = case when p_accept then 'accepted' else 'rejected' end, responded_at = now()
   where id = r.id;
  if p_accept then
    insert into public.friendships (user_a, user_b)
    values (least(r.from_uid, r.to_uid), greatest(r.from_uid, r.to_uid))
    on conflict do nothing;
  end if;
end $$;

create or replace function public.cancel_friend_request(p_request_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); r public.friend_requests;
begin
  select * into r from public.friend_requests where id = p_request_id for update;
  if not found or r.from_uid <> uid then perform private.fail('request_not_found'); end if;
  if r.status <> 'pending' then perform private.fail('request_not_pending'); end if;
  update public.friend_requests set status = 'cancelled', responded_at = now() where id = r.id;
end $$;

-- ---------------------------------------------------------------------------
-- Duel invitations (was duel_invitations + duel_invite_state)
-- ---------------------------------------------------------------------------
create table public.duel_invitations (
  id            uuid primary key default gen_random_uuid(),
  from_uid      uuid not null references auth.users(id) on delete cascade,
  to_uid        uuid not null references auth.users(id) on delete cascade,
  from_username text not null default '',
  from_avatar   text not null default 'default',
  to_username   text not null default '',
  to_avatar     text not null default 'default',
  duel_id       uuid references public.duels(id) on delete set null,
  duel_code     text not null default '',
  mode          text not null references private.mode_rules(mode),
  status        text not null default 'pending'
                check (status in ('pending','accepted','in_progress','rejected','cancelled','expired')),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '10 minutes',
  responded_at  timestamptz,
  check (from_uid <> to_uid)
);
create unique index duel_invitations_pending_pair_key on public.duel_invitations
  (least(from_uid, to_uid), greatest(from_uid, to_uid)) where status = 'pending';
create index duel_invitations_to_idx   on public.duel_invitations (to_uid, status, created_at desc);
create index duel_invitations_from_idx on public.duel_invitations (from_uid, status, created_at desc);
create index duel_invitations_duel_idx on public.duel_invitations (duel_id);
alter table public.duel_invitations enable row level security;
create policy "duel invitation visible to sender and receiver" on public.duel_invitations
  for select to authenticated
  using ((select auth.uid()) = from_uid or (select auth.uid()) = to_uid);

-- Creates the duel and the invitation in ONE transaction (Firestore did two steps).
create or replace function public.send_duel_invitation(p_to_uid uuid, p_mode text default 'duel')
returns public.duel_invitations
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); d public.duels; them record; inv public.duel_invitations;
begin
  perform private.check_rate(uid, 'duel_invite', 10, interval '1 minute');
  if p_to_uid is null or p_to_uid = uid then perform private.fail('cannot_invite_self'); end if;
  if not private.are_friends(uid, p_to_uid) then perform private.fail('not_friends'); end if;

  -- Lapse stale pending invites for this pair so they stop blocking.
  update public.duel_invitations set status = 'expired', responded_at = now()
   where status = 'pending' and expires_at <= now()
     and least(from_uid, to_uid) = least(uid, p_to_uid)
     and greatest(from_uid, to_uid) = greatest(uid, p_to_uid);

  if exists (select 1 from public.duel_invitations where status = 'pending'
               and least(from_uid, to_uid) = least(uid, p_to_uid)
               and greatest(from_uid, to_uid) = greatest(uid, p_to_uid)) then
    perform private.fail('invite_pending');
  end if;

  d := private.create_duel_for(uid, coalesce(p_mode, 'duel'));
  select username, avatar into them from public.profiles where id = p_to_uid;
  begin
    insert into public.duel_invitations (from_uid, to_uid, from_username, from_avatar, to_username, to_avatar,
                                         duel_id, duel_code, mode)
    values (uid, p_to_uid, d.host_name, coalesce(d.host_avatar, 'default'),
            coalesce(them.username, ''), coalesce(them.avatar, 'default'), d.id, d.code, d.mode)
    returning * into inv;
  exception when unique_violation then
    perform private.fail('invite_pending');
  end;
  return inv;
end $$;

-- Accept = join the duel + mark accepted, atomically.
create or replace function public.accept_duel_invitation(p_invitation_id uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); inv public.duel_invitations; d public.duels;
begin
  select * into inv from public.duel_invitations where id = p_invitation_id for update;
  if not found or inv.to_uid <> uid then perform private.fail('invitation_not_found'); end if;
  if inv.status <> 'pending' then perform private.fail('invitation_not_pending'); end if;
  if inv.expires_at <= now() then perform private.fail('invitation_expired'); end if;
  select * into d from public.duels where id = inv.duel_id for update;
  if not found then perform private.fail('duel_unavailable'); end if;
  d := private.join_duel_row(uid, d);
  update public.duel_invitations set status = 'accepted', responded_at = now() where id = inv.id;
  return d.id;
end $$;

create or replace function private.close_invitation(p_id uuid, p_uid uuid, p_as_receiver boolean, p_status text)
returns void language plpgsql set search_path = '' as $$
declare inv public.duel_invitations;
begin
  select * into inv from public.duel_invitations where id = p_id for update;
  if not found or (p_as_receiver and inv.to_uid <> p_uid) or (not p_as_receiver and inv.from_uid <> p_uid) then
    perform private.fail('invitation_not_found');
  end if;
  if inv.status <> 'pending' then perform private.fail('invitation_not_pending'); end if;
  update public.duel_invitations set status = p_status, responded_at = now() where id = inv.id;
  -- The unjoined duel created for this invite is now useless.
  delete from public.duels where id = inv.duel_id and status = 'waiting' and guest_id is null;
end $$;

create or replace function public.reject_duel_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin perform private.close_invitation(p_invitation_id, private.require_uid(), true, 'rejected'); end $$;

create or replace function public.cancel_duel_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin perform private.close_invitation(p_invitation_id, private.require_uid(), false, 'cancelled'); end $$;

-- Host entered the game for an accepted invite.
create or replace function public.mark_duel_invitation_in_progress(p_invitation_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); n int;
begin
  update public.duel_invitations set status = 'in_progress'
   where id = p_invitation_id and from_uid = uid and status = 'accepted';
  get diagnostics n = row_count;
  return n = 1;
end $$;

-- ---------------------------------------------------------------------------
-- Privileges: read-only tables, RPC-only writes
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
grant select on public.profiles, public.leaderboard_scores, public.duels,
                public.friend_requests, public.friendships, public.duel_invitations to authenticated;

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon;
grant execute on function
  public.save_profile(jsonb), public.get_my_profile(), public.get_player_profiles(uuid[]),
  public.is_username_available(text), public.server_day(), public.get_leaderboard(text, int),
  public.create_duel(text), public.join_duel(text), public.start_game_session(text, uuid),
  public.submit_score(uuid, text, int, int, int, int),
  public.submit_duel_score(uuid, uuid, int, int, int, int),
  public.send_friend_request(text), public.respond_friend_request(uuid, boolean),
  public.cancel_friend_request(uuid), public.send_duel_invitation(uuid, text),
  public.accept_duel_invitation(uuid), public.reject_duel_invitation(uuid),
  public.cancel_duel_invitation(uuid), public.mark_duel_invitation_in_progress(uuid)
to authenticated;
-- Internal helpers are executed by definer functions (owner: postgres); the
-- invoker-rights get_leaderboard() only needs mode_rules (granted above).

-- New objects created later must not become client-callable by accident.
alter default privileges in schema public revoke execute on functions from public, anon;
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: participants get change notifications for these tables (RLS applies).
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.duels, public.duel_invitations, public.friend_requests;

-- ---------------------------------------------------------------------------
-- Retention (run daily by pg_cron, see below)
-- ---------------------------------------------------------------------------
create or replace function private.cleanup()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.duel_invitations set status = 'expired', responded_at = now()
   where status = 'pending' and expires_at <= now();
  delete from public.duels where status = 'waiting' and created_at < now() - interval '24 hours';
  -- Abandoned matches (one side never played) and old history.
  delete from public.duels where status = 'in_progress' and coalesce(joined_at, created_at) < now() - interval '7 days';
  delete from public.duels where status = 'completed' and completed_at < now() - interval '180 days';
  delete from public.duel_invitations where created_at < now() - interval '30 days';
  delete from public.friend_requests where status <> 'pending' and created_at < now() - interval '30 days';
  delete from private.game_sessions where expires_at < now() - interval '1 day';
  delete from private.rate_limits where window_start < now() - interval '1 day';
end $$;

create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('perfecttap-daily-cleanup', '17 3 * * *', 'select private.cleanup()');
