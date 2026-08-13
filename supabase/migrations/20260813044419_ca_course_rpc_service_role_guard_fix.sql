do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='svc_layer1_apply_scoped_course_records';
  if v_def is null then raise exception 'svc_layer1_apply_scoped_course_records missing'; end if;
  v_def:=replace(v_def,
$guard$  if lower(coalesce(current_setting('request.jwt.claim.role', true),'')) <> 'service_role' and session_user <> 'postgres' then
    raise exception 'service_role required';
  end if;
$guard$,'');
  execute v_def;
end $$;
revoke all on function public.svc_layer1_apply_scoped_course_records(text,uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_layer1_apply_scoped_course_records(text,uuid,uuid,uuid,text,text,jsonb) to service_role;