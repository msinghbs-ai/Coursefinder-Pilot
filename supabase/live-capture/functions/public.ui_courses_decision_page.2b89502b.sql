CREATE OR REPLACE FUNCTION public.ui_courses_decision_page(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_subdivision_code text DEFAULT NULL::text, p_provider_id uuid DEFAULT NULL::uuid, p_level_code text DEFAULT NULL::text, p_field_code text DEFAULT NULL::text, p_delivery_mode text DEFAULT NULL::text, p_lifecycle_status text DEFAULT NULL::text, p_publication_status text DEFAULT NULL::text, p_has_fee boolean DEFAULT NULL::boolean, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_min_completeness numeric DEFAULT NULL::numeric, p_freshness text DEFAULT NULL::text, p_sort text DEFAULT 'course'::text, p_direction text DEFAULT 'asc'::text, p_has_state boolean DEFAULT NULL::boolean, p_has_link boolean DEFAULT NULL::boolean, p_university_group text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'catalogue', 'ref', 'scholarship', 'auth'
AS $function$
declare
  v_limit int:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset int:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'course'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
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
        exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and l.status='active') has_link,
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
        and (nullif(trim(coalesce(p_university_group,'')),'') is null or c.provider_id in (select security.university_group_provider_ids(p_university_group)))
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
      'items',coalesce(jsonb_agg((to_jsonb(o)-'total_count')||jsonb_build_object('university_groups',security.provider_university_groups(o.provider_id))),'[]'::jsonb),
      'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir
    ) from ordered o
  );
end
$function$
