-- CF-CHG-20260820-007 — full-catalogue decision paging/search behind governed Admin read.
-- Preserves canonical identity and CF-CHG-20260820-001 canonical-presence semantics.

create or replace function public.ui_courses_decision_page(
  p_limit integer default 50,
  p_offset integer default 0,
  p_query text default null,
  p_country_code text default null,
  p_subdivision_code text default null,
  p_provider_id uuid default null,
  p_level_code text default null,
  p_field_code text default null,
  p_delivery_mode text default null,
  p_lifecycle_status text default null,
  p_publication_status text default null,
  p_has_fee boolean default null,
  p_has_intake boolean default null,
  p_has_english boolean default null,
  p_has_scholarship boolean default null,
  p_min_completeness numeric default null,
  p_freshness text default null,
  p_sort text default 'course',
  p_direction text default 'asc',
  p_has_state boolean default null,
  p_has_link boolean default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, catalogue, ref, scholarship, auth
as $$
declare
  v_limit int:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset int:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'course'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  return (
    with base as (
      select
        c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
        c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
        coalesce(p.display_name,p.canonical_name) provider_name,
        co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
        sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study,
        case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' else c.delivery_mode end delivery_mode,
        fee.amount fee_amount,fee.currency_code::text fee_currency,
        sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
        round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
        round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
        sch.has_scholarship,
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
      left join lateral (
        select cf.amount,cf.currency_code
        from catalogue.course_fees cf
        where cf.course_id=c.id
          and cf.fee_type='tuition'
          and cf.basis='registered_total_course'
          and coalesce(cf.status,'active')='active'
        order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
        limit 1
      ) fee on true
      cross join lateral (
        select
          exists(select 1 from catalogue.course_registrations r where r.course_id=c.id) has_registration,
          (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)) has_structure,
          exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active') has_fee,
          exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active') has_intake,
          exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active') has_english,
          (c.description is not null and length(trim(c.description))>0) has_description
      ) sig
      cross join lateral (
        select exists(
          select 1 from scholarship.scopes ss
          where coalesce(ss.include_exclude,'include')='include'
            and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id))
        ) has_scholarship
      ) sch
      left join lateral (
        select count(distinct cc.campus_id)::int campus_count,count(distinct s.id)::int region_count,min(s.code) single_code,min(s.name) single_name
        from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        left join ref.subdivisions s on s.id=ca.subdivision_id
        where cc.course_id=c.id
      ) geo on true
      left join lateral (
        select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
        from catalogue.course_campuses cc
        where cc.course_id=c.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
      ) dm on true
      where (nullif(trim(coalesce(p_query,'')),'') is null
        or c.canonical_title ilike '%'||trim(p_query)||'%'
        or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
        or coalesce(c.course_code,'') ilike '%'||trim(p_query)||'%'
        or coalesce(c.stable_key,'') ilike '%'||trim(p_query)||'%')
        and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code)))
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id join ref.subdivisions s on s.id=ca.subdivision_id
          where cc.course_id=c.id and s.code=upper(trim(p_subdivision_code))))
        and (p_provider_id is null or c.provider_id=p_provider_id)
        and (nullif(trim(coalesce(p_level_code,'')),'') is null or sl.code=trim(p_level_code))
        and (nullif(trim(coalesce(p_field_code,'')),'') is null or fos.code=trim(p_field_code))
        and (nullif(trim(coalesce(p_delivery_mode,'')),'') is null or coalesce(c.delivery_mode,'')=trim(p_delivery_mode)
          or exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode=trim(p_delivery_mode)))
        and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or c.lifecycle_status=trim(p_lifecycle_status))
        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or c.publication_status=trim(p_publication_status))
    ), filtered as (
      select * from base
      where (p_has_fee is null or has_fee=p_has_fee)
        and (p_has_intake is null or has_intake=p_has_intake)
        and (p_has_english is null or has_english=p_has_english)
        and (p_has_scholarship is null or has_scholarship=p_has_scholarship)
        and (p_has_state is null or has_state=p_has_state)
        and (p_has_link is null or has_link=p_has_link)
        and (p_min_completeness is null or completeness_score_v2>=p_min_completeness)
        and (nullif(trim(coalesce(p_freshness,'')),'') is null
          or (p_freshness='never_verified' and last_verified_at is null)
          or (p_freshness='modified_7d' and updated_at>=now()-interval '7 days')
          or (p_freshness='modified_30d' and updated_at>=now()-interval '30 days')
          or (p_freshness='stale_180d' and (last_verified_at is null or last_verified_at<now()-interval '180 days')))
    ), numbered as (
      select *,count(*) over() total_count from filtered
    ), ordered as (
      select * from numbered order by
        case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,
        case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,
        case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
        case when v_sort='fee' and v_dir='asc' then fee_amount end asc nulls last,
        case when v_sort='fee' and v_dir='desc' then fee_amount end desc nulls last,
        case when v_sort='completeness' and v_dir='asc' then completeness_score_v2 end asc,
        case when v_sort='completeness' and v_dir='desc' then completeness_score_v2 end desc,
        case when v_sort='modified' and v_dir='asc' then updated_at end asc,
        case when v_sort='modified' and v_dir='desc' then updated_at end desc,
        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
        lower(canonical_title),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir
    ) from ordered o
  );
end
$$;

create or replace function security.admin_catalogue_page(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, security, catalogue, ref, scholarship, auth
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
    return public.ui_providers_page(
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

revoke all on function security.admin_catalogue_page(text,jsonb) from public,anon;
grant execute on function security.admin_catalogue_page(text,jsonb) to authenticated,service_role;

create or replace function public.admin_read(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation in ('providers_page','courses_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id));
  end if;
  return v_result;
end
$$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;

-- Underlying page/list functions are internal projections once browser routing is through admin_read.
revoke all on function public.ui_providers_page(integer,integer,text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean) from public,anon,authenticated;
revoke all on function public.ui_scholarships_page(integer,integer,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.ui_providers_list(integer) from public,anon,authenticated;
revoke all on function public.ui_campuses_list(integer) from public,anon,authenticated;
revoke all on function public.ui_scholarships_list(integer) from public,anon,authenticated;

grant execute on function public.ui_providers_page(integer,integer,text,text,text,text,text,text,text) to service_role;
grant execute on function public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean) to service_role;
grant execute on function public.ui_scholarships_page(integer,integer,text,text,text,text,text,text) to service_role;
grant execute on function public.ui_providers_list(integer) to service_role;
grant execute on function public.ui_campuses_list(integer) to service_role;
grant execute on function public.ui_scholarships_list(integer) to service_role;

comment on function security.admin_catalogue_page(text,jsonb) is
  'CF-CHG-20260820-007 role-checked server-side catalogue paging/search for Admin decision grids. Course readiness uses canonical six-signal presence, not Search completeness.';
comment on function public.admin_read(text,jsonb) is
  'Governed browser read contract for catalogue paging, Insights, Evidence and Course fee semantics.';
