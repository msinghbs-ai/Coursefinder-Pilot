drop function if exists public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text);

create or replace function public.ui_course_filter_options(p_country_code text default null,p_subdivision_code text default null)
returns jsonb
language sql stable security definer
set search_path='public','catalogue','ref','auth'
as $$
select case when auth.uid() is null then null else jsonb_build_object(
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name) from (
   select distinct co.iso_alpha2::text code,co.name from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
 )x),'[]'::jsonb),
 'subdivisions',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name) from (
   select distinct s.code,s.name,s.subdivision_type
   from catalogue.courses c
   join catalogue.providers p on p.id=c.provider_id
   join ref.countries co on co.id=p.country_id
   join catalogue.course_campuses cc on cc.course_id=c.id
   join catalogue.campuses cp on cp.id=cc.campus_id
   join ref.subdivisions s on s.id=cp.subdivision_id
   where nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))
 )x),'[]'::jsonb),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'stable_key',x.stable_key) order by x.name) from (
   select distinct p.id,coalesce(p.display_name,p.canonical_name) name,p.stable_key
   from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
     and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(
       select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions s on s.id=cp.subdivision_id
       where cc.course_id=c.id and s.code=upper(trim(p_subdivision_code))))
 )x),'[]'::jsonb),
 'levels',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.sort_order,x.name) from (
   select distinct sl.code,sl.name,sl.sort_order
   from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
     and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions s on s.id=cp.subdivision_id where cc.course_id=c.id and s.code=upper(trim(p_subdivision_code))))
 )x),'[]'::jsonb),
 'fields',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name) from (
   select distinct fos.code,fos.name
   from catalogue.courses c join ref.fields_of_study fos on fos.id=c.primary_field_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
     and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions s on s.id=cp.subdivision_id where cc.course_id=c.id and s.code=upper(trim(p_subdivision_code))))
 )x),'[]'::jsonb),
 'delivery_modes',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.code) order by x.code) from (
   select distinct cc.delivery_mode code
   from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
     and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
     and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from catalogue.course_campuses cc2 join catalogue.campuses cp2 on cp2.id=cc2.campus_id join ref.subdivisions s2 on s2.id=cp2.subdivision_id where cc2.course_id=c.id and s2.code=upper(trim(p_subdivision_code))))
 )x),'[]'::jsonb)
) end $$;

create or replace function public.ui_courses_decision_page(
 p_limit integer default 50,p_offset integer default 0,p_query text default null,p_country_code text default null,p_subdivision_code text default null,p_provider_id uuid default null,p_level_code text default null,p_field_code text default null,p_delivery_mode text default null,p_lifecycle_status text default null,p_publication_status text default null,p_has_fee boolean default null,p_has_intake boolean default null,p_has_english boolean default null,p_has_scholarship boolean default null,p_min_completeness numeric default null,p_freshness text default null,p_sort text default 'course',p_direction text default 'asc',p_has_state boolean default null,p_has_link boolean default null)
returns jsonb
language plpgsql stable security definer
set search_path='public','catalogue','ref','search','scholarship','auth'
as $$
declare v_limit int:=least(greatest(coalesce(p_limit,50),1),200);v_offset int:=greatest(coalesce(p_offset,0),0);v_sort text:=lower(coalesce(p_sort,'course'));v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
 if auth.uid() is null then raise exception 'authentication required';end if;
 return (
 with base as (
   select c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
     coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
     sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study,
     case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' else c.delivery_mode end delivery_mode,
     coalesce(d.completeness_score,0) completeness_score,
     exists(select 1 from catalogue.course_fees f where f.course_id=c.id and coalesce(f.status,'active')='active') has_fee,
     exists(select 1 from catalogue.course_intakes i where i.course_id=c.id) has_intake,
     exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id) has_english,
     exists(select 1 from scholarship.scopes ss where ss.course_id=c.id and coalesce(ss.include_exclude,'include')='include') has_scholarship,
     exists(select 1 from catalogue.course_links l where l.course_id=c.id and l.status='active') has_link,
     coalesce(geo.region_count,0)>0 has_state,
     coalesce(geo.campus_count,0) campus_count,
     case when geo.region_count=1 then geo.single_code else null end subdivision_code,
     case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else null end subdivision_name,
     coalesce(geo.region_count,0) region_count
   from catalogue.courses c
   join catalogue.providers p on p.id=c.provider_id
   join ref.countries co on co.id=p.country_id
   left join ref.study_levels sl on sl.id=c.study_level_id
   left join ref.fields_of_study fos on fos.id=c.primary_field_id
   left join search.course_documents d on d.course_id=c.id
   left join lateral (
     select count(distinct cc.campus_id)::int campus_count,count(distinct s.id)::int region_count,min(s.code) single_code,min(s.name) single_name
     from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id left join ref.subdivisions s on s.id=ca.subdivision_id
     where cc.course_id=c.id
   ) geo on true
   left join lateral (
     select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
     from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
   ) dm on true
   where (nullif(trim(coalesce(p_query,'')),'') is null or c.canonical_title ilike '%'||trim(p_query)||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%' or coalesce(c.course_code,'') ilike '%'||trim(p_query)||'%' or coalesce(c.stable_key,'') ilike '%'||trim(p_query)||'%')
     and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
     and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id join ref.subdivisions s on s.id=ca.subdivision_id where cc.course_id=c.id and s.code=upper(trim(p_subdivision_code))))
     and (p_provider_id is null or c.provider_id=p_provider_id)
     and (nullif(trim(coalesce(p_level_code,'')),'') is null or sl.code=trim(p_level_code))
     and (nullif(trim(coalesce(p_field_code,'')),'') is null or fos.code=trim(p_field_code))
     and (nullif(trim(coalesce(p_delivery_mode,'')),'') is null or coalesce(c.delivery_mode,'')=trim(p_delivery_mode) or exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode=trim(p_delivery_mode)))
     and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or c.lifecycle_status=trim(p_lifecycle_status))
     and (nullif(trim(coalesce(p_publication_status,'')),'') is null or c.publication_status=trim(p_publication_status))
 ),filtered as(
   select * from base where (p_has_fee is null or has_fee=p_has_fee) and (p_has_intake is null or has_intake=p_has_intake) and (p_has_english is null or has_english=p_has_english) and (p_has_scholarship is null or has_scholarship=p_has_scholarship) and (p_has_state is null or has_state=p_has_state) and (p_has_link is null or has_link=p_has_link) and (p_min_completeness is null or completeness_score>=p_min_completeness) and (nullif(trim(coalesce(p_freshness,'')),'') is null or (p_freshness='never_verified' and last_verified_at is null) or (p_freshness='modified_7d' and updated_at>=now()-interval '7 days') or (p_freshness='modified_30d' and updated_at>=now()-interval '30 days') or (p_freshness='stale_180d' and (last_verified_at is null or last_verified_at<now()-interval '180 days')))
 ),numbered as(select *,count(*) over() total_count from filtered),ordered as(
   select * from numbered order by
    case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
    case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
    case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
    case when v_sort='completeness' and v_dir='asc' then completeness_score end asc,case when v_sort='completeness' and v_dir='desc' then completeness_score end desc,
    case when v_sort='modified' and v_dir='asc' then updated_at end asc,case when v_sort='modified' and v_dir='desc' then updated_at end desc,
    case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
    lower(canonical_title),id limit v_limit offset v_offset)
 select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o);
