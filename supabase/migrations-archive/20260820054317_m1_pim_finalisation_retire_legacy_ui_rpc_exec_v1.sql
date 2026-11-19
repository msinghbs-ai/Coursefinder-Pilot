-- M1-PIM-FINALISATION: retire legacy browser-executable public.ui_* compatibility RPCs.
-- PIM Admin v2.10 calls only public.admin_read, whose routed helpers perform explicit role/rank checks.
-- Preserve postgres owner and service_role execution for internal compatibility.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname like 'ui\_%' escape '\'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.signature);
    execute format('grant execute on function %s to service_role', r.signature);
  end loop;
end $$;
