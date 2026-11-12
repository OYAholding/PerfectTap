-- Duel score retries (PendingDuelStore on iOS) may arrive after the 2h session
-- TTL. Treat an expired session like "no session": static plausibility checks,
-- stored as unverified. Only forged/mismatched sessions still flag the score.
-- The public wrapper (20261112100328) is unchanged; only the private body moves.
create or replace function private.submit_duel_score(
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
    -- used/expired sessions (client retry after a network failure or >2h later)
    -- fall back to unverified static checks instead of zeroing the score.
    if v_reason is not null and v_reason not in ('session_used', 'session_expired') then
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

revoke all on function private.submit_duel_score(uuid, uuid, int, int, int, int) from public, anon;
grant execute on function private.submit_duel_score(uuid, uuid, int, int, int, int) to authenticated;
