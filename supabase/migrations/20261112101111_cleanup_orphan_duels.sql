-- Duels whose BOTH players deleted their accounts keep no value for anyone.
-- (Deleting one player keeps the duel for the opponent's history: FKs set NULL.)
create or replace function private.cleanup()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.duel_invitations set status = 'expired', responded_at = now()
   where status = 'pending' and expires_at <= now();
  delete from public.duels where status = 'waiting' and created_at < now() - interval '24 hours';
  delete from public.duels where status = 'in_progress' and coalesce(joined_at, created_at) < now() - interval '7 days';
  delete from public.duels where status = 'completed' and completed_at < now() - interval '180 days';
  delete from public.duels where host_id is null and guest_id is null;
  delete from public.duel_invitations where created_at < now() - interval '30 days';
  delete from public.friend_requests where status <> 'pending' and created_at < now() - interval '30 days';
  delete from private.game_sessions where expires_at < now() - interval '1 day';
  delete from private.rate_limits where window_start < now() - interval '1 day';
end $$;
revoke all on function private.cleanup() from public, anon, authenticated;
