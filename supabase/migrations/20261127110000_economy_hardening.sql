-- PerfectTap 1.2.0 — economy hardening after the 2026-11-27 adversarial review.
-- Each block names the finding it closes (docs/SECURITY_REVIEW_1.2.0.md).
-- Nothing here activates the economy or changes a balance; the 1.1.x path is
-- unchanged while no config has ever been approved.

-- ---------------------------------------------------------------------------
-- C1 (critical): replaying an existing event key bought shop items for free
-- (apply_economy_delta answered `duplicate`, the item was granted anyway).
-- Now: the item is granted only when the debit was applied; a replay of the
-- SAME purchase returns `duplicate`, any other replay is refused.
-- L1: lock order economy -> profile_data (same as every other writer).
-- ---------------------------------------------------------------------------
create or replace function private.purchase_economy_item(p_user uuid, p_event_key uuid, p_item_id text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; item private.economy_shop_items; pd private.profile_data;
        prior private.economy_events; e private.economy; out jsonb;
begin
  cfg := private.require_active_economy();
  perform private.check_rate(p_user, 'economy_shop_purchase', 30, interval '1 minute');
  select * into item from private.economy_shop_items
  where item_id = p_item_id and enabled and config_version = cfg.version;
  if not found then perform private.fail('item_unavailable'); end if;
  if p_event_key is null then perform private.fail('invalid_payload'); end if;

  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;
  select * into pd from private.profile_data where id = p_user for update;
  if not found then perform private.fail('profile_required'); end if;

  select * into prior from private.economy_events where user_id = p_user and event_key = p_event_key;
  if found then
    if prior.source = 'shop_purchase' and prior.metadata->>'item_id' = p_item_id then
      return jsonb_build_object('status','duplicate','balance',e.confirmed_balance,
                                'coinDebt',e.coin_debt,'itemID',p_item_id);
    end if;
    perform private.fail('invalid_payload');
  end if;

  if coalesce(pd.data->'owned_items','[]'::jsonb) ? p_item_id then
    return jsonb_build_object('status','already_owned','itemID',p_item_id);
  end if;
  out := private.apply_economy_delta(p_user, p_event_key, 'shop_purchase', -item.price,
    cfg.version, jsonb_build_object('item_id', p_item_id));
  if out->>'status' is distinct from 'applied' then perform private.fail('invalid_payload'); end if;
  perform private.set_profile_item(p_user, p_item_id, true);
  return out || jsonb_build_object('itemID', p_item_id);
end $$;
revoke all on function private.purchase_economy_item(uuid, uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- C2 (critical) + H1 (high): legacy claims.
-- C2: the JIT refresh accepted a Firestore document for ANY Firebase uid,
--     including accounts created after the import, whose owner can write the
--     document freely. Such "JIT-only" players are now recorded; after an
--     owner activation their claim keeps no server-owned items, no premium /
--     no-ads / daily-streak state, and their coins go to human review (never
--     auto-accepted by reconcile_legacy_economy, which only reads `pending`).
-- H1: claiming legacy data on an account whose economy is already
--     `accepted` overwrote nothing in the ledger, and the next save pinned the
--     coins back to the confirmed balance (honest legacy coins lost). The
--     claimed coins now join the account's balance as a reviewed candidate.
-- Before any config was ever approved (today) claims behave exactly as in 1.1.
-- ---------------------------------------------------------------------------
create table private.legacy_jit_players (
  firebase_uid text primary key,
  first_seen   timestamptz not null default now()
);
alter table private.legacy_jit_players enable row level security;
revoke all on private.legacy_jit_players from public, anon, authenticated, service_role;

-- Firebase uids present in the import snapshot (before any JIT refresh).
create table private.legacy_snapshot_uids (firebase_uid text primary key);
alter table private.legacy_snapshot_uids enable row level security;
revoke all on private.legacy_snapshot_uids from public, anon, authenticated, service_role;
insert into private.legacy_snapshot_uids (firebase_uid)
select firebase_uid from legacy.players on conflict do nothing;

create or replace function private.after_legacy_claim_economy(p_user uuid, p_firebase_uid text)
returns void
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; pd private.profile_data; e private.economy;
        jit boolean; claimed bigint; server_items text[]; premium_ids text[]; v_data jsonb;
        new_status text; candidate bigint;
begin
  select * into cfg from private.economy_configs where approved_at is not null
  order by approved_at desc limit 1;
  if not found then return; end if;          -- pre-activation: unchanged 1.1 behaviour

  jit := not exists (select 1 from private.legacy_snapshot_uids where firebase_uid = p_firebase_uid);
  select * into pd from private.profile_data where id = p_user for update;
  if not found then return; end if;
  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;

  v_data := pd.data;
  claimed := case when v_data->>'coins' ~ '^[0-9]{1,15}$' then (v_data->>'coins')::bigint else 0 end;
  -- Server-owned state is never taken from a claimed document after activation.
  v_data := v_data - array['daily_reward_last_claim', 'daily_reward_streak']
               || jsonb_build_object('no_ads', e.no_ads, 'season_premium', false);
  if jit then
    server_items := private.server_owned_items(cfg);
    select coalesce(array_agg(item_id), '{}') into premium_ids from private.iap_products where item_id is not null;
    if jsonb_typeof(v_data->'owned_items') = 'array' then
      v_data := jsonb_set(v_data, '{owned_items}', coalesce((
        select jsonb_agg(x) from jsonb_array_elements_text(v_data->'owned_items') t(x)
        where not (x = any(server_items)) and (not (x = any(premium_ids)) or x = any(e.premium_items))), '[]'::jsonb));
    end if;
  end if;

  -- Claimed coins + whatever the account already holds = the reviewed candidate.
  candidate := claimed + case when e.legacy_status = 'accepted' then coalesce(e.confirmed_balance, 0) else 0 end;
  new_status := case when jit then 'review' else 'pending' end;
  update private.economy
  set legacy_status = new_status, legacy_opening_balance = candidate,
      confirmed_balance = coalesce(confirmed_balance, 0), updated_at = now()
  where user_id = p_user;
  update private.profile_data set data = jsonb_set(v_data, '{coins}', to_jsonb(candidate)), updated_at = now()
  where id = p_user;
  insert into private.legacy_economy_reviews as r
    (user_id, snapshot, legacy_candidate, confirmed_balance, status, reason_code)
  values (p_user, jsonb_build_object('claimed_at', now(), 'claimed_coins', claimed, 'jit_only', jit,
                                     'previous_status', e.legacy_status, 'previous_balance', e.confirmed_balance),
          candidate, coalesce(e.confirmed_balance, 0), new_status,
          case when jit then 'jit_only_legacy_claim' else 'legacy_claim_after_activation' end)
  on conflict (user_id) do update
    set snapshot = r.snapshot || excluded.snapshot, legacy_candidate = excluded.legacy_candidate,
        status = excluded.status, reason_code = excluded.reason_code, updated_at = now();
end $$;
revoke all on function private.after_legacy_claim_economy(uuid, text) from public, anon, authenticated, service_role;

create or replace function private.legacy_refresh_player(p_firebase_uid text, p_data jsonb, p_friend_uids text[])
returns text language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(p_firebase_uid, '') = '' or length(p_firebase_uid) > 128 then return 'invalid'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' or octet_length(p_data::text) > 262144 then return 'invalid'; end if;
  if p_data ? 'uid' and p_data->>'uid' is distinct from p_firebase_uid then return 'uid_mismatch'; end if;
  perform pg_advisory_xact_lock(hashtext('legacy_claim:' || p_firebase_uid));
  if exists (select 1 from private.legacy_tombstones where firebase_uid = p_firebase_uid) then return 'account_deleted'; end if;
  if exists (select 1 from private.legacy_claims where firebase_uid = p_firebase_uid) then return 'already_claimed'; end if;
  if not exists (select 1 from private.legacy_snapshot_uids where firebase_uid = p_firebase_uid) then
    insert into private.legacy_jit_players (firebase_uid) values (p_firebase_uid) on conflict do nothing;
  end if;

  insert into legacy.raw_docs (collection, doc_id, parent_id, data) values ('players', p_firebase_uid, '', p_data)
  on conflict (collection, parent_id, doc_id) do update set data = excluded.data;
  insert into legacy.players (firebase_uid, username, friend_code, data)
  values (p_firebase_uid, coalesce(p_data->>'username', ''), nullif(upper(p_data->>'friend_code'), ''), p_data)
  on conflict (firebase_uid) do update
    set username = excluded.username, friend_code = excluded.friend_code, data = excluded.data;
  insert into legacy.friendships (uid_a, uid_b, created_at)
  select least(p_firebase_uid, f), greatest(p_firebase_uid, f), null
  from unnest((coalesce(p_friend_uids, '{}'::text[]))[1:200]) f
  where coalesce(f, '') <> '' and f <> p_firebase_uid and length(f) <= 128
    and not exists (select 1 from private.legacy_tombstones t where t.firebase_uid = f)
  on conflict do nothing;
  return 'refreshed';
end $$;
revoke execute on function private.legacy_refresh_player(text, jsonb, text[]) from public, anon, authenticated;

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
  if res->>'status' = 'claimed' then
    perform private.after_legacy_claim_economy(p_user, p_firebase_uid);
  end if;
  return res || jsonb_build_object('fresh', refresh);
end $$;
revoke execute on function public.claim_legacy_profile_fresh(uuid, text, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.claim_legacy_profile_fresh(uuid, text, jsonb, text[]) to service_role;

-- ---------------------------------------------------------------------------
-- M2 (season premium never expired) + M3 (containment let clients add
-- server-owned items): sanitize_economy.
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
  if not found then
    -- M3: no active config. Before the first owner activation this is the
    -- unchanged 1.1 path. Once a config has ever been approved (e.g. during a
    -- containment), items that only the server may grant are still filtered:
    -- a client cannot add them while the economy is contained.
    out := private.sanitize_economy_legacy(uid, p);
    select * into cfg from private.economy_configs where approved_at is not null
    order by approved_at desc limit 1;
    if not found or out is null or jsonb_typeof(out) <> 'object'
       or jsonb_typeof(out->'owned_items') <> 'array' then
      return out;
    end if;
    select data into stored from private.profile_data where id = uid;
    server_items := private.server_owned_items(cfg);
    stored_items := case when jsonb_typeof(stored->'owned_items') = 'array' then stored->'owned_items' else '[]'::jsonb end;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into items from (
      select x from jsonb_array_elements_text(out->'owned_items') t(x)
      where not (x = any(server_items)) or stored_items ? x
      union
      select x from jsonb_array_elements_text(stored_items) t(x) where x = any(server_items)
    ) s;
    return jsonb_set(out, '{owned_items}', items);
  end if;
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
  -- M2: premium is per season and only from verified (SSV) ads this season;
  -- a stored or client-sent flag never carries it into another season.
  out := out || jsonb_build_object('season_premium',
    verified_ads >= coalesce((cfg.config->>'season_ads_required')::int, 2147483647));
  return out;
end $$;
revoke all on function private.sanitize_economy(uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- M5: client-reported achievement / challenge progress is rate limited.
-- Their coins per UTC day are capped by config `progress_daily_cap`; the
-- first claim of a day always passes (a single large reward is never stuck).
-- Over the cap the claim fails `progress_daily_limit`; the iOS outbox keeps
-- it (once-per-account events never expire) and it is paid on a later day.
-- ---------------------------------------------------------------------------
create or replace function private.enforce_progress_daily_cap()
returns trigger language plpgsql security definer set search_path = '' as $$
declare cap bigint; used bigint;
begin
  if new.source not in ('achievement', 'challenge') or coalesce(new.amount, 0) <= 0 then return new; end if;
  select (config->>'progress_daily_cap')::bigint into cap from private.economy_configs where active;
  if cap is null then return new; end if;
  select coalesce(sum(amount), 0) into used from private.economy_grants
  where user_id = new.user_id and source in ('achievement', 'challenge') and server_day = new.server_day;
  if used > 0 and used + new.amount > cap then perform private.fail('progress_daily_limit'); end if;
  return new;
end $$;
revoke all on function private.enforce_progress_daily_cap() from public, anon, authenticated;
create trigger economy_grants_progress_daily_cap
  before insert on private.economy_grants
  for each row execute function private.enforce_progress_daily_cap();

update private.economy_configs
set config = config || jsonb_build_object('progress_daily_cap', 3000)
where version = 'balanced-premium-rc1';

-- ---------------------------------------------------------------------------
-- H2 / M1 / L4: legacy reconciliation evidence. Sandbox purchases are not
-- paid evidence; account age counts for at most 180 days; a re-run after a
-- manual reset no longer collides on the ledger key.
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
                     where pl.user_id = e.user_id and ip.kind = 'coins' and pl.revoked_at is null
                       and pl.environment = 'Production'), 0)::bigint as paid,
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
    -- Account age counts for at most 180 days (an old account is not a mint).
    v_allow := rec.paid + p_base_allowance + p_daily_allowance * least(greatest(rec.age_days, 1), 180);
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
                private.deterministic_uuid('legacy_accept:' || rec.uid::text || ':' || rec.candidate::text), 'legacy_opening',
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

-- ---------------------------------------------------------------------------
-- L6: a refund for a deleted account must not fail forever (FK on the
-- tombstone). The tombstone keeps the transaction, without the user.
-- ---------------------------------------------------------------------------
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
    values (p_transaction_id, coalesce(nullif(p_original_transaction_id, ''), p_transaction_id),
            (select u.id from auth.users u where u.id = p_user), p_product_id,
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
grant execute on function private.revoke_purchase(text, timestamptz, text, text, text, uuid) to service_role;

-- Guard (unchanged invariant): nothing client-callable in `public` is SECURITY DEFINER.
do $check$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'public SECURITY DEFINER function still executable by authenticated';
  end if;
end $check$;
