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
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),case when lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''))='level' then 100 else 10 end);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_sub_id uuid;
  v_empty text;
  v_pids uuid[];
  v_cids uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_subdivision is not null then select sd.id into v_sub_id from ref.subdivisions sd where sd.code=v_subdivision; end if;

  -- 22 Nov 2026 (REQ-105, s972): the filter lists read the providers of the country and the courses of the region once,
  -- then each list is a semi-join over its own small reference table. Same values, labels, order and totals as before.
  if v_country is not null and v_kind not in ('university_group','country') then
    select coalesce(array_agg(p.id),'{}'::uuid[]) into v_pids from catalogue.providers p join ref.countries co on co.id=p.country_id where co.iso_alpha2::text=v_country;
  end if;
  if v_subdivision is not null and v_kind in ('provider','level','field','delivery') then
    select coalesce(array_agg(distinct x.id),'{}'::uuid[]) into v_cids from (
      select cc.course_id id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
      where cp.subdivision_id in (select sd.id from ref.subdivisions sd where sd.code=v_subdivision)
      union all
      select c.id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
      where p.subdivision_id=v_sub_id and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                                                     where cc.course_id=c.id and cp.subdivision_id is not null)) x;
  end if;

  if v_kind='country' then
    with q as (
      select distinct co.iso_alpha2::text value,co.name label,co.iso_alpha2::text meta
      from ref.countries co
      where co.id in (select p.country_id from catalogue.providers p where exists(select 1 from catalogue.courses c where c.provider_id=p.id))
        and (v_query is null or lower(co.name||' '||co.iso_alpha2::text) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='subdivision' then
    with q as (
      select distinct s.code value,s.name label,s.code meta
      from ref.subdivisions s
      where (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
        and (exists(select 1 from catalogue.campuses cp join catalogue.course_campuses cc on cc.campus_id=cp.id join catalogue.courses c on c.id=cc.course_id
                    where cp.subdivision_id=s.id and (v_pids is null or c.provider_id=any(v_pids)))
          or exists(select 1 from catalogue.providers p
                    where p.subdivision_id=s.id and (v_pids is null or p.id=any(v_pids))
                      and exists(select 1 from catalogue.courses c where c.provider_id=p.id
                                   and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                                                  where cc.course_id=c.id and cp.subdivision_id is not null))))
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='provider' then
    with q as (
      select distinct p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta
      from catalogue.providers p
      where (v_pids is null or p.id=any(v_pids))
        and exists(select 1 from catalogue.courses c where c.provider_id=p.id and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='level' then
    with q as (
      select distinct sl.code value,sl.name label,coalesce(g.group_name,'Other') meta,sl.sort_order,coalesce(g.group_order,90) group_order
      from ref.study_levels sl
      left join ref.study_level_groups g on g.level_code=sl.code
      where exists(select 1 from catalogue.courses c where c.study_level_id=sl.id
                     and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(sl.name||' '||sl.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select value,label,meta,group_order,sort_order from q order by group_order,sort_order,lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'group',meta,'group_order',group_order) order by group_order,sort_order,lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='field' then
    with q as (
      select distinct fos.code value,fos.name label,fos.code meta
      from ref.fields_of_study fos
      where exists(select 1 from catalogue.courses c where c.primary_field_id=fos.id
                     and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(fos.name||' '||fos.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='delivery' then
    -- the few delivery modes are read from their indexes (one probe per mode), then kept when a course in scope has the mode
    with recursive t(m) as (
      (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'') is not null order by 1 limit 1)
      union all
      select (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'')>t.m order by 1 limit 1) from t where t.m is not null
    ), u(m) as (
      (select cc.delivery_mode from catalogue.course_campuses cc where cc.delivery_mode is not null order by 1 limit 1)
      union all
      select (select cc.delivery_mode from catalogue.course_campuses cc where cc.delivery_mode>u.m order by 1 limit 1) from u where u.m is not null
    ), q as (
      select m value,upper(left(replace(m,'_',' '),1))||substr(replace(m,'_',' '),2) label,null::text meta
      from (
        select t.m from t where t.m is not null
          and exists(select 1 from catalogue.courses c where nullif(btrim(c.delivery_mode),'')=t.m
                       and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        union
        select u.m from u where u.m is not null
          and exists(select 1 from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id
                     where cc.delivery_mode=u.m and nullif(btrim(c.delivery_mode),'') is null
                       and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
      ) x
      where m is not null and btrim(m)<>''
        and (v_query is null or lower(replace(m,'_',' ')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  elsif v_kind='university_group' then
    with q as (
      select replace(ic.code,'au_','') value,ic.name label,
             (select count(*)::int from security.university_group_provider_ids(ic.code) g) provider_count,
             (select count(*)::int from catalogue.courses c where c.provider_id in (select security.university_group_provider_ids(ic.code))) course_count
      from ref.institution_collections ic
      join ref.countries co on co.id=ic.country_id
      where ic.collection_type='university_group' and ic.status='active'
        and (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(ic.name||' '||replace(ic.code,'au_','')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,
                       'meta',provider_count||case when provider_count=1 then ' university' else ' universities' end,
                       'count',course_count,'course_count',course_count,'provider_count',provider_count) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  else
    raise exception 'unsupported catalogue filter kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  if v_total=0 and v_query is null then
    v_empty:=case v_kind
      when 'university_group' then 'No university groups are set up for this country.'
      when 'field' then 'Field of study is not classified for this country yet.'
      when 'subdivision' then 'No regions are recorded for this country.'
      when 'delivery' then 'No delivery mode is recorded for these courses.'
      else null end;
  end if;
  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',(v_offset+jsonb_array_length(v_items))<v_total
  )||case when v_empty is null then '{}'::jsonb else jsonb_build_object('empty_reason',v_empty) end;
end $function$
