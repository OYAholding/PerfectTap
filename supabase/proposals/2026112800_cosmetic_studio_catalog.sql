-- ============================================================================
-- PROPOSAL ONLY — NOT A MIGRATION. DO NOT MOVE INTO supabase/migrations/ AND
-- DO NOT DEPLOY FROM ANY COSMETIC BRANCH.
-- ============================================================================
-- Cosmetic Studio server catalog + atomic bundle purchase (target: 1.2.1).
--
-- Written and tested ON TOP OF the full release/1.2.0 migration set, including
-- 20261127110000_economy_hardening.sql and 20261127120000_support_operations.sql.
-- See supabase/proposals/README.md for the exact test run.
--
-- What it does (everything INACTIVE / disabled):
--   1. economy_shop_items: primary key (item_id) -> (config_version, item_id),
--      so a config version can carry its own full catalog and a cosmetic id can
--      be registered under several versions (F1). No hardening function relies
--      on the old key (all lookups filter by config_version; no ON CONFLICT on
--      this table anywhere in release/1.2.0).
--   2. New config version `cosmetic-studio-rc1` (inactive, copy of
--      balanced-premium-rc1's config + `cosmetic_studio: true`).
--   3. Copies balanced-premium-rc1's shop rows into the new version (disabled)
--      and adds the 27 Cosmetic Studio items (disabled).
--   4. F1 (review, high): the cosmetic ids are ALSO registered, disabled, under
--      every other config version (today: balanced-premium-rc1) and, by trigger,
--      under every config version created later. server_owned_items(cfg) reads
--      all rows of cfg regardless of `enabled`, so while ANY config is active
--      (or, during a containment, was the last approved one) a client profile
--      save can no longer add a cosmetic id to owned_items. A guard trigger keeps
--      cosmetic rows disabled in any config that is not a cosmetic config, so a
--      blanket "enable the shop" update cannot start selling them at candidate
--      prices. For ids a client may have added BEFORE this file was applied
--      while an authoritative config was already active,
--      private.strip_unpaid_cosmetic_items() (service role, dry run by default)
--      removes cosmetic ids that have no shop_purchase ledger entry.
--   5. private.economy_bundles (RLS on, no client policies, no client grants)
--      + 3 bundles (disabled).
--   6. private.purchase_economy_bundle(p_user, p_event_key, p_bundle_id),
--      mirroring the hardened purchase_economy_item:
--      F2: lock order economy -> profile_data (hardening rule L1);
--      F3: a replayed event key returns `duplicate` only for the SAME bundle,
--          any other reuse fails `invalid_payload`; the replay check runs before
--          the `already_owned` short-circuit; items are granted only when the
--          ledger delta reports `applied`.
--      Plus the caller/invoker wrappers following the purchase_economy_item pattern.
--
-- Prices are UNAPPROVED candidates (docs/cosmetics/SHOP_CATALOG_PROPOSAL.md,
-- "authoritative candidate" column, ~3.5x the legacy proposal like the
-- existing balanced-premium-rc1 catalog).
-- ============================================================================

-- 1. Per-version catalog key -------------------------------------------------
alter table private.economy_shop_items drop constraint economy_shop_items_pkey;
alter table private.economy_shop_items add primary key (config_version, item_id);

-- Cosmetic Studio item ids: "<collection>.<slot>" (CosmeticItem.makeID).
create or replace function private.is_cosmetic_item_id(p_item_id text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_item_id ~ '^[a-z0-9_]+\.(tapButton|tapSound|lifeIcon|tapEffect|perfectEffect|missEffect|lifeLostEffect|gameOverEffect|haptics)$', false)
$$;
revoke all on function private.is_cosmetic_item_id(text) from public, anon, authenticated;

-- 2. Inactive config version ---------------------------------------------------
insert into private.economy_configs (version, config, active)
select 'cosmetic-studio-rc1',
       c.config || jsonb_build_object('status', 'candidate_not_approved',
                                      'based_on', 'balanced-premium-rc1',
                                      'cosmetic_studio', true),
       false
from private.economy_configs c
where c.version = 'balanced-premium-rc1'
on conflict (version) do nothing;

-- 4a. Guard: cosmetic rows can be enabled only in a cosmetic config ------------
-- (created before the inserts below so it also covers them). Coerces instead of
-- raising so a blanket `update ... set enabled = true` (ops activation scripts,
-- existing pgTAP suites) keeps working and simply does not sell cosmetics.
create or replace function private.guard_cosmetic_shop_rows()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.enabled and private.is_cosmetic_item_id(new.item_id) and not coalesce((
       select (c.config->>'cosmetic_studio')::boolean from private.economy_configs c
       where c.version = new.config_version), false) then
    new.enabled := false;
  end if;
  return new;
end $$;
revoke all on function private.guard_cosmetic_shop_rows() from public, anon, authenticated;
create trigger economy_shop_items_cosmetic_guard
  before insert or update on private.economy_shop_items
  for each row execute function private.guard_cosmetic_shop_rows();

-- 3. Catalog rows (all disabled) ---------------------------------------------
insert into private.economy_shop_items (item_id, price, config_version, enabled)
select s.item_id, s.price, 'cosmetic-studio-rc1', false
from private.economy_shop_items s
where s.config_version = 'balanced-premium-rc1'
on conflict (config_version, item_id) do nothing;

insert into private.economy_shop_items (item_id, price, config_version, enabled)
select v.item_id, v.price, 'cosmetic-studio-rc1', false
from (values
  ('quack_attack.tapButton', 1000), ('quack_attack.tapSound', 850), ('quack_attack.lifeIcon', 700),
  ('quack_attack.tapEffect', 500),  ('quack_attack.perfectEffect', 700), ('quack_attack.missEffect', 400),
  ('quack_attack.lifeLostEffect', 500), ('quack_attack.gameOverEffect', 500), ('quack_attack.haptics', 350),
  ('purrfect_tap.tapButton', 1000), ('purrfect_tap.tapSound', 850), ('purrfect_tap.lifeIcon', 700),
  ('purrfect_tap.tapEffect', 500),  ('purrfect_tap.perfectEffect', 700), ('purrfect_tap.missEffect', 400),
  ('purrfect_tap.lifeLostEffect', 500), ('purrfect_tap.gameOverEffect', 500), ('purrfect_tap.haptics', 350),
  ('boom_mode.tapButton', 1000), ('boom_mode.tapSound', 850), ('boom_mode.lifeIcon', 700),
  ('boom_mode.tapEffect', 500),  ('boom_mode.perfectEffect', 700), ('boom_mode.missEffect', 400),
  ('boom_mode.lifeLostEffect', 500), ('boom_mode.gameOverEffect', 500), ('boom_mode.haptics', 350)
) as v(item_id, price)
on conflict (config_version, item_id) do nothing;

-- 4b. F1: register the cosmetic ids (disabled) under every other config ------
insert into private.economy_shop_items (item_id, price, config_version, enabled)
select s.item_id, s.price, c.version, false
from private.economy_shop_items s
cross join private.economy_configs c
where s.config_version = 'cosmetic-studio-rc1' and private.is_cosmetic_item_id(s.item_id)
  and c.version <> 'cosmetic-studio-rc1'
on conflict (config_version, item_id) do nothing;

-- ... and under every config version created later (disabled; the guard keeps
-- them disabled unless that config is a cosmetic config).
create or replace function private.register_cosmetic_ids_for_config()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into private.economy_shop_items (item_id, price, config_version, enabled)
  select distinct on (s.item_id) s.item_id, s.price, new.version, false
  from private.economy_shop_items s
  where private.is_cosmetic_item_id(s.item_id)
  order by s.item_id, s.created_at
  on conflict (config_version, item_id) do nothing;
  return new;
end $$;
revoke all on function private.register_cosmetic_ids_for_config() from public, anon, authenticated;
create trigger economy_configs_register_cosmetic_ids
  after insert on private.economy_configs
  for each row execute function private.register_cosmetic_ids_for_config();

-- 4c. F1: one-off cleanup for ids added while unprotected ---------------------
-- Removes cosmetic ids that no shop_purchase ledger entry paid for. Run it
-- (dry run first) when this proposal lands IF an authoritative config was active
-- before it was applied: in that window server_owned_items did not know the ids,
-- so a client save could add them for free. Do NOT run it for ids bought on the
-- legacy (pre-activation) economy, which are legitimate and have no ledger
-- entry; this is the same rule as themes bought before activation.
-- Lock order per player: economy -> profile_data (L1). Each removal is audited.
create or replace function private.strip_unpaid_cosmetic_items(p_dry_run boolean default true)
returns table (user_id uuid, item_id text, applied boolean)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare rec record; x text;
begin
  for rec in
    select pd.id as uid from private.profile_data pd
    where jsonb_typeof(pd.data->'owned_items') = 'array'
      and exists (select 1 from jsonb_array_elements_text(pd.data->'owned_items') t(v)
                  where private.is_cosmetic_item_id(t.v))
    order by pd.id
  loop
    if not p_dry_run then
      insert into private.economy (user_id) values (rec.uid) on conflict (user_id) do nothing;
      perform 1 from private.economy e where e.user_id = rec.uid for update;
      perform 1 from private.profile_data pd where pd.id = rec.uid for update;
    end if;
    for x in
      select t.v from private.profile_data pd, jsonb_array_elements_text(pd.data->'owned_items') t(v)
      where pd.id = rec.uid and private.is_cosmetic_item_id(t.v)
        and not exists (
          select 1 from private.economy_events ev
          where ev.user_id = rec.uid and ev.source = 'shop_purchase'
            and (ev.metadata->>'item_id' = t.v
                 or (jsonb_typeof(ev.metadata->'item_ids') = 'array' and ev.metadata->'item_ids' ? t.v)))
    loop
      if not p_dry_run then
        perform private.set_profile_item(rec.uid, x, false);
        insert into private.economy_events (user_id, kind, detail)
        values (rec.uid, 'cosmetic_unpaid_stripped', jsonb_build_object('item_id', x));
      end if;
      user_id := rec.uid; item_id := x; applied := not p_dry_run;
      return next;
    end loop;
  end loop;
end $$;
revoke all on function private.strip_unpaid_cosmetic_items(boolean) from public, anon, authenticated;
grant execute on function private.strip_unpaid_cosmetic_items(boolean) to service_role;

-- 5. Bundles -----------------------------------------------------------------
create table private.economy_bundles (
  bundle_id      text not null check (bundle_id ~ '^bundle\.[a-z0-9_]+$'),
  config_version text not null references private.economy_configs(version),
  item_ids       text[] not null check (cardinality(item_ids) between 1 and 32),
  price          int not null check (price > 0),
  enabled        boolean not null default false,
  created_at     timestamptz not null default now(),
  primary key (config_version, bundle_id)
);
alter table private.economy_bundles enable row level security;
-- No policies: clients never read or write this table directly.

insert into private.economy_bundles (bundle_id, config_version, item_ids, price, enabled)
select 'bundle.' || c, 'cosmetic-studio-rc1',
       array(select c || '.' || s from unnest(array['tapButton','tapSound','lifeIcon','tapEffect',
             'perfectEffect','missEffect','lifeLostEffect','gameOverEffect','haptics']) s),
       3750, false
from unnest(array['quack_attack','purrfect_tap','boom_mode']) c
on conflict (config_version, bundle_id) do nothing;

-- 6. Atomic bundle purchase --------------------------------------------------
-- Price to complete = round(bundle.price × missing_list_value / total_list_value),
-- clamped to [1, missing_list_value]. Same rule as the client
-- (CosmeticBundlePricing, ios/PerfectTap/Models/ShopItem.swift).
create or replace function private.purchase_economy_bundle(p_user uuid, p_event_key uuid, p_bundle_id text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; b private.economy_bundles; pd private.profile_data;
        e private.economy; prior private.economy_events;
        owned jsonb; n_items int; total bigint; missing text[]; missing_value bigint;
        charge bigint; out jsonb; item text;
begin
  cfg := private.require_active_economy();
  perform private.check_rate(p_user, 'economy_shop_purchase', 30, interval '1 minute');
  if p_event_key is null or coalesce(p_bundle_id, '') = '' then perform private.fail('invalid_payload'); end if;

  select * into b from private.economy_bundles
  where bundle_id = p_bundle_id and enabled and config_version = cfg.version;
  if not found then perform private.fail('item_unavailable'); end if;

  -- Every component must be an enabled shop item of the same config: the
  -- list values come from there, and server_owned_items() then protects them.
  select count(distinct s.item_id), coalesce(sum(s.price), 0) into n_items, total
  from private.economy_shop_items s
  where s.config_version = cfg.version and s.enabled and s.item_id = any(b.item_ids);
  if n_items <> cardinality(b.item_ids) or total <= 0 then perform private.fail('item_unavailable'); end if;

  -- F2 / L1: lock order economy -> profile_data, same as purchase_economy_item.
  insert into private.economy (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into e from private.economy where user_id = p_user for update;
  select * into pd from private.profile_data where id = p_user for update;
  if not found then perform private.fail('profile_required'); end if;

  -- F3 / C1: a replay of the SAME bundle purchase is a duplicate; any other reuse
  -- of the key (another bundle, a single item, a reward) is refused. Checked
  -- before `already_owned`, so a reused key never answers with ownership state.
  select * into prior from private.economy_events where user_id = p_user and event_key = p_event_key;
  if found then
    if prior.source = 'shop_purchase' and prior.metadata->>'bundle_id' = p_bundle_id then
      return jsonb_build_object('status', 'duplicate', 'balance', e.confirmed_balance,
                                'coinDebt', e.coin_debt, 'bundleID', p_bundle_id);
    end if;
    perform private.fail('invalid_payload');
  end if;

  owned := coalesce(pd.data->'owned_items', '[]'::jsonb);
  select array_agg(u.x order by u.ord), coalesce(sum(s.price), 0) into missing, missing_value
  from unnest(b.item_ids) with ordinality as u(x, ord)
  join private.economy_shop_items s on s.item_id = u.x and s.config_version = cfg.version
  where not (owned ? u.x);

  if missing is null or cardinality(missing) = 0 then
    return jsonb_build_object('status', 'already_owned', 'bundleID', p_bundle_id);
  end if;

  charge := least(missing_value,
                  greatest(1, (2 * b.price::bigint * missing_value + total) / (2 * total)));

  out := private.apply_economy_delta(p_user, p_event_key, 'shop_purchase', -charge, cfg.version,
    jsonb_build_object('bundle_id', p_bundle_id, 'item_ids', to_jsonb(missing),
                       'missing_list_value', missing_value));
  -- F3: grant only what was actually paid for.
  if out->>'status' is distinct from 'applied' then perform private.fail('invalid_payload'); end if;

  foreach item in array missing loop
    perform private.set_profile_item(p_user, item, true);
  end loop;
  return out || jsonb_build_object('bundleID', p_bundle_id, 'itemIDs', to_jsonb(missing), 'charged', charge);
end $$;
revoke all on function private.purchase_economy_bundle(uuid, uuid, text) from public, anon, authenticated;

create or replace function private.purchase_economy_bundle_for_caller(p_event_key uuid, p_bundle_id text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_uid();
begin
  return private.purchase_economy_bundle(uid, p_event_key, p_bundle_id);
end $$;
revoke all on function private.purchase_economy_bundle_for_caller(uuid, text) from public, anon;

create or replace function public.purchase_economy_bundle(p_event_key uuid, p_bundle_id text)
returns jsonb
language sql volatile security invoker set search_path = '' as $$
  select private.purchase_economy_bundle_for_caller(p_event_key, p_bundle_id)
$$;
revoke all on function public.purchase_economy_bundle(uuid, text) from public, anon;
grant execute on function private.purchase_economy_bundle_for_caller(uuid, text),
  public.purchase_economy_bundle(uuid, text) to authenticated;

-- Explicit grants only. Private tables have RLS and no client table grants.
revoke all on table private.economy_bundles from public, anon, authenticated;
