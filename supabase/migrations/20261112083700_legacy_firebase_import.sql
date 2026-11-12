-- ============================================================================
-- Legacy Firebase import + lazy account claiming
-- ============================================================================
-- 1. scripts/migration/export-firestore.mjs dumps Firestore to NDJSON.
-- 2. Rows are \copy'd into legacy.raw_docs, then `select legacy.ingest();`.
-- 3. When a player first opens the Supabase build, the app sends its Firebase
--    ID token to the `claim-legacy-account` Edge Function, which verifies it
--    and calls public.claim_legacy_profile() with the service role. Progress,
--    verified leaderboard rows and friendships move to the new Supabase user.
-- Nothing here is reachable by anon/authenticated.
-- ============================================================================

create schema if not exists legacy;
revoke all on schema legacy from public, anon, authenticated;

create table legacy.raw_docs (
  collection text not null,           -- 'players' | 'friendships' | 'leaderboard'
  doc_id     text not null,
  parent_id  text not null default '', -- leaderboard: mode
  data       jsonb not null,
  primary key (collection, parent_id, doc_id)
);

create table legacy.players (
  firebase_uid text primary key,
  username     text not null default '',
  friend_code  text,
  data         jsonb not null
);
create table legacy.friendships (
  uid_a      text not null,
  uid_b      text not null,
  created_at timestamptz,
  primary key (uid_a, uid_b),
  check (uid_a < uid_b)
);
create table legacy.leaderboard (
  mode         text not null,
  firebase_uid text not null,
  username     text not null default '',
  score        int not null,
  max_combo    int not null default 0,
  primary key (mode, firebase_uid)
);
alter table legacy.raw_docs    enable row level security;
alter table legacy.players     enable row level security;
alter table legacy.friendships enable row level security;
alter table legacy.leaderboard enable row level security;

-- Firebase UID → Supabase user. One-to-one.
create table private.legacy_claims (
  firebase_uid text primary key,
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  claimed_at   timestamptz not null default now()
);
alter table private.legacy_claims enable row level security;

-- Firebase accounts whose owner deleted their PerfectTap account (never re-claimable).
create table private.legacy_tombstones (
  firebase_uid text primary key,
  deleted_at   timestamptz not null default now()
);
alter table private.legacy_tombstones enable row level security;

-- Idempotent: re-running after a fresh export refreshes unclaimed players only.
create or replace function legacy.ingest()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n_players int; n_friends int; n_lb int;
begin
  insert into legacy.players (firebase_uid, username, friend_code, data)
  select r.doc_id, coalesce(r.data->>'username', ''), nullif(upper(r.data->>'friend_code'), ''), r.data
  from legacy.raw_docs r
  where r.collection = 'players'
    and not exists (select 1 from private.legacy_tombstones t where t.firebase_uid = r.doc_id)
  on conflict (firebase_uid) do update
    set username = excluded.username, friend_code = excluded.friend_code, data = excluded.data
    where not exists (select 1 from private.legacy_claims c where c.firebase_uid = excluded.firebase_uid);
  get diagnostics n_players = row_count;

  insert into legacy.friendships (uid_a, uid_b, created_at)
  select least(ids->>0, ids->>1), greatest(ids->>0, ids->>1),
         nullif(r.data->>'created_at', '')::timestamptz
  from legacy.raw_docs r, lateral (select r.data->'user_ids' as ids) x
  where r.collection = 'friendships' and jsonb_array_length(ids) = 2 and ids->>0 <> ids->>1
    and not exists (select 1 from private.legacy_tombstones t where t.firebase_uid in (ids->>0, ids->>1))
  on conflict do nothing;
  get diagnostics n_friends = row_count;

  insert into legacy.leaderboard (mode, firebase_uid, username, score, max_combo)
  select r.parent_id, r.doc_id, coalesce(r.data->>'username', ''),
         (r.data->>'score')::int, coalesce((r.data->>'max_combo')::int, 0)
  from legacy.raw_docs r
  where r.collection = 'leaderboard'
    and not exists (select 1 from private.legacy_tombstones t where t.firebase_uid = r.doc_id)
    and jsonb_typeof(r.data->'score') = 'number'
    and (r.data->>'score')::numeric between 0 and 10000000
  on conflict (mode, firebase_uid) do update
    set score = greatest(legacy.leaderboard.score, excluded.score), username = excluded.username;
  get diagnostics n_lb = row_count;

  return jsonb_build_object('players', n_players, 'friendships', n_friends, 'leaderboard', n_lb);
end $$;

-- Moves one legacy player onto a Supabase user. Called only by the Edge Function.
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
    if lp.username <> '' and exists (select 1 from public.profiles
                                     where lower(username) = lower(lp.username) and id <> p_user) then
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

-- Called by the delete-account Edge Function right before auth.users deletion.
create or replace function public.purge_account_data(p_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare fb text;
begin
  select firebase_uid into fb from private.legacy_claims where user_id = p_user;
  if fb is not null then
    insert into private.legacy_tombstones (firebase_uid) values (fb) on conflict do nothing;
    delete from legacy.players where firebase_uid = fb;
    delete from legacy.leaderboard where firebase_uid = fb;
    delete from legacy.friendships where uid_a = fb or uid_b = fb;
    delete from legacy.raw_docs
     where doc_id = fb or (collection = 'friendships' and data->'user_ids' ? fb);
  end if;
  -- Unjoined duels this player hosted are useless to anyone else.
  delete from public.duels where host_id = p_user and status = 'waiting';
end $$;

-- Used by link-email / claim-legacy-account before assigning an email.
create or replace function public.edge_email_in_use(p_email text, p_except uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users where lower(email) = lower(p_email) and id <> p_except)
$$;

-- Rate limiter for Edge Functions (service role only).
create or replace function public.edge_check_rate(p_user uuid, p_action text, p_max int, p_window_seconds int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.check_rate(p_user, p_action, p_max, make_interval(secs => p_window_seconds));
end $$;

revoke execute on function public.claim_legacy_profile(uuid, text), public.edge_check_rate(uuid, text, int, int),
  public.purge_account_data(uuid), public.edge_email_in_use(text, uuid) from public, anon, authenticated;
grant execute on function public.claim_legacy_profile(uuid, text), public.edge_check_rate(uuid, text, int, int),
  public.purge_account_data(uuid), public.edge_email_in_use(text, uuid) to service_role;
revoke execute on function legacy.ingest() from public, anon, authenticated;

-- Future helpers in private/legacy must never become client-callable by default.
alter default privileges in schema private revoke execute on functions from public;
alter default privileges in schema legacy  revoke execute on functions from public;
