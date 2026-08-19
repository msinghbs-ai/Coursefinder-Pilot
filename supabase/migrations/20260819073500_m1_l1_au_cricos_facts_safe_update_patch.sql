-- PostgREST/Edge service-role calls enforce an explicit WHERE predicate on UPDATE.
-- The temporary table contains only the bounded payload, so WHERE true is intentionally exhaustive.

do $patch$
declare
  v_def text;
  v_before text := '  )::text,''sha256''),''hex'');';
  v_after text := '  )::text,''sha256''),''hex'')' || E'\n  where true;';
begin
  select pg_get_functiondef(p.oid)
    into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='svc_layer1_apply_course_regulatory_facts'
  limit 1;

  if v_def is null then
    raise exception 'svc_layer1_apply_course_regulatory_facts missing';
  end if;
  if position(v_before in v_def)=0 then
    raise exception 'expected hash update statement not found';
  end if;

  execute replace(v_def,v_before,v_after);
end
$patch$;

revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from public;
revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from anon;
revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from authenticated;
grant execute on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) to service_role;
