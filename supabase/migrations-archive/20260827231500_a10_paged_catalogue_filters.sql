-- A10 — server-paged catalogue filter options, hard capped to 10 per request.
begin;

CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_kind text:=lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''));
  v_query text:=lower(nullif(trim(coalesce(p_args->>'query','')),''));
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text:=upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),10);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if v_kind='country' then
    with q as (
      select distinct co.iso_alpha2::text value,co.name label,co.iso_alpha2::text meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where v_query is null or lower(co.name||' '||co.iso_alpha2::text) like '%'||v_query||'%'
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='subdivision' then
    with q as (
      select distinct s.code value,s.name label,s.code meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      join catalogue.course_campuses cc on cc.course_id=c.id
      join catalogue.campuses cp on cp.id=cc.campus_id
      join ref.subdivisions s on s.id=cp.subdivision_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='provider' then
    with q as (
      select distinct p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where cc.course_id=c.id and s.code=v_subdivision
        ))
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='level' then
    with q as (
      select distinct sl.code value,sl.name label,sl.code meta,sl.sort_order
      from catalogue.courses c
      join ref.study_levels sl on sl.id=c.study_level_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where cc.course_id=c.id and s.code=v_subdivision
        ))
        and (v_query is null or lower(sl.name||' '||sl.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select value,label,meta from q order by sort_order,lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta)) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='field' then
    with q as (
      select distinct fos.code value,fos.name label,fos.code meta
      from catalogue.courses c
      join ref.fields_of_study fos on fos.id=c.primary_field_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where cc.course_id=c.id and s.code=v_subdivision
        ))
        and (v_query is null or lower(fos.name||' '||fos.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='delivery' then
    with q as (
      select distinct cc.delivery_mode value,cc.delivery_mode label,cc.delivery_mode meta
      from catalogue.course_campuses cc
      join catalogue.courses c on c.id=cc.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
        and (v_country is null or co.iso_alpha2::text=v_country)
        and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc2
          join catalogue.campuses cp2 on cp2.id=cc2.campus_id
          join ref.subdivisions s2 on s2.id=cp2.subdivision_id
          where cc2.course_id=c.id and s2.code=v_subdivision
        ))
        and (v_query is null or lower(cc.delivery_mode) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  else
    raise exception 'unsupported catalogue filter kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',(v_offset+jsonb_array_length(v_items))<v_total
  );
end $function$
;

revoke all on function security.admin_catalogue_filter_page(jsonb) from public,anon;
grant execute on function security.admin_catalogue_filter_page(jsonb) to authenticated,service_role;

do $$
declare v_oid oid;v_def text;
begin
 select p.oid into v_oid
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='admin_read'
   and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
 limit 1;
 if v_oid is null then raise exception 'public.admin_read(text,jsonb) not found'; end if;
 select pg_get_functiondef(v_oid) into v_def;
 if position('catalogue_filter_page' in v_def)=0 then
   if position('if p_operation in (''provider_filters'',''course_filters'') then' in v_def)=0 then
     raise exception 'admin_read catalogue filter marker not found';
   end if;
   v_def:=replace(
     v_def,
     'if p_operation in (''provider_filters'',''course_filters'') then',
     'if p_operation=''catalogue_filter_page'' then return security.admin_catalogue_filter_page(p_args); end if;'||chr(10)||
     ' if p_operation in (''provider_filters'',''course_filters'') then'
   );
   execute v_def;
 end if;
end $$;

commit;
