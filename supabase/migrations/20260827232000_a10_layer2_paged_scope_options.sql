-- A10 — keep Layer 2 Country initial load light; page State/University names at 10 per request.

begin;

create or replace function public.layer2_scope_options_page_service(
  p_actor uuid,
  p_country_code text,
  p_kind text,
  p_state_id uuid default null,
  p_query text default null,
  p_limit integer default 10,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref','security'
as $$
declare
  v_rank integer:=0;
  v_kind text:=lower(coalesce(nullif(trim(p_kind),''),''));
  v_country text:=upper(coalesce(nullif(trim(p_country_code),''),''));
  v_query text:=lower(nullif(trim(coalesce(p_query,'')),''));
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(role.rank),0) into v_rank
  from security.user_roles ur join security.roles role on role.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if v_country='' then raise exception 'country required' using errcode='22023'; end if;

  if v_kind='state' then
    with q as (
      select distinct sd.id::text value,sd.name label,sd.code meta
      from pipeline.layer2_source_profiles lp
      join pipeline.sources s on s.id=lp.source_id
      join ref.countries co on co.id=s.country_id
      join catalogue.courses c on c.provider_id=s.provider_id
      join catalogue.course_campuses cc on cc.course_id=c.id
      join catalogue.campuses cam on cam.id=cc.campus_id
      join ref.subdivisions sd on sd.id=cam.subdivision_id
      where lp.domain='course_facts' and lp.enabled and not lp.paused
        and upper(co.iso_alpha2::text)=v_country
        and (v_query is null or lower(sd.name||' '||sd.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
    into v_items,v_total;

  elsif v_kind='university' then
    with q as (
      select distinct cp.id::text value,cp.canonical_name label,lp.id::text meta
      from pipeline.layer2_source_profiles lp
      join pipeline.sources s on s.id=lp.source_id
      join ref.countries co on co.id=s.country_id
      join catalogue.providers cp on cp.id=s.provider_id
      where lp.domain='course_facts' and lp.enabled and not lp.paused
        and upper(co.iso_alpha2::text)=v_country
        and (p_state_id is null or exists(
          select 1
          from catalogue.courses c
          join catalogue.course_campuses cc on cc.course_id=c.id
          join catalogue.campuses cam on cam.id=cc.campus_id
          where c.provider_id=cp.id and cam.subdivision_id=p_state_id
        ))
        and (v_query is null or lower(cp.canonical_name||' '||lp.profile_key) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
    into v_items,v_total;
  else
    raise exception 'unsupported scope option kind' using errcode='22023';
  end if;

  return jsonb_build_object('items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,'has_more',(v_offset+jsonb_array_length(v_items))<v_total);
end $$;

create or replace function public.layer2_scope_countries_service(p_actor uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','pipeline','ref','security'
as $$
declare v_rank integer:=0;v_items jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(role.rank),0) into v_rank
 from security.user_roles ur join security.roles role on role.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name),'[]'::jsonb)
 into v_items
 from (
  select distinct c.iso_alpha2::text code,c.name
  from pipeline.layer2_source_profiles lp
  join pipeline.sources s on s.id=lp.source_id
  join ref.countries c on c.id=s.country_id
  where lp.domain='course_facts' and lp.enabled and not lp.paused
 ) x;
 return jsonb_build_object('countries',v_items);
end $$;

revoke all on function public.layer2_scope_options_page_service(uuid,text,text,uuid,text,integer,integer) from public,anon,authenticated;
revoke all on function public.layer2_scope_countries_service(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scope_options_page_service(uuid,text,text,uuid,text,integer,integer) to service_role;
grant execute on function public.layer2_scope_countries_service(uuid) to service_role;

-- Preview keeps complete scope resolution server-side but no longer returns the complete
-- profile/university list to the browser. The list is fetched separately through the paged service.
do $$
declare v_oid oid;v_def text;v_old text;
begin
 select p.oid into v_oid
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='layer2_operator_scope_service'
   and pg_get_function_identity_arguments(p.oid)='p_actor uuid, p_action text, p_country_code text, p_scope_type text, p_scope_id uuid'
 limit 1;
 if v_oid is null then raise exception 'layer2_operator_scope_service not found'; end if;
 select pg_get_functiondef(v_oid) into v_def;
 v_old:='''profiles'',coalesce(jsonb_agg(distinct jsonb_build_object(''profile_id'',sc.profile_id,''profile_key'',sc.profile_key,''provider_id'',sc.provider_id,''provider_name'',sc.provider_name)),''[]''::jsonb),';
 if position(v_old in v_def)>0 then
   v_def:=replace(v_def,v_old,'');
   execute v_def;
 end if;
end $$;

commit;
