-- Emergency containment for 20261122120000. This intentionally preserves all
-- purchase/audit rows. Run only against the confirmed PerfectTap project.
begin;

update private.iap_products set enabled = false;
revoke execute on function public.record_verified_purchase(uuid, text, text, text, text, timestamptz, timestamptz)
  from service_role;
revoke execute on function public.revoke_purchase(text, timestamptz, text, text, text, uuid)
  from service_role;
revoke execute on function public.process_app_store_notification(text, text, text, timestamptz, text, text, text, text, uuid, timestamptz)
  from service_role;

insert into private.economy_events (user_id, kind, detail)
values (null, 'purchase_backend_contained', jsonb_build_object('at', now()));

commit;

-- Do not drop the ledger/economy tables during an incident. Restore the prior
-- save_profile definition from the pre-deploy schema backup if that function,
-- rather than purchase ingestion, is the source of the incident.
