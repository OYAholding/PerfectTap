-- PerfectTap 1.1.0 release gate (14.11.2026)
-- 1. Just-in-time legacy migration: claim-legacy-account reads the player's CURRENT Firestore
--    document (with the player's own verified Firebase ID token) and passes it here, so a claim
--    no longer depends only on the last periodic snapshot. Same guarantees as before:
--    tombstones win, an already-claimed player is never overwritten, one Firebase account maps
--    to exactly one Supabase user, and the whole claim is one transaction.
-- 2. Username moderation (public usernames are user-generated content):
--    blocklist checked by is_username_available() and on first save, legacy names on claim,
--    and private.moderate_username() for reports (renames everywhere the name is copied).

-- ───────────── Username moderation ─────────────
create table private.blocked_username_terms (
  term text primary key check (term ~ '^[a-z0-9]{3,20}$'),
  kind text not null default 'contains' check (kind in ('contains', 'exact'))
);
alter table private.blocked_username_terms enable row level security;

create table private.moderation_log (
  id           bigint generated always as identity primary key,
  user_id      uuid not null,
  old_username text not null,
  new_username text not null,
  reason       text not null,
  created_at   timestamptz not null default now()
);
create index moderation_log_user_idx on private.moderation_log (user_id);
alter table private.moderation_log enable row level security;

-- Lower-case, undo common digit/symbol swaps, drop separators.
create or replace function private.normalize_username(u text)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(translate(lower(coalesce(u, '')), '01345789@$', 'oieastbgas'), '[^a-z]', '', 'g')
$$;

create or replace function private.username_blocked(u text)
returns boolean language sql stable security definer set search_path = '' as $$
  with n as (select private.normalize_username(u) as s)
  select exists (
    select 1 from private.blocked_username_terms t, n
    where (t.kind = 'exact' and n.s = t.term)
       or (t.kind = 'contains' and (n.s like '%' || t.term || '%'
                                    or regexp_replace(n.s, '(.)\1+', '\1', 'g') like '%' || t.term || '%'))
  )
$$;

-- Neutral replacement that satisfies the username format: Player_ + hex, unique.
create or replace function private.neutral_username(p_user uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare h text := md5(p_user::text); n int := 8; cand text;
begin
  loop
    cand := 'Player_' || substr(h, 1, n);
    exit when n >= 13 or not exists (select 1 from public.profiles where lower(username) = lower(cand) and id <> p_user);
    n := n + 1;
  end loop;
  return cand;
end $$;

-- Moderator tool (SQL editor only; no API grant). Renames a reported player everywhere the
-- name is shown. The player keeps all progress; later saves keep the new name.
create or replace function private.moderate_username(p_user uuid, p_reason text default 'reported')
returns text language plpgsql security definer set search_path = '' as $$
declare old text; neu text;
begin
  select username into old from public.profiles where id = p_user for update;
  if old is null then perform private.fail('not_found'); end if;
  neu := private.neutral_username(p_user);
  update public.profiles set username = neu where id = p_user;
  update public.leaderboard_scores set username = neu where user_id = p_user;
  update public.duels set host_name = neu where host_id = p_user;
  update public.duels set guest_name = neu where guest_id = p_user;
  update public.friend_requests set from_username = neu where from_uid = p_user;
  update public.friend_requests set to_username = neu where to_uid = p_user;
  update public.duel_invitations set from_username = neu where from_uid = p_user;
  update public.duel_invitations set to_username = neu where to_uid = p_user;
  insert into private.moderation_log (user_id, old_username, new_username, reason)
  values (p_user, coalesce(old, ''), neu, left(coalesce(p_reason, 'reported'), 200));
  return neu;
end $$;

-- Player reports (server side, ready for an in-app "Report" button; until then reports arrive
-- by email via the support page). One open report per reporter/player pair, rate limited.
create table private.player_reports (
  id          bigint generated always as identity primary key,
  reporter_id uuid not null,
  reported_id uuid not null,
  username    text not null,
  reason      text not null default 'offensive_name',
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  unique (reporter_id, reported_id)
);
alter table private.player_reports enable row level security;

create or replace function private.report_player(p_reported uuid, p_reason text default 'offensive_name')
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid(); uname text;
begin
  perform private.check_rate(uid, 'report_player', 10, interval '1 hour');
  if p_reported is null or p_reported = uid then perform private.fail('invalid_payload'); end if;
  select username into uname from public.profiles where id = p_reported;
  if uname is null then perform private.fail('not_found'); end if;
  insert into private.player_reports (reporter_id, reported_id, username, reason)
  values (uid, p_reported, uname, left(coalesce(nullif(p_reason, ''), 'offensive_name'), 100))
  on conflict (reporter_id, reported_id) do nothing;
end $$;
-- Same shape as 20261112100328_rpc_invoker_wrappers.sql: invoker wrapper in public.
create or replace function public.report_player(p_reported uuid, p_reason text default 'offensive_name')
returns void language sql volatile security invoker set search_path = ''
as 'select private.report_player(p_reported, p_reason)';
revoke all on function private.report_player(uuid, text), public.report_player(uuid, text) from public, anon;
grant execute on function private.report_player(uuid, text), public.report_player(uuid, text) to authenticated;

insert into private.blocked_username_terms (term, kind) values
  -- Profanity / slurs (substring match after normalisation). Extend with SQL as needed.
  ('fuck','contains'), ('shit','contains'), ('bitch','contains'), ('cunt','contains'),
  ('nigger','contains'), ('nigga','contains'), ('faggot','contains'), ('whore','contains'),
  ('slut','contains'), ('pussy','contains'), ('penis','contains'), ('vagina','contains'),
  ('porn','contains'), ('asshole','contains'), ('bastard','contains'), ('retard','contains'),
  ('kike','contains'), ('wank','contains'), ('twat','contains'), ('dildo','contains'),
  ('jizz','contains'), ('hitler','contains'), ('pedophile','contains'), ('kkk','contains'),
  -- Impersonation (exact match after normalisation).
  ('admin','exact'), ('administrator','exact'), ('moderator','exact'), ('support','exact'),
  ('official','exact'), ('perfecttap','exact'), ('perfecttapteam','exact'), ('apple','exact'),
  ('appreview','exact'), ('staff','exact'), ('system','exact')
on conflict do nothing;

-- Body of the public.is_username_available wrapper (see 20261112100328_rpc_invoker_wrappers.sql).
create or replace function private.is_username_available(p_username text)
returns boolean
language sql stable security definer set search_path = '' as $$
  select not private.username_blocked(p_username) and not exists (
    select 1 from public.profiles
    where lower(username) = lower(trim(p_username)) and username <> '' and id <> auth.uid()
  )
$$;

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
    -- A moderated (renamed) player keeps the server name. The app may still hold the old
    -- name and send it with every save; ignoring it keeps progress sync working.
    if exists (select 1 from private.moderation_log m where m.user_id = uid) then
      new_username := cur.username;
    else
      perform private.fail('username_immutable');
    end if;
  end if;
  -- First choice of a name: the app asks is_username_available() first, which refuses blocked
  -- names. If a blocked name still arrives (offline / older client), replace it with a neutral
  -- one instead of failing: a failed save here would stop all later progress sync.
  if coalesce(cur.username, '') = '' and new_username <> '' and private.username_blocked(new_username) then
    insert into private.moderation_log (user_id, old_username, new_username, reason)
    values (uid, new_username, private.neutral_username(uid), 'blocked_on_save');
    new_username := private.neutral_username(uid);
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

create or replace function public.claim_legacy_profile(p_user uuid, p_firebase_uid text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  existing private.legacy_claims;
  lp legacy.players;
  cur public.profiles;
  payload jsonb;
  username_conflict boolean := false;
  n_friends int := 0;
begin
  if p_user is null or coalesce(p_firebase_uid, '') = '' then perform private.fail('invalid_payload'); end if;

  -- Serialise concurrent claims of the same Firebase account.
  perform pg_advisory_xact_lock(hashtext('legacy_claim:' || p_firebase_uid));

  if exists (select 1 from private.legacy_tombstones where firebase_uid = p_firebase_uid) then
    return jsonb_build_object('status', 'account_deleted');
  end if;

  select * into existing from private.legacy_claims where firebase_uid = p_firebase_uid;
  if found then
    return jsonb_build_object('status', case when existing.user_id = p_user then 'already_claimed' else 'claimed_elsewhere' end,
                              'user_id', existing.user_id);
  end if;
  if exists (select 1 from private.legacy_claims where user_id = p_user) then
    return jsonb_build_object('status', 'user_already_linked');
  end if;

  select * into lp from legacy.players where firebase_uid = p_firebase_uid;
  select * into cur from public.profiles where id = p_user;

  if lp.firebase_uid is not null then
    if cur.id is not null and cur.username <> '' and cur.username <> lp.username then
      return jsonb_build_object('status', 'user_has_profile');
    end if;

    payload := lp.data - array['uid', 'friends', 'server_day_probe_ts'];
    -- Taken or blocked legacy name → empty; the app then asks the player to choose a new one.
    if lp.username <> '' and (private.username_blocked(lp.username) or exists (select 1 from public.profiles
                                     where lower(username) = lower(lp.username) and id <> p_user)) then
      username_conflict := true;
      payload := payload || jsonb_build_object('username', '');
    end if;
    if lp.friend_code is not null and exists (select 1 from private.profile_data
                                              where friend_code = lp.friend_code and id <> p_user) then
      payload := payload - 'friend_code';
    end if;
    -- Legacy data may predate validation; clamp instead of failing the claim.
    payload := payload
      || jsonb_build_object('coins', least(greatest(coalesce((payload->>'coins')::numeric, 0), 0), 100000000)::int)
      || jsonb_build_object('level', least(greatest(coalesce((payload->>'level')::numeric, 1), 1), 10000)::int);
    perform private.save_profile_for(p_user, payload);

    insert into public.leaderboard_scores (mode, user_id, username, score, max_combo)
    select l.mode, p_user, coalesce(nullif(l.username, ''), lp.username), l.score, l.max_combo
    from legacy.leaderboard l
    where l.firebase_uid = p_firebase_uid
      and exists (select 1 from private.mode_rules m where m.mode = l.mode)
    on conflict (mode, user_id) do update set score = greatest(public.leaderboard_scores.score, excluded.score);
  end if;

  insert into private.legacy_claims (firebase_uid, user_id) values (p_firebase_uid, p_user);

  -- Re-create friendships whose other side has already claimed.
  insert into public.friendships (user_a, user_b, created_at)
  select least(p_user, c.user_id), greatest(p_user, c.user_id), coalesce(f.created_at, now())
  from legacy.friendships f
  join private.legacy_claims c
    on c.firebase_uid = case when f.uid_a = p_firebase_uid then f.uid_b else f.uid_a end
  where (f.uid_a = p_firebase_uid or f.uid_b = p_firebase_uid) and c.user_id <> p_user
  on conflict do nothing;
  get diagnostics n_friends = row_count;

  return jsonb_build_object('status', case when lp.firebase_uid is null then 'no_legacy_data' else 'claimed' end,
                            'username_conflict', username_conflict, 'friendships_restored', n_friends);
end $$;

-- ───────────── Just-in-time legacy refresh ─────────────
-- Replaces the snapshot of ONE unclaimed, non-deleted player with the document the Edge
-- Function just read from Firestore using that player's verified Firebase ID token.
create or replace function private.legacy_refresh_player(p_firebase_uid text, p_data jsonb, p_friend_uids text[])
returns text language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(p_firebase_uid, '') = '' or length(p_firebase_uid) > 128 then return 'invalid'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text) > 262144 then return 'invalid'; end if;
  if p_data ? 'uid' and p_data->>'uid' is distinct from p_firebase_uid then return 'uid_mismatch'; end if;
  perform pg_advisory_xact_lock(hashtext('legacy_claim:' || p_firebase_uid));
  if exists (select 1 from private.legacy_tombstones where firebase_uid = p_firebase_uid) then return 'account_deleted'; end if;
  if exists (select 1 from private.legacy_claims where firebase_uid = p_firebase_uid) then return 'already_claimed'; end if;

  insert into legacy.raw_docs (collection, doc_id, parent_id, data) values ('players', p_firebase_uid, '', p_data)
  on conflict (collection, parent_id, doc_id) do update set data = excluded.data;
  insert into legacy.players (firebase_uid, username, friend_code, data)
  values (p_firebase_uid, coalesce(p_data->>'username', ''), nullif(upper(p_data->>'friend_code'), ''), p_data)
  on conflict (firebase_uid) do update
    set username = excluded.username, friend_code = excluded.friend_code, data = excluded.data;
  -- Friendships Firestore confirmed for this player (canonical docs or mutual mirrors).
  insert into legacy.friendships (uid_a, uid_b, created_at)
  select least(p_firebase_uid, f), greatest(p_firebase_uid, f), null
  from unnest((coalesce(p_friend_uids, '{}'::text[]))[1:200]) f
  where coalesce(f, '') <> '' and f <> p_firebase_uid and length(f) <= 128
    and not exists (select 1 from private.legacy_tombstones t where t.firebase_uid = f)
  on conflict do nothing;
  return 'refreshed';
end $$;

-- Edge Function entry point: refresh (if fresh data was read) + claim, in ONE transaction.
-- A bad or unusable fresh document never blocks the claim: it falls back to the snapshot.
create or replace function public.claim_legacy_profile_fresh(p_user uuid, p_firebase_uid text,
                                                             p_fresh jsonb default null, p_friend_uids text[] default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare refresh text := 'skipped'; res jsonb;
begin
  if p_fresh is not null then
    begin
      refresh := private.legacy_refresh_player(p_firebase_uid, p_fresh, p_friend_uids);
    exception when others then
      refresh := 'error';
    end;
  end if;
  res := public.claim_legacy_profile(p_user, p_firebase_uid);
  return res || jsonb_build_object('fresh', refresh);
end $$;

revoke execute on function public.claim_legacy_profile_fresh(uuid, text, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.claim_legacy_profile_fresh(uuid, text, jsonb, text[]) to service_role;
revoke execute on function private.legacy_refresh_player(text, jsonb, text[]), private.moderate_username(uuid, text),
  private.neutral_username(uuid), private.username_blocked(text), private.normalize_username(text)
  from public, anon, authenticated;
