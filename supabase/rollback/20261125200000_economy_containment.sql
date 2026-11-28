-- Emergency containment for the authoritative economy
-- (20261125130443 + 20261125200000). Preserves every ledger, claim, review
-- and balance row. Run only against the confirmed PerfectTap project, together
-- with 20261122120000_purchase_containment.sql when purchases must stop too.
--
-- Effect: no active economy config ⇒ every client economy RPC fails with
-- `economy_disabled` and save_profile falls back to the pre-authoritative
-- guard; coin-shop rows are disabled; rewarded-ad SSV grants stop.
begin;

update private.economy_configs set active = false where active;
update private.economy_shop_items set enabled = false where enabled;

revoke execute on function public.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint)
  from service_role;
revoke execute on function public.submit_economy_event(uuid, text, jsonb)
  from authenticated;
-- The private bodies carry their own grants; revoke them too (defense in depth).
revoke execute on function private.record_verified_rewarded_claim(uuid, uuid, text, text, uuid, smallint)
  from service_role;
revoke execute on function private.submit_economy_event(uuid, text, jsonb)
  from authenticated;

insert into private.economy_events (user_id, kind, detail)
values (null, 'economy_backend_contained', jsonb_build_object('at', now()));

commit;

-- Recovery: re-grant the two functions above, re-enable approved shop rows and
-- re-activate the approved config (requires approved_by/approved_at) only after
-- the incident is understood. Never delete ledger rows or edit balances here;
-- corrections are new ledger events.
