-- PerfectTap 1.2.0 — internal support & operations toolkit (no admin app).
--
-- Every function lives in `private`, is SECURITY DEFINER with an empty
-- search_path, and is executable ONLY by the database owner (`postgres`,
-- i.e. a person holding the DB connection string). Not by anon,
-- authenticated, or service_role: a leaked Edge Function key cannot reach
-- support powers. Operators use scripts/support/pt-support.sh.
--
-- Read helpers never write. Mutating helpers:
--   * require operator, ticket and a reason (>= 10 chars);
--   * are idempotent per (action, ticket, user) via a deterministic event key;
--   * go through the existing ledger primitives (apply_economy_delta), so the
--     non-negative balance invariant and the ledger trail are unchanged;
--   * write one row to private.support_actions (append-only audit log).
-- coin_debt is never touched (stays disabled).

create table private.support_actions (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  operator    text not null check (char_length(operator) between 2 and 64),
  action      text not null check (action in (
                'adjust_balance', 'set_legacy_opening', 'economy_containment', 'purchase_containment')),
  user_id     uuid references auth.users(id) on delete set null,
  ticket      text not null check (ticket ~ '^[A-Za-z0-9_.:#-]{2,64}$'),
  reason      text not null check (char_length(reason) between 10 and 500),
  event_key   uuid,
  details     jsonb not null default '{}'::jsonb,
  unique (action, ticket, user_id)
);
alter table private.support_actions enable row level security;
revoke all on private.support_actions from public, anon, authenticated, service_role;

-- Append-only: no UPDATE/DELETE, even for the owner, without dropping the trigger.
create or replace function private.support_actions_append_only()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'support_actions is append-only';
end $$;
create trigger support_actions_append_only
  before update or delete on private.support_actions
  for each row execute function private.support_actions_append_only();

create or replace function private.support_require(p_operator text, p_ticket text, p_reason text)
returns void language plpgsql set search_path = '' as $$
begin
  if coalesce(char_length(trim(p_operator)), 0) < 2 then raise exception 'support: operator required'; end if;
  if coalesce(p_ticket, '') !~ '^[A-Za-z0-9_.:#-]{2,64}$' then raise exception 'support: ticket required'; end if;
  if coalesce(char_length(trim(p_reason)), 0) < 10 then raise exception 'support: reason (>= 10 chars) required'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Read: find a player by uid, username, friend code or email.
-- ---------------------------------------------------------------------------
create or replace function private.support_find_user(p_query text)
returns table (user_id uuid, username text, friend_code text, email text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select u.id, pr.username, pd.friend_code, u.email::text, u.created_at
  from auth.users u
  left join public.profiles pr on pr.id = u.id
  left join private.profile_data pd on pd.id = u.id
  where u.id::text = p_query
     or lower(pr.username) = lower(p_query)
     or upper(pd.friend_code) = upper(p_query)
     or lower(u.email) = lower(p_query)
  limit 20;
$$;

-- ---------------------------------------------------------------------------
-- Read: one player's economy, legacy review, purchases and recent ledger.
-- ---------------------------------------------------------------------------
create or replace function private.support_user_overview(p_user uuid, p_ledger_limit int default 50)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', p_user,
    'username', (select username from public.profiles where id = p_user),
    'profile_coins', (select pd.data->'coins' from private.profile_data pd where pd.id = p_user),
    'owned_items', (select pd.data->'owned_items' from private.profile_data pd where pd.id = p_user),
    'economy', (select to_jsonb(e) - 'coin_window_start' - 'coin_window_gain'
                from private.economy e where e.user_id = p_user),
    'legacy_review', (select to_jsonb(lr) from private.legacy_economy_reviews lr where lr.user_id = p_user),
    'purchases', coalesce((select jsonb_agg(jsonb_build_object(
          'transaction_id', pl.transaction_id, 'original_transaction_id', pl.original_transaction_id,
          'product_id', pl.product_id, 'environment', pl.environment,
          'purchased_at', pl.purchased_at, 'revoked_at', pl.revoked_at) order by pl.purchased_at desc)
        from private.purchase_ledger pl where pl.user_id = p_user), '[]'::jsonb),
    'grants_today', coalesce((select jsonb_object_agg(source, total) from (
          select source, sum(amount) as total from private.economy_grants
          where user_id = p_user and server_day = (now() at time zone 'utc')::date group by source) g), '{}'::jsonb),
    'recent_ledger', coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
          select jsonb_build_object('created_at', ev.created_at, 'kind', ev.kind, 'source', ev.source,
                                    'amount', ev.amount, 'event_key', ev.event_key, 'metadata', ev.metadata) as x
          from private.economy_events ev where ev.user_id = p_user
          order by ev.created_at desc limit greatest(1, least(coalesce(p_ledger_limit, 50), 500))) l), '[]'::jsonb),
    'support_actions', coalesce((select jsonb_agg(to_jsonb(sa) order by sa.at desc)
        from private.support_actions sa where sa.user_id = p_user), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- Read: investigate a missing / disputed purchase by any transaction id.
-- ---------------------------------------------------------------------------
create or replace function private.support_purchase_lookup(p_transaction_id text)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'ledger', coalesce((select jsonb_agg(to_jsonb(pl) order by pl.purchased_at)
        from private.purchase_ledger pl
        where pl.transaction_id = p_transaction_id or pl.original_transaction_id = p_transaction_id), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(n) order by n.signed_at)
        from private.app_store_notifications n where n.transaction_id = p_transaction_id), '[]'::jsonb),
    'credits', coalesce((select jsonb_agg(jsonb_build_object('user_id', ev.user_id, 'source', ev.source,
          'amount', ev.amount, 'created_at', ev.created_at, 'event_key', ev.event_key))
        from private.economy_events ev
        where ev.source in ('iap_coins', 'iap_revoke', 'iap_reinstate')
          and ev.metadata->>'transaction_id' = p_transaction_id), '[]'::jsonb),
    'hint', 'No ledger row = the app never reached verify-purchase: ask the player to Restore Purchases while signed in. '
            'Ledger row owned by another user = shared Apple ID / account switch: do not move it without evidence.'
  );
