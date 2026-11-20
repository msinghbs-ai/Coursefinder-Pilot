CREATE OR REPLACE FUNCTION security.admin_providers_page_v3(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'provider'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_query text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_country text:=nullif(trim(coalesce(p_args->>'country_code','')),'');
  v_subdivision text:=nullif(trim(coalesce(p_args->>'subdivision_code','')),'');
  v_lifecycle text:=nullif(trim(coalesce(p_args->>'lifecycle_status','')),'');
  v_publication text:=nullif(trim(coalesce(p_args->>'publication_status','')),'');
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
  v_adapter text:=nullif(trim(coalesce(p_args->>'adapter','')),'');
  v_desc text:=nullif(lower(trim(coalesce(p_args->>'description',''))),'');
  v_adm text:=nullif(lower(trim(coalesce(p_args->>'admission',''))),'');
  v_tier text:=nullif(lower(trim(coalesce(p_args->>'source_tier',''))),'');
  v_web text:=nullif(lower(trim(coalesce(p_args->>'website',''))),'');
  v_zoho text:=nullif(lower(trim(coalesce(p_args->>'zoho',''))),'');
  v_type text:=nullif(trim(coalesce(p_args->>'provider_type','')),'');
  v_quality text:=nullif(lower(trim(coalesce(p_args->>'quality',''))),'');
  v_qset text[];
  v_missing text[] := (select array_agg(distinct btrim(x)) from unnest(string_to_array(nullif(btrim(coalesce(p_args->>'missing', '')), ''), ',')) x where btrim(x) <> '');
  v_need_facts boolean;
  v_scan_feeds boolean;
  v_page_feeds boolean;
  v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_missing is not null and not (v_missing <@ array['description','website','city','state_region','provider_type','phone','email','address','established_year']) then raise exception 'unsupported missing-field filter: %', array_to_string(v_missing, ',') using errcode = '22023'; end if; -- fixed: the nine provider fields security.provider_missing_fields_v1 reports
  if v_desc is not null and v_desc not in ('filled','missing') then raise exception 'unsupported description filter: %',v_desc using errcode='22023'; end if;
  if v_adm is not null and v_adm not in ('pending','held','declined','admitted') then raise exception 'unsupported admission filter: %',v_adm using errcode='22023'; end if;
  if v_tier is not null and v_tier not in ('stored','direct','firecrawl','registry_factual','unknown') then raise exception 'unsupported source tier filter: %',v_tier using errcode='22023'; end if;
  if v_web is not null and v_web not in ('matched','pending','missing','not_applicable') then raise exception 'unsupported website filter: %',v_web using errcode='22023'; end if;
  if v_zoho is not null and v_zoho not in ('matched','pending','missing','not_applicable') then raise exception 'unsupported zoho filter: %',v_zoho using errcode='22023'; end if;
  if v_type is not null and v_type<>'unclassified' and not exists (select 1 from ref.provider_types pt where pt.code=v_type) then raise exception 'unsupported provider type filter: %',v_type using errcode='22023'; end if;
  -- Description quality level (Fill fields, Platform Admin directive 9-10 Nov 2026): the four groups the screen offers (basic, enriched, missing, held) and each single class
  if v_quality is not null then
    v_qset:=case v_quality
      when 'basic' then array['basic_registry'] when 'enriched' then array['enriched_admitted','consumer_pending','verified_published'] when 'missing' then array['missing'] when 'held' then array['held']
      when 'queued' then array['queued'] when 'processing' then array['processing'] when 'waiting_decision' then array['waiting_decision'] when 'basic_registry' then array['basic_registry']
      when 'enriched_admitted' then array['enriched_admitted'] when 'consumer_pending' then array['consumer_pending'] when 'verified_published' then array['verified_published'] when 'unrecorded' then array['unrecorded'] end;
    if v_qset is null then raise exception 'unsupported quality filter: %',v_quality using errcode='22023'; end if;
  end if;
  -- the description facts are worked out for every provider only when a filter or a sort needs them
  -- Description (filled, missing) and the Description sort read the provider's own description column, so they need no facts. The pipeline facts are worked out
  -- only for a filter or sort that needs them, and only for the providers that already pass the filters on the provider's own columns.
  v_need_facts:=coalesce(v_adm,v_tier,v_web,v_zoho,v_quality) is not null
    or v_sort in ('admission','source','desc_admitted','reader','last_read','next_retry','layer4','canonical','website','zoho','mismatch','quality');

  -- The two feed candidate scans read every provider, so they run only when a Website or Zoho filter or sort needs them across the whole set, or when the
  -- screen shows a feed column (it then sends feeds=true) for the rows of the page. Otherwise those three fields come back null.
  -- the quality level of an enriched provider depends on the two feeds, so a quality sort, or a filter on a class that includes the enriched ones, scans them too
  v_scan_feeds:=coalesce(v_web,v_zoho) is not null or v_sort in ('website','zoho','mismatch','quality')
    or coalesce(v_quality in ('enriched','enriched_admitted','consumer_pending','verified_published'),false);
  v_page_feeds:=v_scan_feeds or lower(coalesce(p_args->>'feeds',''))='true';

  return (
    -- Same design as v2 (CF-247 W34): the page is chosen first on the light columns; the per-provider counts, the adapter status, the evidence count and
    -- the new columns are worked out for the rows of the page only. The adapter status is worked out for every matching provider only when the Adapter
    -- filter or sort needs it, the course count only for the Courses sort, the registration, scholarship and coverage values only for their own sort.
    with cand as (
      -- the providers that pass the filters on the provider's own columns (query, country, state, lifecycle, publication, group, type, Description)
      select p.id
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        left join ref.subdivisions ps on ps.id=p.subdivision_id
       where
        (
          v_query is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||v_query||'%'
          or coalesce(p.stable_key,'') ilike '%'||v_query||'%'
          or coalesce(p.primary_city,'') ilike '%'||v_query||'%'
          or coalesce(c.iso_alpha2::text,'') ilike '%'||v_query||'%'
          or coalesce(c.name,'') ilike '%'||v_query||'%'
          or coalesce(c.default_currency_code::text,'') ilike '%'||v_query||'%'
          or coalesce(ps.code,'') ilike '%'||v_query||'%'
          or coalesce(ps.name,'') ilike '%'||v_query||'%'
        )
        and (v_country is null or c.iso_alpha2::text=upper(v_country))
        and (v_subdivision is null or ps.code=upper(v_subdivision))
        and (v_lifecycle is null or p.lifecycle_status=v_lifecycle)
        and (v_publication is null or p.publication_status=v_publication)
        and (v_group is null or p.id in (select security.university_group_provider_ids(v_group)))
        and (v_type is null or (v_type='unclassified' and p.provider_type_id is null) or p.provider_type_id=(select pt.id from ref.provider_types pt where pt.code=v_type))
        and (v_desc is null or (v_desc='filled')=(nullif(btrim(p.description),'') is not null))
        and (v_missing is null or security.provider_missing_fields_v1(p) @> v_missing)
    ), facts as materialized (
      select * from security.provider_catalogue_facts_v1(array(select x.id from cand x), v_scan_feeds) where v_need_facts
    ), base as (
      select
        p.id,p.display_name,p.canonical_name,c.iso_alpha2::text country_code,c.default_currency_code::text currency_code,
        ps.name subdivision_name,p.primary_city city,p.last_verified_at,p.provider_type_id,p.lifecycle_status,p.publication_status,p.updated_at,
        case when v_adapter is not null or v_sort='adapter' then security.provider_adapter_status_v1(p.id) end adapter_status,
        case when v_sort='courses' then (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) end course_count,
        case when v_sort='scholarships' then (select count(*)::bigint from scholarship.scholarships sc where sc.provider_id=p.id) end scholarship_count,
        case when v_sort='registration' then (select lower(pr.registration_scheme||' '||pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id=p.id order by pr.checked_at desc nulls last,pr.id limit 1) end registration_key,
        case when v_sort='coverage' then (select ac.disposition from pipeline.aer_provider_coverage ac where ac.provider_id=p.id) end coverage_key,
        (nullif(btrim(p.description),'') is not null) description_filled,f.admission_state,f.source_tier,f.admitted_at,f.reader_state,f.last_read_ok_at,f.next_retry_at,f.l4_status,f.canonical_status,f.website_state,f.zoho_state,f.mismatch,
        -- the quality level and the number of missing provider fields, only where a filter or sort needs them across the whole set
        case when v_need_facts then security.provider_description_quality_class_v1(f.description_filled,f.admission_state,f.source_tier,f.reader_state,f.l4_status,f.website_state,f.zoho_state,v_scan_feeds) end quality_class,
        case when v_sort='missing_fields' then cardinality(security.provider_missing_fields_v1(p)) end missing_count
      from cand x
      join catalogue.providers p on p.id=x.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      left join facts f on f.provider_id=p.id
      where
        (v_adm is null or f.admission_state=v_adm)
        and (v_tier is null or f.source_tier=v_tier)
        and (v_web is null or f.website_state=v_web)
        and (v_zoho is null or f.zoho_state=v_zoho)
    ), filtered as (
      select * from base
       where v_adapter is null
          or (v_adapter = 'any' and adapter_status not in ('none', 'no_courses'))
          or adapter_status = v_adapter
    ), qfiltered as (
      select * from filtered where v_quality is null or quality_class = any(v_qset)
    ), numbered as (
      select f.id,count(*) over()::bigint total_count,row_number() over (order by
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(f.display_name,f.canonical_name)) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(f.display_name,f.canonical_name)) end desc,
        case when v_sort='country' and v_dir='asc' then f.country_code end asc,
        case when v_sort='country' and v_dir='desc' then f.country_code end desc,
        case when v_sort='currency' and v_dir='asc' then f.currency_code end asc,
        case when v_sort='currency' and v_dir='desc' then f.currency_code end desc,
        case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(f.subdivision_name,'')) end asc,
        case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(f.subdivision_name,'')) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(f.city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(f.city,'')) end desc,
        case when v_sort='type' and v_dir='asc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'~') end asc,
        case when v_sort='type' and v_dir='desc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'') end desc,
        case when v_sort='courses' and v_dir='asc' then f.course_count end asc,
        case when v_sort='courses' and v_dir='desc' then f.course_count end desc,
        case when v_sort='adapter' and v_dir='asc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end asc,
        case when v_sort='adapter' and v_dir='desc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end desc,
        case when v_sort='verified' and v_dir='asc' then f.last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then f.last_verified_at end desc nulls last,
        -- the new sorts. Unknown (no value held) is last in both directions, as on the Course catalogue's time sorts.
        case when v_sort='registration' and v_dir='asc' then f.registration_key end asc nulls last,
        case when v_sort='registration' and v_dir='desc' then f.registration_key end desc nulls last,
        case when v_sort='scholarships' and v_dir='asc' then f.scholarship_count end asc,
        case when v_sort='scholarships' and v_dir='desc' then f.scholarship_count end desc,
        case when v_sort='coverage' and v_dir='asc' then f.coverage_key end asc nulls last,
        case when v_sort='coverage' and v_dir='desc' then f.coverage_key end desc nulls last,
        case when v_sort='lifecycle' and v_dir='asc' then f.lifecycle_status end asc,
        case when v_sort='lifecycle' and v_dir='desc' then f.lifecycle_status end desc,
        case when v_sort='publication' and v_dir='asc' then f.publication_status end asc,
        case when v_sort='publication' and v_dir='desc' then f.publication_status end desc,
        case when v_sort='modified' and v_dir='asc' then f.updated_at end asc nulls last,
        case when v_sort='modified' and v_dir='desc' then f.updated_at end desc nulls last,
        case when v_sort='description' and v_dir='asc' then f.description_filled::int end asc,
        case when v_sort='description' and v_dir='desc' then f.description_filled::int end desc,
        case when v_sort='admission' and v_dir='asc' then f.admission_state end asc nulls last,
        case when v_sort='admission' and v_dir='desc' then f.admission_state end desc nulls last,
        case when v_sort='source' and v_dir='asc' then f.source_tier end asc nulls last,
        case when v_sort='source' and v_dir='desc' then f.source_tier end desc nulls last,
        case when v_sort='desc_admitted' and v_dir='asc' then f.admitted_at end asc nulls last,
        case when v_sort='desc_admitted' and v_dir='desc' then f.admitted_at end desc nulls last,
        case when v_sort='reader' and v_dir='asc' then f.reader_state end asc nulls last,
        case when v_sort='reader' and v_dir='desc' then f.reader_state end desc nulls last,
        case when v_sort='last_read' and v_dir='asc' then f.last_read_ok_at end asc nulls last,
        case when v_sort='last_read' and v_dir='desc' then f.last_read_ok_at end desc nulls last,
        case when v_sort='next_retry' and v_dir='asc' then f.next_retry_at end asc nulls last,
        case when v_sort='next_retry' and v_dir='desc' then f.next_retry_at end desc nulls last,
        case when v_sort='layer4' and v_dir='asc' then f.l4_status end asc nulls last,
        case when v_sort='layer4' and v_dir='desc' then f.l4_status end desc nulls last,
        case when v_sort='canonical' and v_dir='asc' then f.canonical_status end asc nulls last,
        case when v_sort='canonical' and v_dir='desc' then f.canonical_status end desc nulls last,
        case when v_sort='website' and v_dir='asc' then f.website_state end asc nulls last,
        case when v_sort='website' and v_dir='desc' then f.website_state end desc nulls last,
        case when v_sort='zoho' and v_dir='asc' then f.zoho_state end asc nulls last,
        case when v_sort='zoho' and v_dir='desc' then f.zoho_state end desc nulls last,
        case when v_sort='mismatch' and v_dir='asc' then f.mismatch end asc nulls last,
        case when v_sort='mismatch' and v_dir='desc' then f.mismatch end desc nulls last,
        -- Description quality level: the order of the pipeline, from Missing to Verified published (a level the page could not work out is last)
        case when v_sort='quality' and v_dir='asc' then array_position(array['missing','queued','processing','waiting_decision','held','basic_registry','unrecorded','enriched_admitted','consumer_pending','verified_published'], f.quality_class) end asc nulls last,
        case when v_sort='quality' and v_dir='desc' then array_position(array['missing','queued','processing','waiting_decision','held','basic_registry','unrecorded','enriched_admitted','consumer_pending','verified_published'], f.quality_class) end desc nulls last,
        case when v_sort='missing_fields' and v_dir='asc' then f.missing_count end asc,
        case when v_sort='missing_fields' and v_dir='desc' then f.missing_count end desc,
        lower(coalesce(f.display_name,f.canonical_name)),f.id) ord
      from qfiltered f
    ), keys as (
      select n.id,n.total_count,n.ord from numbered n where n.ord>v_offset and n.ord<=v_offset+v_limit
    ), pfacts as (
      -- the page's rows only: array(...) is an empty array, never null, when the page is empty (null would mean every provider)
      select * from security.provider_catalogue_facts_v1(array(select k.id from keys k), v_page_feeds)
    ), reg as (
      select distinct on (pr.provider_id) pr.provider_id,jsonb_build_object('scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status,'checked_at',pr.checked_at) j
        from catalogue.provider_registrations pr where pr.provider_id in (select k.id from keys k)
       order by pr.provider_id,pr.checked_at desc nulls last,pr.id
    ), sch as (
      select s.provider_id,jsonb_build_object('total',count(*),'published',count(*) filter (where s.publication_status='published' and s.lifecycle_status='active')) j
        from scholarship.scholarships s where s.provider_id in (select k.id from keys k) group by s.provider_id
    ), cov as (
      select ac.provider_id,jsonb_build_object('disposition',ac.disposition,'discovery',ac.discovery_state,'extraction',ac.extraction_state,'admission',ac.admission_state,
               'matrix_active',ac.matrix_active,'course_requirements_active',ac.course_req_active,'as_at',ac.updated_at) j
        from pipeline.aer_provider_coverage ac where ac.provider_id in (select k.id from keys k)
    ), page as (
      select
        p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,
        p.primary_city city,p.website,p.lifecycle_status,p.publication_status,
        p.last_verified_at,p.created_at,p.updated_at,
        (select pt.code from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_code,
        (select pt.name from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_name,
        p.provider_type_basis,
        exists (select 1 from pipeline.manual_locks ml where ml.entity='provider' and ml.entity_id=p.id and ml.field='provider_type_id') provider_type_locked,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        security.provider_adapter_status_v1(p.id) adapter_status,
        (select count(distinct x.evidence_id)::bigint
           from (
             select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
             union all
             select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
             union all
             select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
           ) x) evidence_count,
        p.description description_text,
        security.provider_missing_fields_v1(p) missing_fields,
        k.ord
      from keys k
      join catalogue.providers p on p.id=k.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
    )
    select jsonb_build_object(
      'items',coalesce((select jsonb_agg((to_jsonb(o)-'ord'-'description_text'-'missing_fields')||jsonb_build_object(
                'university_groups',security.provider_university_groups(o.id),
                'registration',(select r.j from reg r where r.provider_id=o.id),
                'scholarships',coalesce((select s.j from sch s where s.provider_id=o.id),jsonb_build_object('total',0,'published',0)),
                'entry_coverage',(select cv.j from cov cv where cv.provider_id=o.id),
                'pdesc',coalesce((select (to_jsonb(pf)-'provider_id')||jsonb_build_object('quality',security.provider_description_quality_class_v1(pf.description_filled,pf.admission_state,pf.source_tier,pf.reader_state,pf.l4_status,pf.website_state,pf.zoho_state,v_page_feeds),
                   'website_publication',security.provider_description_publication_v1(pf.website_state),'zoho_publication',security.provider_description_publication_v1(pf.zoho_state)) from pfacts pf where pf.provider_id=o.id),'{}'::jsonb)
                   ||jsonb_build_object('text',o.description_text,'missing_fields',to_jsonb(o.missing_fields))) order by o.ord) from page o),'[]'::jsonb),
      'total',coalesce((select max(total_count) from keys),0),
      'limit',v_limit,
      'offset',v_offset,
      'sort',v_sort,
      'direction',v_dir,
      'columns_profile','provider_columns_v1'
    )
  );
end
$function$
