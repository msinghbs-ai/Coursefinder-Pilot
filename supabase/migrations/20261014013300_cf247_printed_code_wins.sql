-- CF-247 v2.15.271 (follow-up to 20261014013200): a printed code always wins. The course list and record show the StudySearch code only
-- while the course has no identifier of a printed type (ref.course_code_schemes.printed), so marking a type as printed takes effect at
-- once, with no code removed. Ontario portal codes (on_aps, e.g. Humber 01149) are the colleges' own program codes as published on
-- ontariocolleges.ca, so they are marked printed. The StudySearch codes already given stay recorded (a code never changes).
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.admin_course_page_fast_base(jsonb)": "9ddef257dbd6b515e1cf586354517fb3", "security.admin_course_page_unfiltered_fast(jsonb)": "3b7ea35f749554d044ffaefc0c2054cd", "security.course_display_code_v1(uuid)": "9564d681a931571a0b221a324d66071e"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;
update ref.course_code_schemes set printed = true, label = 'Ontario college program code', note = 'Published on ontariocolleges.ca', updated_at = now() where scheme = 'on_aps';

CREATE OR REPLACE FUNCTION security.admin_course_page_fast_base(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end;
  v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end;
  v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end;
  v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end;
  v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end;
  v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
  v_min_completeness numeric:=nullif(p_args->>'min_completeness','')::numeric;
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
  v_result jsonb;
  v_sub_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is not null then
    select sd.id into v_sub_id from ref.subdivisions sd where sd.code=upper(trim(p_args->>'subdivision_code'));
  end if;

  -- Fee/readiness ordering is still intentionally not promoted by the v2.10 UI.
  -- Preserve the accepted legacy implementation only for explicit direct callers of
  -- those derived sorts. All normal derived filters remain in the bounded fast path.
  if v_sort in ('fee','completeness') then
    return security.admin_course_page_search_state(public.ui_courses_decision_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,
      nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),
      v_has_fee,v_has_intake,v_has_english,v_has_scholarship,v_min_completeness,nullif(p_args->>'freshness',''),
      v_sort,v_dir,v_has_state,v_has_link,v_group
    ));
  end if;

  with base as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,c.open_to_international,c.open_to_domestic,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    where (nullif(trim(coalesce(p_args->>'query','')),'') is null
      or c.canonical_title ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.course_code,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
      or exists(select 1 from catalogue.course_identifiers ci where ci.course_id=c.id and ci.scheme='studysearch' and upper(ci.identifier) like upper(trim(p_args->>'query'))||'%'))
      and (nullif(trim(coalesce(p_args->>'country_code','')),'') is null or co.iso_alpha2::text=upper(trim(p_args->>'country_code')))
      and (v_provider_id is null or c.provider_id=v_provider_id)
      and (v_group is null or c.provider_id in (select security.university_group_provider_ids(v_group)))
      and (nullif(trim(coalesce(p_args->>'level_code','')),'') is null or sl.code=trim(p_args->>'level_code'))
      and (nullif(trim(coalesce(p_args->>'field_code','')),'') is null or fos.code=trim(p_args->>'field_code'))
      and (nullif(trim(coalesce(p_args->>'lifecycle_status','')),'') is null or c.lifecycle_status=trim(p_args->>'lifecycle_status'))
      and (nullif(trim(coalesce(p_args->>'publication_status','')),'') is null or c.publication_status=trim(p_args->>'publication_status'))
      and (nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is null or exists(
        select 1 from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        join ref.subdivisions sd on sd.id=ca.subdivision_id
        where cc.course_id=c.id and sd.code=upper(trim(p_args->>'subdivision_code')))
        or (p.subdivision_id=v_sub_id and not exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id
          where cc.course_id=c.id and ca.subdivision_id is not null)))
      and (nullif(trim(coalesce(p_args->>'delivery_mode','')),'') is null
        or nullif(btrim(c.delivery_mode),'')=trim(p_args->>'delivery_mode')
        or (nullif(btrim(c.delivery_mode),'') is null
            and exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode=trim(p_args->>'delivery_mode'))))
      and (nullif(trim(coalesce(p_args->>'freshness','')),'') is null
        or (p_args->>'freshness'='never_verified' and c.last_verified_at is null)
        or (p_args->>'freshness'='modified_7d' and c.updated_at>=now()-interval '7 days')
        or (p_args->>'freshness'='modified_30d' and c.updated_at>=now()-interval '30 days')
        or (p_args->>'freshness'='stale_180d' and (c.last_verified_at is null or c.last_verified_at<now()-interval '180 days')))
      and (v_has_fee is null or exists(
        select 1 from catalogue.course_fees cf
        where cf.course_id=c.id and coalesce(cf.status,'active')='active')=v_has_fee)
      and (v_has_intake is null or exists(
        select 1 from catalogue.course_intakes ci
        where ci.course_id=c.id and coalesce(ci.status,'active')='active')=v_has_intake)
      and (v_has_english is null or exists(
        select 1 from catalogue.course_english_requirements er
        where er.course_id=c.id and coalesce(er.status,'active')='active')=v_has_english)
      and (v_has_scholarship is null or exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id)))=v_has_scholarship)
      and (v_has_state is null or (p.subdivision_id is not null or exists(
        select 1 from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        where cc.course_id=c.id and ca.subdivision_id is not null))=v_has_state)
      and (v_has_link is null or exists(
        select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and l.status='active')=v_has_link)
      and (nullif(p_args->>'applicant','') is null
        or (p_args->>'applicant'='international' and c.open_to_international is true)
        or (p_args->>'applicant'='domestic_only' and c.open_to_international is false)
        or (p_args->>'applicant'='both' and c.open_to_international is true and c.open_to_domestic is true)
        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
      and (v_min_completeness is null or (
        (exists(select 1 from catalogue.course_registrations r where r.course_id=c.id))::int
        +(c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id))::int
        +(exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active'))::int
        +(c.description is not null and length(trim(c.description))>0)::int
      )*100.0/6.0 >= v_min_completeness)
  ), numbered as (
    select *,count(*) over() total_count from base
  ), paged as (
    select * from numbered order by
      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,
      case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
      case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
      case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
      case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,
      case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
      case when v_sort='modified' and v_dir='asc' then updated_at end asc,
      case when v_sort='modified' and v_dir='desc' then updated_at end desc,
      case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
      case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
      lower(canonical_title),id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      pg.open_to_international,pg.open_to_domestic,coalesce(ssc.identifier,pg.course_code) display_code,case when ssc.identifier is not null then 'studysearch' else 'own' end code_kind,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      coalesce(nullif(btrim(pg.canonical_delivery_mode),''),case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' end) delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,(coalesce(geo.region_count,0)>0 or psd.id is not null) has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code when coalesce(geo.region_count,0)=0 then psd.code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else psd.name end subdivision_name,
      case when coalesce(geo.region_count,0)>0 then geo.region_count when psd.id is not null then 1 else 0 end region_count,
      case when coalesce(geo.region_count,0)>0 then 'campus' when psd.id is not null then 'provider' else null end region_source,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups,
      pg.total_count
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code from catalogue.course_fees cf
      where cf.course_id=pg.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (select exists(select 1 from scholarship.scopes ss where coalesce(ss.include_exclude,'include')='include' and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))) has_scholarship) sch
    cross join lateral (select exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=pg.id and l.status='active') has_link) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,count(distinct sd.id)::int region_count,min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id left join ref.subdivisions sd on sd.id=ca.subdivision_id where cc.course_id=pg.id
    ) geo on true
    left join ref.subdivisions psd on psd.id=(select p2.subdivision_id from catalogue.providers p2 where p2.id=pg.provider_id)
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id=pg.id and i.scheme='studysearch'
      and not exists (select 1 from catalogue.course_identifiers j join ref.course_code_schemes s on s.scheme=j.scheme and s.printed where j.course_id=pg.id) limit 1) ssc on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'),'[]'::jsonb),
    'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
    'execution_profile','paged_enrichment_v3'
  ) into v_result from enriched e;
  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_unfiltered_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_total bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select count(*) into v_total from catalogue.courses;

  with paged as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    order by lower(c.canonical_title),c.id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      coalesce(ssc.identifier,pg.course_code) display_code,case when ssc.identifier is not null then 'studysearch' else 'own' end code_kind,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      coalesce(nullif(btrim(pg.canonical_delivery_mode),''),case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' end) delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,(coalesce(geo.region_count,0)>0 or psd.id is not null) has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code when coalesce(geo.region_count,0)=0 then psd.code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else psd.name end subdivision_name,
      case when coalesce(geo.region_count,0)>0 then geo.region_count when psd.id is not null then 1 else 0 end region_count,
      case when coalesce(geo.region_count,0)>0 then 'campus' when psd.id is not null then 'provider' else null end region_source,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code
      from catalogue.course_fees cf
      where cf.course_id=pg.id
        and cf.fee_type='tuition'
        and cf.basis='registered_total_course'
        and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
      limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (
      select exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))
      ) has_scholarship
    ) sch
    cross join lateral (
      select exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=pg.id and l.status='active') has_link
    ) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,
             count(distinct sd.id)::int region_count,
             min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc
      join catalogue.campuses ca on ca.id=cc.campus_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where cc.course_id=pg.id
    ) geo on true
    left join ref.subdivisions psd on psd.id=(select p2.subdivision_id from catalogue.providers p2 where p2.id=pg.provider_id)
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id=pg.id and i.scheme='studysearch'
      and not exists (select 1 from catalogue.course_identifiers j join ref.course_code_schemes s on s.scheme=j.scheme and s.printed where j.course_id=pg.id) limit 1) ssc on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc
      where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb),
    'total',v_total,'limit',v_limit,'offset',v_offset,
    'sort','course','direction','asc',
    'execution_profile','page_first_unfiltered_v1'
  ) into v_result
  from enriched e;

  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION security.course_display_code_v1(p_course uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when ss.identifier is not null then jsonb_build_object('code', ss.identifier, 'kind', 'studysearch', 'label', 'StudySearch code')
              else jsonb_build_object('code', c.course_code, 'kind', 'own',
                     'label', coalesce((select s.label from catalogue.course_identifiers i join ref.course_code_schemes s on s.scheme = i.scheme
                                         where i.course_id = c.id and i.identifier = c.course_code limit 1), 'Course code')) end
    from catalogue.courses c
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id = c.id and i.scheme = 'studysearch'
      and not exists (select 1 from catalogue.course_identifiers j join ref.course_code_schemes s on s.scheme = j.scheme and s.printed where j.course_id = c.id)
     limit 1) ss on true
   where c.id = p_course
$function$;

do $post$
declare v_expected jsonb := '{"security.admin_course_page_fast_base(jsonb)": "12f21dca758c75f6ffbc06f94fa12382", "security.admin_course_page_unfiltered_fast(jsonb)": "aaae93e378dcbd66c9536858c6b4dce8", "security.course_display_code_v1(uuid)": "ecff13f8e16dd993f48360a2dc7fa379"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.271 printed code post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