$$;

-- ---------------------------------------------------------------------------
-- Read: monitoring for refund and economy abuse (last p_days days).
-- ---------------------------------------------------------------------------
create or replace function private.support_refund_watch(p_days int default 30)
returns table (user_id uuid, refunds bigint, coin_refunds bigint, purchases bigint,
               confirmed_balance bigint, last_refund_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select pl.user_id,
         count(*) filter (where pl.revoked_at is not null),
         count(*) filter (where pl.revoked_at is not null and ip.kind = 'coins'),
         count(*),
         (select e.confirmed_balance from private.economy e where e.user_id = pl.user_id),
         max(pl.revoked_at)
  from private.purchase_ledger pl
  join private.iap_products ip on ip.product_id = pl.product_id
  where pl.user_id is not null
    and pl.purchased_at >= now() - make_interval(days => greatest(1, coalesce(p_days, 30)))
  group by pl.user_id
  having count(*) filter (where pl.revoked_at is not null) >= 1
  order by 2 desc, 6 desc;
$$;

create or replace function private.support_economy_watch(p_days int default 7, p_limit int default 50)
returns table (user_id uuid, earned bigint, capped bigint, cap_days bigint, grants bigint,
               confirmed_balance bigint, legacy_status text)
language sql stable security definer set search_path = '' as $$
  select g.user_id, sum(g.amount), sum(g.capped),
         count(distinct g.server_day) filter (where g.capped > 0),
         count(*), e.confirmed_balance, e.legacy_status
  from private.economy_grants g
  left join private.economy e on e.user_id = g.user_id
  where g.server_day >= (now() at time zone 'utc')::date - greatest(1, coalesce(p_days, 7))
  group by g.user_id, e.confirmed_balance, e.legacy_status
  order by 2 desc
  limit greatest(1, least(coalesce(p_limit, 50), 1000));
$$;

-- Legacy balances waiting for a human (status pending / review / rejected).
create or replace function private.support_legacy_queue(p_limit int default 100)
returns table (user_id uuid, status text, reason_code text, legacy_candidate bigint,
               verified_floor bigint, disputed_balance bigint, plausibility_score numeric,
               reviewed_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select e.user_id, e.legacy_status, lr.reason_code, lr.legacy_candidate,
         lr.verified_floor, lr.disputed_balance, lr.plausibility_score, lr.reviewed_at
  from private.economy e
  left join private.legacy_economy_reviews lr on lr.user_id = e.user_id
  where e.legacy_status in ('pending', 'review', 'rejected')
  order by lr.plausibility_score desc nulls last, e.user_id
  limit greatest(1, least(coalesce(p_limit, 100), 1000));
$$;

-- ---------------------------------------------------------------------------
-- Write: auditable balance adjustment (dispute resolution / goodwill).
-- Bounded (|delta| <= 50,000), cannot go below zero, requires an accepted
-- legacy status (resolve the legacy review first), idempotent per ticket.
-- ---------------------------------------------------------------------------
create or replace function private.support_adjust_balance(
  p_user uuid, p_delta bigint, p_operator text, p_ticket text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_key uuid; out jsonb; prior private.support_actions;
begin
  perform private.support_require(p_operator, p_ticket, p_reason);
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    raise exception 'support: unknown user';
  end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 50000 then
    raise exception 'support: delta must be non-zero and within +/-50000';
  end if;
  select * into prior from private.support_actions
  where action = 'adjust_balance' and ticket = p_ticket and user_id = p_user;
  if found then
    if (prior.details->>'delta')::bigint <> p_delta then
      raise exception 'support: ticket % already used for a different adjustment', p_ticket;
    end if;
    return jsonb_build_object('status', 'duplicate', 'support_action_id', prior.id);
  end if;

  v_key := private.deterministic_uuid('support_adjust:' || p_ticket || ':' || p_user::text);
  out := private.apply_economy_delta(p_user, v_key, 'support_adjustment', p_delta,
           (select config_version from private.economy where user_id = p_user),
           jsonb_build_object('ticket', p_ticket, 'operator', p_operator));
  insert into private.support_actions (operator, action, user_id, ticket, reason, event_key, details)
  values (p_operator, 'adjust_balance', p_user, p_ticket, p_reason, v_key,
          jsonb_build_object('delta', p_delta, 'result', out));
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- Write: resolve a legacy balance review (pending / review / rejected) by
-- setting the opening balance a human verified. The balance may not exceed
-- what the player had (max of legacy candidate and current confirmed balance),
-- so a typo can never mint coins. Owned items are never touched.
-- ---------------------------------------------------------------------------
create or replace function private.support_set_legacy_opening(
  p_user uuid, p_balance bigint, p_operator text, p_ticket text, p_reason text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e private.economy; lr private.legacy_economy_reviews; v_ceiling bigint; v_key uuid;
begin
  perform private.support_require(p_operator, p_ticket, p_reason);
  select * into e from private.economy where user_id = p_user for update;
  if not found then raise exception 'support: no economy row for user'; end if;
  if e.legacy_status = 'accepted' then
    raise exception 'support: legacy already accepted; use support_adjust_balance';
  end if;
  select * into lr from private.legacy_economy_reviews where user_id = p_user;
  v_ceiling := greatest(coalesce(lr.legacy_candidate, 0), coalesce(e.confirmed_balance, 0),
                        coalesce(e.legacy_opening_balance, 0));
  if p_balance is null or p_balance < 0 or p_balance > v_ceiling then
    raise exception 'support: balance must be between 0 and % (legacy ceiling)', v_ceiling;
  end if;

  v_key := private.deterministic_uuid('support_legacy:' || p_ticket || ':' || p_user::text);
  update private.economy
  set confirmed_balance = p_balance, legacy_status = 'accepted', updated_at = now()
  where user_id = p_user;
  update private.profile_data set data = jsonb_set(data, '{coins}', to_jsonb(p_balance)), updated_at = now()
  where id = p_user;
  insert into private.legacy_economy_reviews as r
    (user_id, confirmed_balance, disputed_balance, status, reason_code, reviewed_by, reviewed_at)
  values (p_user, p_balance, 0, 'accepted', 'support_resolved', p_operator, now())
  on conflict (user_id) do update
    set confirmed_balance = excluded.confirmed_balance, disputed_balance = 0, status = 'accepted',
        reason_code = 'support_resolved', reviewed_by = excluded.reviewed_by,
        reviewed_at = excluded.reviewed_at, updated_at = now();
  insert into private.economy_events (user_id, kind, detail, event_key, source, amount, metadata)
  values (p_user, 'legacy_reconciled',
          jsonb_build_object('from', e.confirmed_balance, 'to', p_balance, 'previous_status', e.legacy_status),
          v_key, 'legacy_opening', p_balance - coalesce(e.confirmed_balance, 0),
          jsonb_build_object('ticket', p_ticket, 'operator', p_operator));
  insert into private.support_actions (operator, action, user_id, ticket, reason, event_key, details)
  values (p_operator, 'set_legacy_opening', p_user, p_ticket, p_reason, v_key,
          jsonb_build_object('from', e.confirmed_balance, 'to', p_balance,
                             'previous_status', e.legacy_status, 'ceiling', v_ceiling));
  return jsonb_build_object('status', 'applied', 'balance', p_balance, 'legacy_status', 'accepted');
end $$;

-- Containment runs are SQL scripts (supabase/rollback/*); this records who
-- ran one and why, from the same transaction the script runs in.
create or replace function private.support_log_containment(
  p_kind text, p_operator text, p_ticket text, p_reason text)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.support_require(p_operator, p_ticket, p_reason);
  if p_kind not in ('economy_containment', 'purchase_containment') then
    raise exception 'support: unknown containment kind';
  end if;
  insert into private.support_actions (operator, action, user_id, ticket, reason)
  values (p_operator, p_kind, null, p_ticket, p_reason);
end $$;

do $grants$
declare f text;
begin
  foreach f in array array[
    'private.support_require(text, text, text)',
    'private.support_find_user(text)',
    'private.support_user_overview(uuid, int)',
    'private.support_purchase_lookup(text)',
    'private.support_refund_watch(int)',
    'private.support_economy_watch(int, int)',
    'private.support_legacy_queue(int)',
    'private.support_adjust_balance(uuid, bigint, text, text, text)',
    'private.support_set_legacy_opening(uuid, bigint, text, text, text)',
    'private.support_log_containment(text, text, text, text)',
    'private.support_actions_append_only()'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $grants$;
