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
language plpgsql stable security definer
set search_path='public','catalogue','ref','pipeline','auth'
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_sort text := case lower(coalesce(p_sort,'provider')) when 'provider' then 'provider' when 'country' then 'country' when 'currency' then 'currency' when 'subdivision' then 'subdivision' when 'city' then 'city' when 'courses' then 'courses' when 'lifecycle' then 'lifecycle' when 'publication' then 'publication' when 'verified' then 'verified' when 'evidence' then 'evidence' else 'provider' end;
  v_dir text := case lower(coalesce(p_direction,'asc')) when 'desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  return (
    with base as (
      select p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        coalesce(ps.code,geo.subdivision_code) subdivision_code,
        coalesce(ps.name,geo.subdivision_name) subdivision_name,
        coalesce(ps.subdivision_type,geo.subdivision_type) subdivision_type,
        coalesce(p.primary_city,geo.city) city,p.website,p.lifecycle_status,p.publication_status,p.last_verified_at,p.created_at,p.updated_at,
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
        or coalesce(c.default_currency_code::text,'') ilike '%'||trim(p_query)||'%'
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
        case when v_sort='currency' and v_dir='asc' then currency_code end asc,
        case when v_sort='currency' and v_dir='desc' then currency_code end desc,
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
end$$;

create or replace function public.ui_provider_related_courses(
  p_provider_id uuid,
  p_limit integer default 25,
  p_offset integer default 0,
  p_query text default null,
  p_lifecycle_status text default null,
  p_publication_status text default null
) returns jsonb language sql stable security definer
set search_path='public','catalogue','auth' as $$
with base as (
  select c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,c.delivery_mode,c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at
  from catalogue.courses c
  where auth.uid() is not null and c.provider_id=p_provider_id
    and (nullif(trim(coalesce(p_query,'')),'') is null or coalesce(c.display_title,c.canonical_title,'') ilike '%'||trim(p_query)||'%' or coalesce(c.course_code,'') ilike '%'||trim(p_query)||'%' or coalesce(c.stable_key,'') ilike '%'||trim(p_query)||'%')
    and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or c.lifecycle_status=trim(p_lifecycle_status))
    and (nullif(trim(coalesce(p_publication_status,'')),'') is null or c.publication_status=trim(p_publication_status))
), numbered as (select *,count(*) over() total_count from base)
select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(x)-'total_count' order by lower(coalesce(x.display_title,x.canonical_title))),'[]'::jsonb),'total',coalesce(max(x.total_count),0),'limit',least(greatest(coalesce(p_limit,25),1),100),'offset',greatest(coalesce(p_offset,0),0))
from (select * from numbered order by lower(coalesce(display_title,canonical_title)) limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0)) x;
$$;

create or replace function public.ui_provider_related_evidence(
  p_provider_id uuid,
  p_limit integer default 25,
  p_offset integer default 0,
  p_query text default null,
  p_evidence_type text default null
) returns jsonb language sql stable security definer
set search_path='public','catalogue','pipeline','auth' as $$
with ids as (
  select e.id from pipeline.evidence_artifacts e where e.entity_id=p_provider_id
  union select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p_provider_id and pi.evidence_id is not null
  union select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p_provider_id and pr.evidence_id is not null
), base as (
  select e.id,e.evidence_type,e.source_url,e.content_hash,e.mime_type,e.captured_at,e.valid_from,e.valid_to,e.supersedes_evidence_id,s.label source_label,s.source_type
  from ids i join pipeline.evidence_artifacts e on e.id=i.id left join pipeline.sources s on s.id=e.source_id
  where auth.uid() is not null
    and (nullif(trim(coalesce(p_query,'')),'') is null or coalesce(e.evidence_type,'') ilike '%'||trim(p_query)||'%' or coalesce(s.label,'') ilike '%'||trim(p_query)||'%' or coalesce(e.source_url,'') ilike '%'||trim(p_query)||'%' or coalesce(e.content_hash,'') ilike '%'||trim(p_query)||'%')
    and (nullif(trim(coalesce(p_evidence_type,'')),'') is null or e.evidence_type=trim(p_evidence_type))
), numbered as (select *,count(*) over() total_count from base)
select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(x)-'total_count' order by x.captured_at desc nulls last),'[]'::jsonb),'total',coalesce(max(x.total_count),0),'limit',least(greatest(coalesce(p_limit,25),1),100),'offset',greatest(coalesce(p_offset,0),0))
from (select * from numbered order by captured_at desc nulls last limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0)) x;
$$;

revoke execute on function public.ui_provider_related_courses(uuid,integer,integer,text,text,text) from public,anon;
revoke execute on function public.ui_provider_related_evidence(uuid,integer,integer,text,text) from public,anon;
grant execute on function public.ui_provider_related_courses(uuid,integer,integer,text,text,text) to authenticated;
grant execute on function public.ui_provider_related_evidence(uuid,integer,integer,text,text) to authenticated;
