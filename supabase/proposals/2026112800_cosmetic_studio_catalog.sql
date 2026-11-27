-- ============================================================================
-- PROPOSAL ONLY — NOT A MIGRATION. DO NOT MOVE INTO supabase/migrations/ AND
-- DO NOT DEPLOY FROM feature/cosmetic-d-shop.
-- ============================================================================
-- Cosmetic Studio server catalog + atomic bundle purchase.
--
-- Needs review by the economy (release/1.2.0) session and must be merged with
-- 20261127110000_economy_hardening.sql (present only in the release worktree)
-- before it can become a migration. See supabase/proposals/README.md.
--
-- What it does (all INACTIVE / disabled):
--   1. economy_shop_items: primary key (item_id) -> (config_version, item_id),
--      so a config version can carry its own full catalog. Required because the
--      current single-column key makes it impossible for a new config version
--      to also list the existing theme / Tap FX / avatar ids.
--   2. New config version `cosmetic-studio-rc1` (inactive, copy of
--      balanced-premium-rc1's config). Never touches the active row or
--      balanced-premium-rc1 itself.
--   3. Copies balanced-premium-rc1's shop rows into the new version (disabled),
--      then adds the 27 Cosmetic Studio items (disabled).
--   4. private.economy_bundles (RLS on, no client policies, no client grants)
--      + 3 bundles (disabled).
--   5. private.purchase_economy_bundle(p_user, p_event_key, p_bundle_id):
--      row lock, ONE ledger delta with the pro-rated price, set_profile_item per
--      missing item, `already_owned` when complete, rate limit; plus the
--      caller/invoker wrappers following the purchase_economy_item pattern.
--
-- Prices are UNAPPROVED candidates (docs/cosmetics/SHOP_CATALOG_PROPOSAL.md,
-- "authoritative candidate" column, ~3.5x the legacy proposal like the
-- existing balanced-premium-rc1 catalog).
-- ============================================================================

-- 1. Per-version catalog key -------------------------------------------------
alter table private.economy_shop_items drop constraint economy_shop_items_pkey;
alter table private.economy_shop_items add primary key (config_version, item_id);

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

-- 4. Bundles -----------------------------------------------------------------
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

-- 5. Atomic bundle purchase --------------------------------------------------
-- Price to complete = round(bundle.price × missing_list_value / total_list_value),
-- clamped to [1, missing_list_value]. Same rule as the client
-- (CosmeticBundlePricing, ios/PerfectTap/Models/ShopItem.swift).
create or replace function private.purchase_economy_bundle(p_user uuid, p_event_key uuid, p_bundle_id text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg private.economy_configs; b private.economy_bundles; pd private.profile_data;
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

  -- Serialise purchases of this player (same lock as purchase_economy_item).
  select * into pd from private.profile_data where id = p_user for update;
  if not found then perform private.fail('profile_required'); end if;
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
  -- A replayed / reused event key charged nothing now: grant nothing either.
  if out->>'status' = 'duplicate' then
    return out || jsonb_build_object('bundleID', p_bundle_id);
  end if;

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
