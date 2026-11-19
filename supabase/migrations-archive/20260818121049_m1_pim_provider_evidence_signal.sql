create or replace function public.ui_providers_page(
  p_limit integer default 50,
  p_offset integer default 0,
  p_query text default null,
  p_country_code text default null,
  p_subdivision_code text default null,
  p_lifecycle_status text default null,
  p_publication_status text default null,
  p_sort text default 'provider',
  p_direction text default 'asc'
) returns jsonb
language plpgsql
stable
security definer
set search_path = public,catalogue,ref,pipeline,auth
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_sort text := case lower(coalesce(p_sort,'provider'))
    when 'provider' then 'provider' when 'country' then 'country' when 'subdivision' then 'subdivision'
    when 'city' then 'city' when 'courses' then 'courses' when 'lifecycle' then 'lifecycle'
    when 'publication' then 'publication' when 'verified' then 'verified' when 'evidence' then 'evidence'
    else 'provider' end;
  v_dir text := case lower(coalesce(p_direction,'asc')) when 'desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return (
    with base as (
      select p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,
        coalesce(ps.code,geo.subdivision_code) subdivision_code,
        coalesce(ps.name,geo.subdivision_name) subdivision_name,
        coalesce(ps.subdivision_type,geo.subdivision_type) subdivision_type,
        coalesce(p.primary_city,geo.city) city,p.website,p.lifecycle_status,p.publication_status,p.last_verified_at,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        (select count(distinct x.evidence_id)::bigint from (
           select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
           union all select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
           union all select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
         ) x) evidence_count
      from catalogue.providers p join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      left join lateral (
        select min(s.code) subdivision_code,
          case when count(distinct s.id)=1 then min(s.name) when count(distinct s.id)>1 then count(distinct s.id)::text||' regions' else null end subdivision_name,
          case when count(distinct s.id)=1 then min(s.subdivision_type) else 'multiple' end subdivision_type,
          min(cp.city) filter(where cp.city is not null) city
        from catalogue.campuses cp left join ref.subdivisions s on s.id=cp.subdivision_id where cp.provider_id=p.id
      ) geo on true
      where (nullif(trim(coalesce(p_query,'')),'') is null
        or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(p.stable_key,'') ilike '%'||trim(p_query)||'%'
        or coalesce(p.primary_city,geo.city,'') ilike '%'||trim(p_query)||'%'
        or coalesce(c.iso_alpha2::text,'') ilike '%'||trim(p_query)||'%'
        or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(ps.code,geo.subdivision_code,'') ilike '%'||trim(p_query)||'%'
        or coalesce(ps.name,geo.subdivision_name,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text=upper(trim(p_country_code)))
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or coalesce(ps.code,geo.subdivision_code)=upper(trim(p_subdivision_code)))
        and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or p.lifecycle_status=trim(p_lifecycle_status))
        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
    ), numbered as (select *,count(*) over()::bigint total_count from base), ordered as (
      select * from numbered order by
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(display_name,canonical_name)) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(display_name,canonical_name)) end desc,
        case when v_sort='country' and v_dir='asc' then country_code end asc,
        case when v_sort='country' and v_dir='desc' then country_code end desc,
        case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(subdivision_name,'')) end asc,
        case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(subdivision_name,'')) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,
        case when v_sort='courses' and v_dir='asc' then course_count end asc,
        case when v_sort='courses' and v_dir='desc' then course_count end desc,
        case when v_sort='lifecycle' and v_dir='asc' then lifecycle_status end asc,
        case when v_sort='lifecycle' and v_dir='desc' then lifecycle_status end desc,
        case when v_sort='publication' and v_dir='asc' then publication_status end asc,
        case when v_sort='publication' and v_dir='desc' then publication_status end desc,
        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
        case when v_sort='evidence' and v_dir='asc' then evidence_count end asc,
        case when v_sort='evidence' and v_dir='desc' then evidence_count end desc,
        lower(coalesce(display_name,canonical_name)),id limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(o.total_count),(select count(*) from base),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) from ordered o
  );
end;$$;
revoke all on function public.ui_providers_page(integer,integer,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.ui_providers_page(integer,integer,text,text,text,text,text,text,text) to authenticated;
