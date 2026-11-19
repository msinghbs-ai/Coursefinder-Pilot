create or replace function security.admin_providers_page(
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
set search_path = 'pg_catalog','catalogue','ref','pipeline','security','auth'
as $$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'provider'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
  v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  return (
    with base as (
      select
        p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,
        p.primary_city city,p.website,p.lifecycle_status,p.publication_status,
        p.last_verified_at,p.created_at,p.updated_at,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        (select count(distinct x.evidence_id)::bigint
           from (
             select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
             union all
             select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
             union all
             select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
           ) x) evidence_count
      from catalogue.providers p
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      where
        (
          nullif(trim(coalesce(p_query,'')),'') is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
          or coalesce(p.stable_key,'') ilike '%'||trim(p_query)||'%'
          or coalesce(p.primary_city,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.iso_alpha2::text,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.default_currency_code::text,'') ilike '%'||trim(p_query)||'%'
          or coalesce(ps.code,'') ilike '%'||trim(p_query)||'%'
          or coalesce(ps.name,'') ilike '%'||trim(p_query)||'%'
        )
        and (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text=upper(trim(p_country_code)))
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)))
        and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or p.lifecycle_status=trim(p_lifecycle_status))
        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
    ), numbered as (
      select *,count(*) over()::bigint total_count from base
    ), ordered as (
      select * from numbered
      order by
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
        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
        lower(coalesce(display_name,canonical_name)),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),
      'total',coalesce(max(total_count),0),
      'limit',v_limit,
      'offset',v_offset,
      'sort',v_sort,
      'direction',v_dir
    ) from ordered o
  );
end
$$;

revoke all on function security.admin_providers_page(integer,integer,text,text,text,text,text,text,text) from public, anon;
grant execute on function security.admin_providers_page(integer,integer,text,text,text,text,text,text,text) to authenticated, service_role;

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
language sql
stable
security invoker
set search_path = 'pg_catalog','public'
as $$
  select public.admin_read('providers_page', jsonb_strip_nulls(jsonb_build_object(
    'limit',p_limit,'offset',p_offset,'query',p_query,'country_code',p_country_code,'subdivision_code',p_subdivision_code,
    'lifecycle_status',p_lifecycle_status,'publication_status',p_publication_status,'sort',p_sort,'direction',p_direction
  )))
$$;

create or replace function public.ui_providers_page(
  p_limit integer default 500,
  p_offset integer default 0,
  p_query text default null
) returns jsonb
language sql
stable
security invoker
set search_path = 'pg_catalog','public'
as $$
  select public.admin_read('providers_page', jsonb_strip_nulls(jsonb_build_object(
    'limit',p_limit,'offset',p_offset,'query',p_query,'sort','provider','direction','asc'
  )))
$$;

revoke all on function public.ui_providers_page(integer,integer,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.ui_providers_page(integer,integer,text) from public, anon;
grant execute on function public.ui_providers_page(integer,integer,text,text,text,text,text,text,text) to authenticated, service_role;
grant execute on function public.ui_providers_page(integer,integer,text) to authenticated, service_role;

create or replace function security.admin_catalogue_page(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','security','catalogue','ref','scholarship','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'name'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_result jsonb;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end;
  v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end;
  v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end;
  v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end;
  v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end;
  v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='providers_page' then
    return security.admin_providers_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),
      nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir
    );
  elsif p_operation='courses_page' then
    return public.ui_courses_decision_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,
      nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),
      v_has_fee,v_has_intake,v_has_english,v_has_scholarship,nullif(p_args->>'min_completeness','')::numeric,nullif(p_args->>'freshness',''),
      coalesce(nullif(p_args->>'sort',''),'course'),v_dir,v_has_state,v_has_link
    );
  elsif p_operation='scholarships_page' then
    return public.ui_scholarships_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),
      coalesce(nullif(p_args->>'sort',''),'scholarship'),v_dir
    );
  elsif p_operation='campuses_page' then
    with base as (
      select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.provider_id,
        coalesce(p.display_name,p.canonical_name) provider_name,
        co.iso_alpha2::text country_code,co.name country_name,
        sd.code subdivision_code,sd.name subdivision_name,
        ca.city,ca.status,ca.publication_status,ca.last_verified_at,ca.created_at,ca.updated_at,
        (select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
      from catalogue.campuses ca
      join catalogue.providers p on p.id=ca.provider_id
      join ref.countries co on co.id=p.country_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where (nullif(trim(coalesce(p_args->>'query','')),'') is null
        or ca.name ilike '%'||trim(p_args->>'query')||'%'
        or coalesce(ca.campus_code,'') ilike '%'||trim(p_args->>'query')||'%'
        or coalesce(ca.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
        or coalesce(ca.city,'') ilike '%'||trim(p_args->>'query')||'%'
        or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
        and (nullif(p_args->>'subdivision_code','') is null or sd.code=upper(p_args->>'subdivision_code'))
        and (v_provider_id is null or ca.provider_id=v_provider_id)
        and (nullif(p_args->>'status','') is null or ca.status=p_args->>'status')
        and (nullif(p_args->>'publication_status','') is null or ca.publication_status=p_args->>'publication_status')
    ), numbered as (
      select *,count(*) over() total_count from base
    ), ordered as (
      select * from numbered order by
        case when v_sort in ('name','campus') and v_dir='asc' then lower(name) end asc,
        case when v_sort in ('name','campus') and v_dir='desc' then lower(name) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,
        case when v_sort='courses' and v_dir='asc' then course_count end asc,
        case when v_sort='courses' and v_dir='desc' then course_count end desc,
        case when v_sort='modified' and v_dir='asc' then updated_at end asc,
        case when v_sort='modified' and v_dir='desc' then updated_at end desc,
        lower(name),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir)
      into v_result from ordered o;
    return v_result;
  else
    raise exception 'unsupported catalogue page operation: %',p_operation using errcode='22023';
  end if;
end
$$;
