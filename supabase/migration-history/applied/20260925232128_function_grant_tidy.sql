do $tidy$
declare r record; v_service_before int; v_service_after int;
begin
  select count(*) into v_service_before from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('public','api','security','pipeline') and has_function_privilege('service_role', p.oid, 'EXECUTE');

  for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE')
             and n.nspname in ('api','security','pipeline','catalogue','search','scholarship','ranking','pim','workflow','publishing','private','integration','ref') loop
    if has_function_privilege('authenticated', r.fn, 'EXECUTE') then execute format('grant execute on function %s to authenticated', r.fn); end if;
    execute format('grant execute on function %s to service_role', r.fn);
    execute format('revoke execute on function %s from public, anon', r.fn);
  end loop;

  for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='api' and p.proname in ('website_integration_auth_v1','website_integration_rate_check_v1','courses_list','providers_list','zoho_course_candidates_v1') loop
    execute format('grant execute on function %s to service_role', r.fn);
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
  end loop;

  select count(*) into v_service_after from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('public','api','security','pipeline') and has_function_privilege('service_role', p.oid, 'EXECUTE');
  if v_service_after < v_service_before then raise exception 'service_role lost execute on % function(s); aborting', v_service_before - v_service_after; end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE')
             and n.nspname in ('api','security','pipeline','catalogue','search','scholarship','ranking','pim','workflow','publishing','private','integration','ref')) then
    raise exception 'anon still has execute on a security-definer function; aborting';
  end if;
end $tidy$;
