create or replace function public.ui_course_filter_options(p_country_code text default null, p_subdivision_code text default null)
returns jsonb
language sql
stable
security definer
set search_path=public,catalogue,ref,auth
as $$
select case when auth.uid() is null then null else jsonb_build_object(
  'countries', coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name) from (
    select distinct co.iso_alpha2::text code, co.name
    from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
  ) x),'[]'::jsonb),
  'subdivisions', coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name) from (
    select distinct s.code,s.name,s.subdivision_type
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    join ref.subdivisions s on s.id=p.subdivision_id
    where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
    union
    select distinct s.code,s.name,s.subdivision_type
    from catalogue.courses c
    join catalogue.course_campuses cc on cc.course_id=c.id
    join catalogue.campuses cp on cp.id=cc.campus_id
    join ref.countries co on co.id=cp.country_id
    join ref.subdivisions s on s.id=cp.subdivision_id
    where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
  ) x),'[]'::jsonb),
  'providers', coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'stable_key',x.stable_key) order by x.name) from (
    select distinct p.id,coalesce(p.display_name,p.canonical_name) name,p.stable_key
    from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
    left join ref.subdivisions ps on ps.id=p.subdivision_id
    where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
      and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)) or exists(
        select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id
        where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code))
      ))
  ) x),'[]'::jsonb),
  'levels', coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.sort_order,x.name) from (
    select distinct sl.code,sl.name,sl.sort_order from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
    left join ref.subdivisions ps on ps.id=p.subdivision_id
    where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
      and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)) or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code))))
  ) x),'[]'::jsonb),
  'fields', coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name) from (
    select distinct fos.code,fos.name from catalogue.courses c join ref.fields_of_study fos on fos.id=c.primary_field_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
    left join ref.subdivisions ps on ps.id=p.subdivision_id
    where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
      and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)) or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code))))
  ) x),'[]'::jsonb),
  'delivery_modes', coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.code) order by x.code) from (
    select distinct c.delivery_mode code from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id left join ref.subdivisions ps on ps.id=p.subdivision_id
    where c.delivery_mode is not null and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
      and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)) or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code))))
  ) x),'[]'::jsonb)
) end;
$$;
revoke all on function public.ui_course_filter_options(text,text) from public,anon;
grant execute on function public.ui_course_filter_options(text,text) to authenticated;

create or replace function public.ui_courses_page(
  p_limit integer default 50,p_offset integer default 0,p_query text default null,p_country_code text default null,p_subdivision_code text default null,p_provider_id uuid default null,p_level_code text default null,p_field_code text default null,p_delivery_mode text default null,p_lifecycle_status text default null,p_publication_status text default null,p_sort text default 'course',p_direction text default 'asc')
returns jsonb
language plpgsql stable security definer
set search_path=public,catalogue,ref,search,auth
as $$
declare v_limit int:=least(greatest(coalesce(p_limit,50),1),200); v_offset int:=greatest(coalesce(p_offset,0),0); v_sort text:=lower(coalesce(p_sort,'course')); v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return (
 with base as (
   select c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
     coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
     coalesce(ps.code,geo.subdivision_code) subdivision_code,coalesce(ps.name,geo.subdivision_name) subdivision_name,
     sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study,c.delivery_mode,
     coalesce(d.completeness_score,0) completeness_score,coalesce(d.has_fee,false) has_fee,coalesce(d.has_intake,false) has_intake,coalesce(d.has_english,false) has_english,coalesce(d.has_scholarship,false) has_scholarship
   from catalogue.courses c
   join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   left join ref.subdivisions ps on ps.id=p.subdivision_id
   left join lateral (
     select case when count(distinct s.id)=1 then min(s.code) end subdivision_code,
            case when count(distinct s.id)=1 then min(s.name) when count(distinct s.id)>1 then count(distinct s.id)::text||' regions' end subdivision_name
     from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id left join ref.subdivisions s on s.id=cp.subdivision_id where cc.course_id=c.id
   ) geo on true
   left join ref.study_levels sl on sl.id=c.study_level_id left join ref.fields_of_study fos on fos.id=c.primary_field_id left join search.course_documents d on d.course_id=c.id
   where (nullif(trim(coalesce(p_query,'')),'') is null or c.canonical_title ilike '%'||trim(p_query)||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%' or coalesce(c.course_code,'') ilike '%'||trim(p_query)||'%' or coalesce(c.stable_key,'') ilike '%'||trim(p_query)||'%' or coalesce(fos.name,'') ilike '%'||trim(p_query)||'%')
     and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
     and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)) or exists(select 1 from catalogue.course_campuses cc2 join catalogue.campuses cp2 on cp2.id=cc2.campus_id join ref.subdivisions s2 on s2.id=cp2.subdivision_id where cc2.course_id=c.id and s2.code=upper(trim(p_subdivision_code))))
     and (p_provider_id is null or c.provider_id=p_provider_id)
     and (nullif(trim(coalesce(p_level_code,'')),'') is null or sl.code=trim(p_level_code))
     and (nullif(trim(coalesce(p_field_code,'')),'') is null or fos.code=trim(p_field_code))
     and (nullif(trim(coalesce(p_delivery_mode,'')),'') is null or c.delivery_mode=trim(p_delivery_mode))
     and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or c.lifecycle_status=trim(p_lifecycle_status))
     and (nullif(trim(coalesce(p_publication_status,'')),'') is null or c.publication_status=trim(p_publication_status))
 ), numbered as (select *,count(*) over() total_count from base), ordered as (
   select * from numbered order by
   case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,
   case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
   case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
   case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
   case when v_sort='country' and v_dir='asc' then country_code end asc,
   case when v_sort='country' and v_dir='desc' then country_code end desc,
   case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(subdivision_name,'')) end asc,
   case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(subdivision_name,'')) end desc,
   case when v_sort='level' and v_dir='asc' then level_code end asc,
   case when v_sort='level' and v_dir='desc' then level_code end desc,
   case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,
   case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
   case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
   case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
   case when v_sort='completeness' and v_dir='asc' then completeness_score end asc,
   case when v_sort='completeness' and v_dir='desc' then completeness_score end desc,
   lower(canonical_title),id limit v_limit offset v_offset)
 select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o);
end $$;
revoke all on function public.ui_courses_page(integer,integer,text,text,text,uuid,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.ui_courses_page(integer,integer,text,text,text,uuid,text,text,text,text,text,text,text) to authenticated;
