-- CF-247 v2.15.270 (Platform Admin, 14 Oct 2026 07:13: "Bug/fix: Courses > state filter is not showing options for nz and Canada. Cross check
-- all filters across all pages and report all relevant drop down options are visible.")
--   1 A course's region is its campus region; when no campus with a region is recorded for the course (all NZ and Canadian courses today),
--     it is the provider's region. Courses › Region (NZ), Province / territory (CA) now list regions, and the course list filters, shows
--     and counts them the same way (column "State / Region", "Has state" filter). Each row says where its region came from (region_source).
--   2 Delivery options and the course list read the course's own delivery mode first (on campus, online, blended, on campus and online);
--     the campus value is used only when the course has none. Before, every course showed "on_campus" because campus rows all say so.
--   3 An empty filter says why (no university groups for this country; field of study not classified for this country yet).
--   4 Data Quality, Enrichment operations and Provider assets accept every country in the catalogue (Canada was refused). Data Quality's
--     stored snapshots stay AU+NZ, AU and NZ (the table's check allows only those); another country is computed when it is opened.
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.admin_catalogue_filter_page(jsonb)": "41fccde4b9bf53aaf9866769897557e1", "security.admin_course_page_fast_base(jsonb)": "520c6f535e5d7c5c43dea7068b21ae66", "security.admin_course_page_unfiltered_fast(jsonb)": "0d95e3df806173bde46ac9319bcf282a", "security.data_quality_overview_cached(jsonb)": "f514296efa43b238adaf4369497af337", "security.admin_enrichment_operations_read(jsonb)": "f9d36378a8a1ac8ba289a8467510480d", "security.admin_provider_asset_read(text,jsonb)": "ccfc43758d0372057cd7fe0486aef5fe"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- Countries that have courses in the catalogue (AU, CA, NZ today). Read by Data Quality, Enrichment operations and Provider assets.
CREATE OR REPLACE FUNCTION security.catalogue_country_codes_v1()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(co.iso_alpha2::text order by co.iso_alpha2::text), '{}'::text[])
    from ref.countries co
   where exists (select 1 from catalogue.providers p join catalogue.courses c on c.provider_id = p.id where p.country_id = co.id)
$function$;
revoke all on function security.catalogue_country_codes_v1() from public, anon;
grant execute on function security.catalogue_country_codes_v1() to authenticated, service_role;

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
  v_sub_id uuid;
  v_empty text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_subdivision is not null then select sd.id into v_sub_id from ref.subdivisions sd where sd.code=v_subdivision; end if;

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
      select s.code value,s.name label,s.code meta
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      join catalogue.course_campuses cc on cc.course_id=c.id
      join catalogue.campuses cp on cp.id=cc.campus_id
      join ref.subdivisions s on s.id=cp.subdivision_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
      union
      select s.code,s.name,s.code
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      join ref.subdivisions s on s.id=p.subdivision_id
      where (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
        and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                        where cc.course_id=c.id and cp.subdivision_id is not null)
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
        ) or (p.subdivision_id=v_sub_id and not exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
          where cc.course_id=c.id and cp.subdivision_id is not null)))
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
        ) or (p.subdivision_id=v_sub_id and not exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
          where cc.course_id=c.id and cp.subdivision_id is not null)))
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
        ) or (p.subdivision_id=v_sub_id and not exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
          where cc.course_id=c.id and cp.subdivision_id is not null)))
        and (v_query is null or lower(fos.name||' '||fos.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='delivery' then
    with q as (
      select m value,upper(left(replace(m,'_',' '),1))||substr(replace(m,'_',' '),2) label,null::text meta
      from (
        select distinct coalesce(nullif(btrim(c.delivery_mode),''),cc.delivery_mode) m
        from catalogue.courses c
        join catalogue.providers p on p.id=c.provider_id
        join ref.countries co on co.id=p.country_id
        left join catalogue.course_campuses cc on cc.course_id=c.id and nullif(btrim(c.delivery_mode),'') is null
        where (v_country is null or co.iso_alpha2::text=v_country)
          and (v_subdivision is null or exists(
          select 1 from catalogue.course_campuses cc2
          join catalogue.campuses cp2 on cp2.id=cc2.campus_id
          join ref.subdivisions s2 on s2.id=cp2.subdivision_id
          where cc2.course_id=c.id and s2.code=v_subdivision
        ) or (p.subdivision_id=v_sub_id and not exists(
          select 1 from catalogue.course_campuses cc2 join catalogue.campuses cp2 on cp2.id=cc2.campus_id
          where cc2.course_id=c.id and cp2.subdivision_id is not null)))
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
end $function$;

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
      or coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%')
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
      pg.open_to_international,pg.open_to_domestic,pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
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

CREATE OR REPLACE FUNCTION security.data_quality_overview_cached(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security'
AS $function$
declare
  v_country text:=nullif(upper(btrim(coalesce(p_args->>'country_code',''))),'');
  v_scope text;
  v_row security.data_quality_overview_snapshots%rowtype;
  v_reason text;
begin
  if v_country is not null and not (v_country = any(security.catalogue_country_codes_v1())) then
    raise exception 'unsupported Data Quality country scope: %',v_country using errcode='22023';
  end if;
  v_scope:=coalesce(v_country,'AU+NZ');
  select * into v_row from security.data_quality_overview_snapshots where scope_code=v_scope;
  if not found and v_country is not null then
    -- stored snapshots: AU+NZ, AU and NZ (the snapshot table's check). Another catalogue country is computed when opened (Canada about 2 s).
    return security.data_quality_overview_impl(jsonb_build_object('country_code',v_country))
      || jsonb_build_object('scope_countries',to_jsonb(security.catalogue_country_codes_v1()),
           'snapshot',jsonb_build_object('scope_code',v_country,'computed_at',now(),'refresh_mode','computed_when_opened','live_drilldown',true));
  end if;
  if not found then
    raise exception 'Data Quality overview snapshot unavailable for scope %',v_scope using errcode='55000';
  end if;
  v_reason:=coalesce(v_row.payload#>>'{policy,reason}','Domain readiness is reported by governed domain.')
    ||' Aggregate snapshot computed at '||v_row.computed_at::text
    ||'; refreshed off-peak daily and after explicit post-ingestion refresh; exception drill-down is live.';
  return jsonb_set(v_row.payload,'{policy,reason}',to_jsonb(v_reason),true)
    || jsonb_build_object('scope_countries',to_jsonb(security.catalogue_country_codes_v1()),'snapshot',jsonb_build_object('scope_code',v_row.scope_code,'computed_at',v_row.computed_at,'compute_duration_ms',v_row.compute_duration_ms,'refresh_interval_minutes',1440,'refresh_mode','off_peak_daily_plus_explicit_post_ingestion','live_drilldown',true));
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_enrichment_operations_read(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'search', 'catalogue', 'ref'
AS $function$
declare
  v_rank integer:=security.current_role_rank();
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country_code','')),''));
  v_hours integer:=least(greatest(coalesce(nullif(p_args->>'hours','')::integer,24),1),168);
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,30),1),100);
  v_result jsonb;
begin
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if v_country is not null and not (v_country = any(security.catalogue_country_codes_v1())) then raise exception 'unsupported country' using errcode='22023'; end if;

  with current_cov as (
    select country_code,field_key,max(covered_count)::bigint covered_count,max(total_courses)::bigint total_courses,
           max(queueable_count)::bigint queueable_count,max(blocked_count)::bigint blocked_count,
           max(awaiting_qualification_count)::bigint awaiting_count,max(snapshot_hour) snapshot_hour
    from pipeline.enrichment_coverage_snapshots s
    where s.snapshot_hour=(select max(s2.snapshot_hour) from pipeline.enrichment_coverage_snapshots s2)
      and (v_country is null or s.country_code=v_country)
    group by country_code,field_key
  ), prior_hour as (
    select distinct on(country_code,field_key) country_code,field_key,covered_count,snapshot_hour
    from pipeline.enrichment_coverage_snapshots
    where snapshot_hour < date_trunc('hour',now()) and (v_country is null or country_code=v_country)
    order by country_code,field_key,snapshot_hour desc
  ), prior_day as (
    select distinct on(country_code,field_key) country_code,field_key,covered_count,snapshot_hour
    from pipeline.enrichment_coverage_snapshots
    where snapshot_hour <= date_trunc('hour',now())-interval '24 hours' and (v_country is null or country_code=v_country)
    order by country_code,field_key,snapshot_hour desc
  ), coverage_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'country_code',c.country_code,'field_key',c.field_key,'current',c.covered_count,'total',c.total_courses,
      'coverage_pct',case when c.total_courses>0 then round((100*c.covered_count::numeric/c.total_courses),2) else 0 end,
      'remaining',greatest(c.total_courses-c.covered_count,0),
      'added_hour',case when ph.covered_count is null then null else c.covered_count-ph.covered_count end,
      'added_day',case when pd.covered_count is null then null else c.covered_count-pd.covered_count end,
      'queueable',c.queueable_count,'blocked',c.blocked_count,'awaiting_qualification',c.awaiting_count,
      'snapshot_hour',c.snapshot_hour,'hour_baseline_at',ph.snapshot_hour,'day_baseline_at',pd.snapshot_hour
    ) order by c.country_code,c.field_key),'[]'::jsonb) value
    from current_cov c left join prior_hour ph using(country_code,field_key) left join prior_day pd using(country_code,field_key)
  ), scoped_recent_items as (
    select ri.*
    from pipeline.layer2_run_items ri
    join catalogue.courses c on ri.entity_type='course' and c.id=ri.entity_id
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    where (v_country is null or trim(co.iso_alpha2)=v_country)
  ), work as (
    select jsonb_build_object(
      'queued',(select count(*) from scoped_recent_items where status='queued'),
      'processing',(select count(*) from scoped_recent_items where status in('running','discovering','acquiring','extracting')),
      'fetched',(select count(*) from pipeline.layer2_provider_attempts pa where pa.status in('completed','success','succeeded') and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'fetch_failures',(select count(*) from pipeline.layer2_provider_attempts pa where pa.status in('failed','error','blocked') and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'evidence_24h',(select count(*) from pipeline.evidence_artifacts e where e.job_id is not null and e.captured_at>=now()-interval '24 hours' and exists(select 1 from pipeline.layer2_run_items x where x.job_id=e.job_id)),
      'layer3_24h',(select count(*) from scoped_recent_items where status='layer3_required' and coalesce(completed_at,updated_at,created_at)>=now()-interval '24 hours'),
      'admitted_source_records_24h',(select count(*) from pipeline.course_fact_source_records sr where sr.applied_at>=now()-interval '24 hours'),
      'http_429_24h',(select count(*) from pipeline.layer2_provider_attempts pa where pa.response_http_status=429 and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'http_5xx_24h',(select count(*) from pipeline.layer2_provider_attempts pa where pa.response_http_status>=500 and coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'vendor_units_24h',(select coalesce(sum(coalesce((nullif(pa.metrics->>'vendor_units',''))::numeric,0)),0) from pipeline.layer2_provider_attempts pa where coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours'),
      'vendor_cost_usd_24h',(select coalesce(sum(coalesce((nullif(pa.metrics->>'estimated_request_cost_usd',''))::numeric,0)),0) from pipeline.layer2_provider_attempts pa where coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '24 hours')
    ) value
  ), hourly as (
    select coalesce(jsonb_agg(to_jsonb(h) order by h.hour_utc),'[]'::jsonb) value
    from (select * from pipeline.layer2_enrichment_hourly_admin_cache_v1
          where hour_utc>=date_trunc('hour',now())-(v_hours||' hours')::interval
            and (v_country is null or country_code=v_country)
          order by hour_utc desc limit v_hours*4) h
  ), blockers as (
    select coalesce(jsonb_agg(x order by (x->>'courses')::bigint desc,x->>'country_code',x->>'field_key'),'[]'::jsonb) value
    from (
      select jsonb_build_object('country_code',country_code,'field_key',field_key,'state','queueable','reason','ready_under_current_qualified_scope','courses',queueable_count) x from current_cov where queueable_count>0
      union all
      select jsonb_build_object('country_code',country_code,'field_key',field_key,'state','blocked','reason','blocked_under_current_scope','courses',blocked_count) from current_cov where blocked_count>0
      union all
      select jsonb_build_object('country_code',country_code,'field_key',field_key,'state','awaiting_source_profile_qualification','reason','source_profile_qualification_required','courses',awaiting_count) from current_cov where awaiting_count>0
    ) b
  ), reasons as (
    select coalesce(jsonb_agg(jsonb_build_object('reason',reason,'items',items,'fields_targeted',fields_targeted,'fields_resolved',fields_resolved) order by items desc),'[]'::jsonb) value
    from (
      select case when status='blocked' then coalesce(nullif(failure_class,''),'runtime_blocked') when status='layer3_required' then 'layer3_required' when status='resolved_l2' then 'resolved_l2' else coalesce(nullif(outcome_code,''),status,'unknown') end reason,
             count(*)::bigint items,sum(coalesce(fields_targeted,0))::bigint fields_targeted,sum(coalesce(fields_resolved,0))::bigint fields_resolved
      from scoped_recent_items
      where coalesce(completed_at,updated_at,created_at)>=now()-interval '7 days'
      group by 1 order by items desc limit 30
    ) q
  ), providers as (
    select coalesce(jsonb_agg(jsonb_build_object('provider',provider_key,'attempts',attempts,'succeeded',succeeded,'failed',failed,'vendor_units',vendor_units,'cost_usd',cost_usd,'p50_ms',p50_ms,'p95_ms',p95_ms,'retries',retries) order by attempts desc),'[]'::jsonb) value
    from (
      select coalesce(ap.provider_key,'unknown') provider_key,count(*)::bigint attempts,
        count(*) filter(where pa.status in('completed','success','succeeded'))::bigint succeeded,
        count(*) filter(where pa.status in('failed','error','blocked'))::bigint failed,
        coalesce(sum(coalesce((nullif(pa.metrics->>'vendor_units',''))::numeric,0)),0)::numeric vendor_units,
        coalesce(sum(coalesce((nullif(pa.metrics->>'estimated_request_cost_usd',''))::numeric,0)),0)::numeric cost_usd,
        percentile_cont(.5) within group(order by extract(epoch from (pa.completed_at-pa.started_at))*1000) filter(where pa.completed_at is not null and pa.started_at is not null) p50_ms,
        percentile_cont(.95) within group(order by extract(epoch from (pa.completed_at-pa.started_at))*1000) filter(where pa.completed_at is not null and pa.started_at is not null) p95_ms,
        0::bigint retries
      from pipeline.layer2_provider_attempts pa left join pipeline.layer2_acquisition_providers ap on ap.id=pa.acquisition_provider_id
      where coalesce(pa.completed_at,pa.started_at,pa.created_at)>=now()-interval '7 days'
      group by ap.provider_key order by attempts desc limit 20
    ) q
  ), admissions as (
    select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'course_id',a.course_id,'field_key',a.field_key,'status',a.status,'reason_code',a.reason_code,'canonical_changed',a.canonical_changed,'search_admission_eligible',a.search_admission_eligible,'evidence_id',a.evidence_id,'decided_at',a.decided_at,'provider_name',p.display_name,'course_title',c.display_title) order by a.decided_at desc),'[]'::jsonb) value
    from (select * from pipeline.layer2_field_admissions order by decided_at desc limit v_limit) a join catalogue.courses c on c.id=a.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where v_country is null or trim(co.iso_alpha2)=v_country
  ), recent_items as (
    select coalesce(jsonb_agg(jsonb_build_object('run_item_id',r.id,'job_id',r.job_id,'course_id',c.id,'course_code',c.course_code,'provider_name',p.display_name,'country_code',trim(co.iso_alpha2),'status',r.status,'stop_reason',case when r.status='blocked' then coalesce(nullif(r.failure_class,''),'runtime_blocked') when r.status='layer3_required' then 'layer3_required' when r.status='resolved_l2' then 'resolved_l2' else coalesce(nullif(r.outcome_code,''),r.status,'unknown') end,'fields_targeted',r.fields_targeted,'fields_resolved',r.fields_resolved,'evidence_count',(select count(*) from pipeline.evidence_artifacts e where e.job_id=r.job_id),'source_record_id',null,'evidence_id',(select e.id from pipeline.evidence_artifacts e where e.job_id=r.job_id order by e.captured_at desc limit 1),'event_at',coalesce(r.completed_at,r.updated_at,r.created_at)) order by coalesce(r.completed_at,r.updated_at,r.created_at) desc),'[]'::jsonb) value
    from (select * from scoped_recent_items order by coalesce(completed_at,updated_at,created_at) desc nulls last limit v_limit) r
    join catalogue.courses c on c.id=r.entity_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
  )
  select jsonb_build_object('observed_at',now(),'country_code',v_country,'coverage',(select value from coverage_json),'work',(select value from work),'hourly',(select value from hourly),'blockers',(select value from blockers),'stop_reasons',(select value from reasons),'providers',(select value from providers),'admissions',(select value from admissions),'recent_items',(select value from recent_items),'authority_note','Acquisition, admission and Search/publication are measured separately. Metrics do not authorise mutation.','metrics_note','Current work, stop reasons and provider summaries are bounded from persisted Layer 2 base tables; hourly historical funnel remains the governed CF-245 operational ledger projection.','change_control_ref','CF-CHG-20260915-245') into v_result;
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION security.admin_provider_asset_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'ref', 'ranking', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_country text:=upper(nullif(btrim(p_args->>'country_code'),''));
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_state text:=nullif(btrim(p_args->>'state'),'');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  if p_operation='provider_asset_summary' then
    return (
      with university_scope as (
        select distinct p.id,p.canonical_name,p.display_name,p.stable_key,c.iso_alpha2 country_code
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2::text = any((select security.catalogue_country_codes_v1()))
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%') discovered,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_backed,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate,
          exists(select 1 from catalogue.provider_assets pa where pa.provider_id=u.id and pa.is_primary and pa.status='approved' and pa.asset_type in ('logo','logo_dark','logo_light')) approved_primary,
          exists(select 1 from pipeline.sources s where s.provider_id=u.id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad') hotcourses_matched
        from university_scope u
      )
      select jsonb_build_object(
        'scope_basis','Canonical university cohort (every country in the catalogue) defined by accepted ranking Provider mappings; Hotcourses is discovery/reconciliation only',
        'country_code',v_country,'expected',count(*),'discovered',count(*) filter(where discovered),
        'acquired',count(*) filter(where evidence_backed or approved_primary),'approved',count(*) filter(where approved_primary),
        'blocked',count(*) filter(where accepted_candidate and not approved_primary),'missing',count(*) filter(where not discovered),
        'needs_review',count(*) filter(where discovered and not accepted_candidate and not approved_primary),
        'hotcourses_matched',count(*) filter(where hotcourses_matched),
        'refresh_cadence','quarterly','authority','first_party_provider',
        'third_party_discovery_policy','Exact university-logo copies from Hotcourses may be promoted as operator-approved fallbacks; canonical ownership remains the Provider and Hotcourses provenance is retained'
      ) from base
    );
  elsif p_operation='provider_asset_coverage' then
    return (
      with university_scope as (
        select distinct p.id provider_id,p.stable_key,coalesce(p.display_name,p.canonical_name) provider_name,p.website,p.lifecycle_status,
          c.iso_alpha2 country_code,c.name country_name
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2::text = any((select security.catalogue_country_codes_v1()))
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='rejected') rejected_candidate_count,
          (select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') latest_candidate_at,
          (select s.url from pipeline.sources s where s.provider_id=u.provider_id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1) hotcourses_url,
          (select s.metadata->>'directory_id' from pipeline.sources s where s.provider_id=u.provider_id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1) hotcourses_id,
          pa.id primary_asset_id,pa.source_url primary_source_url,pa.evidence_id primary_evidence_id,pa.storage_path primary_storage_path,
          pa.mime_type primary_mime_type,pa.content_hash primary_content_hash,pa.verified_at primary_verified_at,
          case when pa.id is not null then 'approved'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') then 'needs_review'
            else 'missing' end coverage_state
        from university_scope u
        left join lateral (
          select x.* from catalogue.provider_assets x where x.provider_id=u.provider_id and x.is_primary and x.status='approved'
            and x.asset_type in ('logo','logo_dark','logo_light')
          order by x.verified_at desc nulls last,x.id limit 1
        ) pa on true
      ), filtered as (select * from base where v_state is null or coverage_state=v_state),
      page as (
        select * from filtered order by case coverage_state when 'blocked' then 1 when 'needs_review' then 2 when 'missing' then 3 else 4 end,
          lower(provider_name),provider_id limit v_limit offset v_offset
      )
      select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb))
    );
  elsif p_operation='provider_asset_context' then
    return (
      select jsonb_build_object(
        'provider_id',p.id,
        'state',case when pa.id is not null then 'approved'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') then 'needs_review'
          else 'missing' end,
        'primary_asset',case when pa.id is null then null else jsonb_build_object('id',pa.id,'source_url',pa.source_url,'evidence_id',pa.evidence_id,'storage_path',pa.storage_path,'mime_type',pa.mime_type,'content_hash',pa.content_hash,'verified_at',pa.verified_at) end,
        'candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'accepted_candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted'),
        'hotcourses_reference',(select jsonb_build_object('id',s.metadata->>'directory_id','url',s.url,'fallback_reuse_approved',coalesce((s.metadata->>'operator_fallback_reuse_approved')::boolean,false),'rights_owner_basis',s.metadata->>'rights_owner_basis') from pipeline.sources s where s.provider_id=p.id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1),
        'latest_candidate_at',(select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'authority','first_party_provider','refresh_cadence','quarterly')
      from catalogue.providers p
      left join lateral (
        select x.* from catalogue.provider_assets x where x.provider_id=p.id and x.is_primary and x.status='approved'
          and x.asset_type in ('logo','logo_dark','logo_light')
        order by x.verified_at desc nulls last,x.id limit 1
      ) pa on true
      where p.id=nullif(p_args->>'provider_id','')::uuid
    );
  end if;
  raise exception 'unsupported provider asset read operation: %',p_operation using errcode='22023';
end
$function$;

do $post$
declare v_expected jsonb := '{"security.admin_catalogue_filter_page(jsonb)": "244538bdc97f9e889de2f4fa8fdec716", "security.admin_course_page_fast_base(jsonb)": "99bbbc5cd444185935da9e96b173a80e", "security.admin_course_page_unfiltered_fast(jsonb)": "3b39481d15e5c35ab121bf435342fbf0", "security.data_quality_overview_cached(jsonb)": "340980cb10c6d64efeda8e6144450f9b", "security.admin_enrichment_operations_read(jsonb)": "f3bef6c828eb0df11c4c2d5b81a940cd", "security.admin_provider_asset_read(text,jsonb)": "415bda224af57032ddcdcec9bda32ab8"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.270 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
