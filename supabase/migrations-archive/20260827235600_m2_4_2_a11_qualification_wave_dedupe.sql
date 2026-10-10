-- M2.4.2 A11 — prevent repeated qualification waves selecting the same active providers.
-- Deployed as m2_4_2_a11_qualification_wave_dedupe.

do $$
declare
  v_oid oid;
  v_def text;
  v_old text := '     order by course_count desc,p.canonical_name,p.id';
  v_new text := '       and not exists(
         select 1
         from pipeline.layer2_scale_qualification_items qi
         join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
         where qi.provider_id=p.id
           and qr.status in (''planned'',''running'')
       )
     order by course_count desc,p.canonical_name,p.id';
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='layer2_scale_scope_service'
    and pg_get_function_identity_arguments(p.oid)='p_actor uuid, p_action text, p_country_code text, p_scope_type text, p_scope_id uuid, p_wave_size integer, p_sample_size integer'
  limit 1;
  if v_oid is null then raise exception 'layer2_scale_scope_service not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position(v_old in v_def)=0 then raise exception 'qualification wave ordering anchor not found'; end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end $$;

revoke all on function public.layer2_scale_scope_service(uuid,text,text,text,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.layer2_scale_scope_service(uuid,text,text,text,uuid,integer,integer) to service_role;