end $$;

create or replace function public.ui_providers_page(p_limit integer default 50,p_offset integer default 0,p_query text default null,p_country_code text default null,p_subdivision_code text default null,p_lifecycle_status text default null,p_publication_status text default null,p_sort text default 'provider',p_direction text default 'asc')
returns jsonb language plpgsql stable security definer set search_path='public','catalogue','ref','pipeline','auth' as $$
declare v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);v_offset integer:=greatest(coalesce(p_offset,0),0);v_sort text:=lower(coalesce(p_sort,'provider'));v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
 if auth.uid() is null then raise exception 'authentication required';end if;
 return(with base as(
  select p.id,p.stable_key,p.canonical_name,p.display_name,c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
    ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,p.primary_city city,p.website,p.lifecycle_status,p.publication_status,p.last_verified_at,p.created_at,p.updated_at,
    geo.region_count campus_region_count,geo.regions campus_regions,
    (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
    (select count(distinct x.evidence_id)::bigint from (select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id union all select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null union all select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null)x) evidence_count
  from catalogue.providers p join ref.countries c on c.id=p.country_id left join ref.subdivisions ps on ps.id=p.subdivision_id
  left join lateral(select count(distinct s.id)::int region_count,string_agg(distinct s.code,', ' order by s.code) regions from catalogue.campuses cp join ref.subdivisions s on s.id=cp.subdivision_id where cp.provider_id=p.id)geo on true
  where (nullif(trim(coalesce(p_query,'')),'') is null or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%' or coalesce(p.stable_key,'') ilike '%'||trim(p_query)||'%' or coalesce(p.primary_city,'') ilike '%'||trim(p_query)||'%' or coalesce(c.iso_alpha2::text,'') ilike '%'||trim(p_query)||'%' or coalesce(c.name,'') ilike '%'||trim(p_query)||'%' or coalesce(c.default_currency_code::text,'') ilike '%'||trim(p_query)||'%' or coalesce(ps.code,'') ilike '%'||trim(p_query)||'%' or coalesce(ps.name,'') ilike '%'||trim(p_query)||'%' or coalesce(geo.regions,'') ilike '%'||trim(p_query)||'%')
    and (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text=upper(trim(p_country_code)))
    and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)) or exists(select 1 from catalogue.campuses cp join ref.subdivisions s on s.id=cp.subdivision_id where cp.provider_id=p.id and s.code=upper(trim(p_subdivision_code))))
    and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or p.lifecycle_status=trim(p_lifecycle_status))
    and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
 ),numbered as(select *,count(*) over()::bigint total_count from base),ordered as(select * from numbered order by case when v_sort='provider' and v_dir='asc' then lower(coalesce(display_name,canonical_name)) end asc,case when v_sort='provider' and v_dir='desc' then lower(coalesce(display_name,canonical_name)) end desc,case when v_sort='country' and v_dir='asc' then country_code end asc,case when v_sort='country' and v_dir='desc' then country_code end desc,case when v_sort='currency' and v_dir='asc' then currency_code end asc,case when v_sort='currency' and v_dir='desc' then currency_code end desc,case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(subdivision_name,'')) end asc,case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(subdivision_name,'')) end desc,case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,case when v_sort='courses' and v_dir='asc' then course_count end asc,case when v_sort='courses' and v_dir='desc' then course_count end desc,case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,lower(coalesce(display_name,canonical_name)),id limit v_limit offset v_offset)
 select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o);
end $$;
