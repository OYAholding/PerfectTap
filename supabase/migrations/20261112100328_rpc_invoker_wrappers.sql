-- ============================================================================
-- Move privileged RPC bodies out of the exposed `public` schema.
-- ============================================================================
-- Supabase's linter (authenticated_security_definer_function_executable) flags
-- SECURITY DEFINER functions reachable through /rest/v1/rpc. Recommended shape:
--   public.<rpc>   SECURITY INVOKER wrapper (same signature: the app is unchanged)
--   private.<rpc>  SECURITY DEFINER body with its auth.uid() checks (unexposed)
-- `authenticated` may EXECUTE the private body only through the wrapper's
-- privileges; the private schema itself is never served by PostgREST.
-- Service-role-only functions (claim_legacy_profile, edge_*, purge_*) are not
-- granted to `authenticated` and are left as they are.
-- ============================================================================

do $migration$
declare
  f record;
  in_args text;
  is_set boolean;
  result text;
  body text;
begin
  for f in
    select p.oid, p.proname,
           pg_get_function_arguments(p.oid)          as args,
           pg_get_function_identity_arguments(p.oid) as identity_args,
           pg_get_function_result(p.oid)             as result,
           p.proretset, p.prorettype, p.proargnames, p.proargmodes
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    order by p.proname
  loop
    -- Positional IN-argument names, for the call inside the wrapper.
    -- (proargnames is NULL for zero-argument functions; NULL modes = all IN.)
    in_args := '';
    if f.proargnames is not null then
      select coalesce(string_agg(quote_ident(a.name), ', ' order by a.ord), '')
        into in_args
        from unnest(f.proargnames) with ordinality as a(name, ord)
       where f.proargmodes is null or f.proargmodes[a.ord] in ('i', 'b');
    end if;

    -- Row-returning functions (TABLE / SETOF / composite) are selected FROM.
    is_set := f.proretset
              or exists (select 1 from pg_type t where t.oid = f.prorettype and t.typtype = 'c');
    body := case when is_set then format('select * from private.%I(%s)', f.proname, in_args)
                 else format('select private.%I(%s)', f.proname, in_args) end;

    execute format('alter function public.%I(%s) set schema private', f.proname, f.identity_args);
    execute format(
      'create function public.%I(%s) returns %s language sql volatile security invoker set search_path = %L as %L',
      f.proname, f.args, f.result, '', body);

    execute format('revoke all on function private.%I(%s) from public, anon', f.proname, f.identity_args);
    execute format('grant execute on function private.%I(%s) to authenticated', f.proname, f.identity_args);
    execute format('revoke all on function public.%I(%s) from public, anon', f.proname, f.identity_args);
    execute format('grant execute on function public.%I(%s) to authenticated', f.proname, f.identity_args);
  end loop;
end
$migration$;

-- Guard: nothing client-callable in `public` may still be SECURITY DEFINER.
do $check$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'public SECURITY DEFINER function still executable by authenticated';
  end if;
end
$check$;
