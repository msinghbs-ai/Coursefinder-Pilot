-- CF-247 S2-Build read carrier (never merged; rolled-back dry runs only). Defines temporary helpers for the probe.
-- Replaces: nothing. Retires: nothing.
create or replace function pg_temp.j(q text) returns text language plpgsql as $f$
declare r text; begin execute 'select coalesce(json_agg(t)::text, ''[]'') from (' || q || ') t' into r; return r; end $f$;
create or replace function pg_temp.x(q text) returns text language plpgsql as $f$
declare r text; l text; begin r := ''; for l in execute 'explain (analyze, buffers, costs off, timing on) ' || q loop r := r || l || E'\n'; end loop; return r; end $f$;
create or replace function pg_temp.t(q text, n int default 3) returns text language plpgsql as $f$
declare t0 timestamptz; r text := ''; i int; d text; begin
  for i in 1..n loop t0 := clock_timestamp(); execute 'select length(coalesce((' || q || ')::text, ''''))' into d;
    r := r || round(extract(epoch from clock_timestamp() - t0) * 1000) || 'ms/' || d || 'c '; end loop; return r; end $f$;
do $a$ declare v uuid; begin
-- CF-247 s977 (session S2-Build, Platform Admin batch of 22 Nov 2026 22:01 AEDT, Part 1 and Part 2): REQ-105 closed for filtered and sorted
-- Courses lists, and the counselling filters behind the Counsellor and Viewer filter bar.
-- Measured live 23 Nov 2026 (rolled-back dry runs, signed in as a Platform Admin): Australia + New South Wales sorted by International fee took
-- 2.6 to 7.3 s; the same list by title 1.2 to 2.8 s; Australia alone by International fee 0.6 to 1.5 s. The state test ran once per course of
-- the country (an exists over campuses and subdivisions for each of about 30,000 courses), and the plan cached for the function after five
-- calls is a generic one that cannot use the filters' values.
-- 1. security.admin_course_page_fast_base (md5-guarded, replaced in place): the courses of the chosen state or region are read once, set-based,
--    with the same rule (a campus in the region, or the provider's own region for a course with no located campus); the function plans each
--    call with its own values (plan_cache_mode force_custom_plan). Same rows, order and totals as before (compared below on eight lists).
--    New arguments, applied in the bounded path only: fee_min and fee_max (the International fee column's fee), intake_month and intake_year,
--    english_test with english_score (courses asking that score or less). With a state chosen, the City column names that state's cities.
-- 2. security.admin_course_page_fast (md5-guarded): the new arguments take the bounded path.
-- 3. security.admin_catalogue_filter_page (md5-guarded): a new list, english_test (the tests active requirements name, from ref.english_tests).
-- 4. Index: each course's current international fee (the sort and the fee range read it by course id).
-- 5. Website API v3 (Decision 277: open to additions until its go-live is recorded; payload unchanged): public.website_v3_course_search_core
--    plans each call with its own values, as above (the generic plan took 3 s for a keyword search that takes 0.45 s planned with its values).
-- Consumer API untouched (G3 checked before and after; v2 functions not changed). Live on deploy. $0. G1: no new job. G2: no operational value.
-- Parity: live head 20261122230000 (s976) read 23 Nov 2026 05:40 AEDT; no open pull request carries a migration; this file is numbered above both.
-- Replaces: the per-course state test in security.admin_course_page_fast_base (rewritten in place).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(replace(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure), chr(13), '')) <> 'a0f64b1a4cfd4965ce24000466246d72'
     and position('s977' in pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure)) = 0 then
    raise exception 'guard: live security.admin_course_page_fast_base differs from the definition this change replaces';
  end if;
  if md5(replace(pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure), chr(13), '')) <> '0df468929bc1f30b769496a0d7be109c'
     and position('s977' in pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure)) = 0 then
    raise exception 'guard: live security.admin_course_page_fast differs from the definition this change replaces';
  end if;
  if md5(replace(pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure), chr(13), '')) <> '48eb54ebba0864615507586bebda0455'
     and position('s977' in pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure)) = 0 then
    raise exception 'guard: live security.admin_catalogue_filter_page differs from the definition this change replaces';
  end if;
  if md5(replace(pg_get_functiondef('public.website_v3_course_search_core(jsonb,integer,integer,text)'::regprocedure), chr(13), '')) <> '5635f8ff45f967ffe8e2b9737883f060'
     and position('force_custom_plan' in pg_get_functiondef('public.website_v3_course_search_core(jsonb,integer,integer,text)'::regprocedure)) = 0 then
    raise exception 'guard: live public.website_v3_course_search_core differs from the definition this change configures';
  end if;
end $g$;
create temp table s977_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s977_cron on commit drop as select count(*) n from cron.job where active;

-- the definition replaced, kept for this transaction only, for the parity check below
do $o$
declare v_def text := replace(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure), chr(13), '');
begin
  if position('s977' in v_def) > 0 then return; end if;
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION security.admin_course_page_fast_base(', 'CREATE OR REPLACE FUNCTION pg_temp.s977_old_base(');
end $o$;

-- Index (reads only; no column changes), built inside a short lock retry
do $i$
declare v_sql text; v_try int;
begin
  foreach v_sql in array array[
    'create index if not exists course_fees_intl_current_idx on catalogue.course_fees (course_id, fee_year desc nulls last, updated_at desc) include (amount, currency_code, basis) where fee_type = ''provider_current_tuition'' and audience = ''international'' and status = ''active''',
    'analyze catalogue.course_fees']
  loop
    for v_try in 1 .. 10 loop  -- fixed: lock retry count for a busy table
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute v_sql;
        exit;
      exception when lock_not_available then
        if v_try = 10 then raise; end if;
        perform pg_sleep(2);  -- fixed: pause between lock tries
      end;
    end loop;
  end loop;
  perform set_config('lock_timeout', '5s', true);  -- fixed: back to this change's lock wait
end $i$;

CREATE OR REPLACE FUNCTION security.admin_course_page_fast_base(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$;
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
  -- 23 Nov 2026 (S2-Build s977, Platform Admin batch Part 2): the counselling filters (international fee range, intake month and year,
  -- English test with the student's score); each is applied in the bounded path below only
  v_fee_min numeric:=nullif(p_args->>'fee_min','')::numeric;
  v_fee_max numeric:=nullif(p_args->>'fee_max','')::numeric;
  v_intake_month integer:=nullif(p_args->>'intake_month','')::integer;
  v_intake_year integer:=nullif(p_args->>'intake_year','')::integer;
  v_test text:=upper(nullif(trim(coalesce(p_args->>'english_test','')),''));
  v_score numeric:=nullif(p_args->>'english_score','')::numeric;
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
  -- 12 Nov 2026 (Platform Admin, Course catalogue): the Course description filter is applied in the bounded path below only
  -- 18 Nov 2026 (Platform Admin, Course catalogue): the Study load and Empty reason filters are applied in the bounded path below only
  if v_sort in ('fee','completeness') and nullif(p_args->>'description','') is null and nullif(p_args->>'study_load','') is null and nullif(p_args->>'empty_reason','') is null
     and v_fee_min is null and v_fee_max is null and v_intake_month is null and v_intake_year is null and v_test is null then
    return security.admin_course_page_search_state(public.ui_courses_decision_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,
      nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),
      v_has_fee,v_has_intake,v_has_english,v_has_scholarship,v_min_completeness,nullif(p_args->>'freshness',''),
      v_sort,v_dir,v_has_state,v_has_link,v_group
    ));
  end if;

  -- 23 Nov 2026 (S2-Build s977, REQ-105): the courses of the chosen state or region are read once, set-based (its campuses, or the
  -- provider's own region for a course with no located campus), and the list keeps those; before, each course of the country was
  -- tested on its own (3.6 to 5.0 s for Australia, New South Wales by International fee). Same rule, same rows.
  with sub_ids as materialized (
    select cc.course_id from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id
     where v_sub_id is not null and ca.subdivision_id=v_sub_id
    union
    select c2.id from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id
     where v_sub_id is not null and p2.subdivision_id=v_sub_id
       and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id where cc.course_id=c2.id and ca.subdivision_id is not null)
  ), base as (
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
      and (nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is null or c.id in (select s.course_id from sub_ids s))
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
      and (v_has_scholarship is null or coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=c.id), false)=v_has_scholarship)
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
      -- 12 Nov 2026 (Platform Admin, Course catalogue): Course description filter: held or not, or written by the description reader in the last day or week
      and (nullif(p_args->>'description','') is null
        or (p_args->>'description'='populated' and nullif(btrim(c.description),'') is not null)
        or (p_args->>'description'='missing' and nullif(btrim(c.description),'') is null)
        or (p_args->>'description' in ('updated_24h','updated_7d') and nullif(btrim(c.description),'') is not null and exists (
          -- the reading must be the text held now: a description edited by hand after the reading is not counted as written by the reader
          select 1 from pipeline.field_enrich_items e where e.course_id=c.id and e.field='description' and e.state='filled' and btrim(e.value->>'text')=btrim(c.description)
             and e.updated_at>=now()-case when p_args->>'description'='updated_24h' then interval '1 day' else interval '7 days' end)))  -- fixed: the filter's own windows, as the Freshness filter's
      -- 18 Nov 2026 (Platform Admin, Course catalogue): Study load filter (none: not held) and Empty reason filter (any: a reason is recorded; none: no reason)
      and (nullif(p_args->>'study_load','') is null
        or (p_args->>'study_load'='none' and c.study_load is null)
        or c.study_load=p_args->>'study_load')
      and (nullif(p_args->>'empty_reason','') is null
        or (p_args->>'empty_reason'='any' and c.empty_reason_code is not null)
        or (p_args->>'empty_reason'='none' and c.empty_reason_code is null)
        or c.empty_reason_code=p_args->>'empty_reason')
      -- 23 Nov 2026 (S2-Build s977): international fee range (the fee the International fee column shows), intake month and year,
      -- English test with the student's score (courses asking that score or less)
      and ((v_fee_min is null and v_fee_max is null) or exists(
        select 1 from (select cf.amount from catalogue.course_fees cf where cf.course_id=c.id and cf.fee_type='provider_current_tuition' and cf.audience='international'
                         and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) f
         where (v_fee_min is null or f.amount>=v_fee_min) and (v_fee_max is null or f.amount<=v_fee_max)))
      and ((v_intake_month is null and v_intake_year is null) or exists(
        select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'
           and (v_intake_year is null or coalesce(ci.intake_year, extract(year from ci.start_date)::int)=v_intake_year)
           and (v_intake_month is null or coalesce(extract(month from ci.start_date)::int, api.website_v2_label_month(ci.intake_label))=v_intake_month)))
      and (v_test is null or exists(
        select 1 from catalogue.course_english_requirements er join ref.english_tests et on et.id=er.english_test_id
         where er.course_id=c.id and coalesce(er.status,'active')='active' and et.code=v_test
           and (v_score is null or (er.overall_score is not null and er.overall_score<=v_score))))
      and (v_min_completeness is null or (
        (exists(select 1 from catalogue.course_registrations r where r.course_id=c.id))::int
        +(c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id))::int
        +(exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active'))::int
        +(c.description is not null and length(trim(c.description))>0)::int
      )*100.0/6.0 >= v_min_completeness)
  ), matched as materialized (
    select b.id,b.canonical_title,b.provider_name,b.field_of_study,b.updated_at,b.last_verified_at,b.provider_id from base b
  ), adm as materialized (
    -- CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31 §8): the Last data admitted and Adapter status sorts run set-based over the
    -- whole filtered set (one aggregate of the admission ledgers; one join of the adapter tables). Each is built only for its own sort.
    select a.course_id,max(a.at) at from security.course_admissions_v1() a where v_sort='admitted' group by a.course_id
  ), ads as materialized (
    select m.id course_id,security.course_adapter_rank_v1(security.course_adapter_state_from_v1(u.provider_id is not null,u.enabled,u.admit,
             p.leased_until>now(),p.status,p.read_status,r.before_read_status)) rank
    from matched m
    left join pipeline.uni_adapters u on u.provider_id=m.provider_id
    left join pipeline.coverage_course_pages p on p.course_id=m.id
    left join (select distinct on (x.course_id) x.course_id,x.before_read_status from pipeline.uni_adapter_results x
               where v_sort='adapter' order by x.course_id,x.at desc,x.id desc) r on r.course_id=m.id
    where v_sort='adapter'
  ), numbered as (
    -- CF-247 W34 (30 Oct 2026): the filters run once into the matching ids with their sort keys only; the total is their count and
    -- the page is the ordered ids; the page's rows are then read in full. Before, every matching course was carried with all its
    -- columns (the description too) through a window count and a full sort (1.0 to 1.6 s idle, 3.0 s under load).
    -- Same rows, same order, same fields, same total.
    select k.id,k.ord,(select count(*) from matched) total_count
    from unnest(array(select numbered.id from matched numbered left join adm on adm.course_id=numbered.id left join ads on ads.course_id=numbered.id order by
      -- 24 Oct 2026 (UI audit Phase 2): the International fee and City columns sort; one indexed lookup per filtered course
      case when v_sort='intl_fee' and v_dir='asc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) end asc nulls last,
      case when v_sort='intl_fee' and v_dir='desc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='provider_current_tuition' and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) end desc nulls last,
      -- 12 Nov 2026 (QA of #1081): with the Course description filter the fee and completeness sorts run here too
      case when v_sort='fee' and v_dir='asc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active' order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1) end asc nulls last,
      case when v_sort='fee' and v_dir='desc' then (select cf.amount from catalogue.course_fees cf where cf.course_id=numbered.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active' order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1) end desc nulls last,
      case when v_sort='completeness' then security.course_completeness_v1(numbered.id) end * case when v_dir='desc' then -1 else 1 end asc nulls last,
      case when v_sort='city' and v_dir='asc' then (select min(lower(ca.city)) from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id where cc.course_id=numbered.id and nullif(btrim(ca.city),'') is not null) end asc nulls last,
      case when v_sort='city' and v_dir='desc' then (select min(lower(ca.city)) from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id where cc.course_id=numbered.id and nullif(btrim(ca.city),'') is not null) end desc nulls last,
      case when v_sort='admitted' and v_dir='asc' then adm.at end asc nulls last,
      case when v_sort='admitted' and v_dir='desc' then adm.at end desc nulls last,
      case when v_sort='adapter' and v_dir='asc' then ads.rank end asc nulls last,
      case when v_sort='adapter' and v_dir='desc' then ads.rank end desc nulls last,
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
    limit v_limit offset v_offset)) with ordinality k(id,ord)
  ), paged as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,c.open_to_international,c.open_to_domestic,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study,
      n.total_count,n.ord
    from numbered n
    join catalogue.courses c on c.id=n.id
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      pg.open_to_international,pg.open_to_domestic,coalesce(ssc.identifier,pg.course_code) display_code,case when ssc.identifier is not null then 'studysearch' else 'own' end code_kind,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      coalesce(nullif(btrim(pg.canonical_delivery_mode),''),case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' end) delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,ifee.amount intl_fee_amount,ifee.currency_code::text intl_fee_currency,ifee.fee_year intl_fee_year,ifee.basis intl_fee_basis,gcity.city_names,
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
      pg.total_count,pg.ord
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code from catalogue.course_fees cf
      where cf.course_id=pg.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1
    ) fee on true
    -- 23 Oct 2026 (Platform Admin 12:52): the international fee a provider publishes, and the campus cities
    left join lateral (select cf.amount, cf.currency_code, cf.fee_year, cf.basis from catalogue.course_fees cf where cf.course_id=pg.id and cf.fee_type='provider_current_tuition'
      and cf.audience='international' and cf.status='active' order by cf.fee_year desc nulls last, cf.updated_at desc limit 1) ifee on true
    -- 23 Nov 2026 (S2-Build s977, Feedback-1): with a state or region chosen, the City column names that state's campus cities only
    left join lateral (select string_agg(distinct ca.city, ', ') city_names from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id
      where cc.course_id=pg.id and nullif(btrim(ca.city),'') is not null
        and (v_sub_id is null or ca.subdivision_id=v_sub_id or not exists(select 1 from catalogue.course_campuses c3 join catalogue.campuses k3 on k3.id=c3.campus_id
                                                                         where c3.course_id=pg.id and k3.subdivision_id=v_sub_id))) gcity on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (select coalesce((select sd.has_scholarship from search.course_documents sd where sd.course_id=pg.id), false) has_scholarship) sch
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
    'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'-'ord' order by e.ord),'[]'::jsonb),
    'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
    'execution_profile','paged_enrichment_v3'
  ) into v_result from enriched e;
  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'public', 'auth'
AS $function$;
declare
  v_q text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_provider_id uuid;
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  v_simple :=
    v_q is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'level_code','') is null
    and nullif(p_args->>'field_code','') is null
    and nullif(p_args->>'delivery_mode','') is null
    and coalesce(nullif(p_args->>'lifecycle_status',''),'active')='active'
    and nullif(p_args->>'publication_status','') is null
    and nullif(p_args->>'has_fee','') is null
    and nullif(p_args->>'has_intake','') is null
    and nullif(p_args->>'has_english','') is null
    and nullif(p_args->>'has_scholarship','') is null
    and nullif(p_args->>'has_state','') is null
    and nullif(p_args->>'has_link','') is null
    and nullif(p_args->>'min_completeness','') is null
    and nullif(p_args->>'freshness','') is null
    and nullif(p_args->>'university_group','') is null
    and nullif(p_args->>'applicant','') is null
    and nullif(p_args->>'description','') is null
    and nullif(p_args->>'study_load','') is null
    and nullif(p_args->>'empty_reason','') is null
    -- 23 Nov 2026 (S2-Build s977): the counselling filters take the bounded path
    and nullif(p_args->>'fee_min','') is null
    and nullif(p_args->>'fee_max','') is null
    and nullif(p_args->>'intake_month','') is null
    and nullif(p_args->>'intake_year','') is null
    and nullif(p_args->>'english_test','') is null
    and v_sort='course' and v_dir='asc';

  if v_simple then
    -- CF-247 Course Catalogue columns (mandate 5 Nov 2026 17:31): every page carries the extra columns, read set-based over its ids
    return security.course_list_with_extras_v1(security.admin_course_page_unfiltered_fast(p_args));
  end if;

  if v_q is not null and v_q ~* '^course:' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where c.stable_key=v_q limit 1;
  elsif v_q is not null and v_q ~ '^[0-9]{6}[A-Za-z]$' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where upper(c.course_code)=upper(v_q) limit 1;
  end if;

  if v_provider_id is not null and nullif(p_args->>'provider_id','') is null then
    return security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text)));
  end if;

  return security.course_list_with_extras_v1(security.admin_course_page_fast_base(p_args));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$;
declare
  v_rank integer:=0;
  v_kind text:=lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''));
  v_query text:=lower(nullif(trim(coalesce(p_args->>'query','')),''));
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text:=upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),case when lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''))='level' then 100 else 10 end);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_sub_id uuid;
  v_empty text;
  v_pids uuid[];
  v_cids uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_subdivision is not null then select sd.id into v_sub_id from ref.subdivisions sd where sd.code=v_subdivision; end if;

  -- 22 Nov 2026 (REQ-105, s972): the filter lists read the providers of the country and the courses of the region once,
  -- then each list is a semi-join over its own small reference table. Same values, labels, order and totals as before.
  if v_country is not null and v_kind not in ('university_group','country') then
    select coalesce(array_agg(p.id),'{}'::uuid[]) into v_pids from catalogue.providers p join ref.countries co on co.id=p.country_id where co.iso_alpha2::text=v_country;
  end if;
  if v_subdivision is not null and v_kind in ('provider','level','field','delivery') then
    select coalesce(array_agg(distinct x.id),'{}'::uuid[]) into v_cids from (
      select cc.course_id id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
      where cp.subdivision_id in (select sd.id from ref.subdivisions sd where sd.code=v_subdivision)
      union all
      select c.id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
      where p.subdivision_id=v_sub_id and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                                                     where cc.course_id=c.id and cp.subdivision_id is not null)) x;
  end if;

  if v_kind='country' then
    with q as (
      select distinct co.iso_alpha2::text value,co.name label,co.iso_alpha2::text meta
      from ref.countries co
      where co.id in (select p.country_id from catalogue.providers p where exists(select 1 from catalogue.courses c where c.provider_id=p.id))
        and (v_query is null or lower(co.name||' '||co.iso_alpha2::text) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='subdivision' then
    with q as (
      select distinct s.code value,s.name label,s.code meta
      from ref.subdivisions s
      where (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
        and (exists(select 1 from catalogue.campuses cp join catalogue.course_campuses cc on cc.campus_id=cp.id join catalogue.courses c on c.id=cc.course_id
                    where cp.subdivision_id=s.id and (v_pids is null or c.provider_id=any(v_pids)))
          or exists(select 1 from catalogue.providers p
                    where p.subdivision_id=s.id and (v_pids is null or p.id=any(v_pids))
                      and exists(select 1 from catalogue.courses c where c.provider_id=p.id
                                   and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                                                  where cc.course_id=c.id and cp.subdivision_id is not null))))
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='provider' then
    with q as (
      select distinct p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta
      from catalogue.providers p
      where (v_pids is null or p.id=any(v_pids))
        and exists(select 1 from catalogue.courses c where c.provider_id=p.id and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='level' then
    with q as (
      select distinct sl.code value,sl.name label,coalesce(g.group_name,'Other') meta,sl.sort_order,coalesce(g.group_order,90) group_order
      from ref.study_levels sl
      left join ref.study_level_groups g on g.level_code=sl.code
      where exists(select 1 from catalogue.courses c where c.study_level_id=sl.id
                     and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(sl.name||' '||sl.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select value,label,meta,group_order,sort_order from q order by group_order,sort_order,lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'group',meta,'group_order',group_order) order by group_order,sort_order,lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='field' then
    with q as (
      select distinct fos.code value,fos.name label,fos.code meta
      from ref.fields_of_study fos
      where exists(select 1 from catalogue.courses c where c.primary_field_id=fos.id
                     and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(fos.name||' '||fos.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='delivery' then
    -- the few delivery modes are read from their indexes (one probe per mode), then kept when a course in scope has the mode
    with recursive t(m) as (
      (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'') is not null order by 1 limit 1)
      union all
      select (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'')>t.m order by 1 limit 1) from t where t.m is not null
    ), u(m) as (
      (select cc.delivery_mode from catalogue.course_campuses cc where cc.delivery_mode is not null order by 1 limit 1)
      union all
      select (select cc.delivery_mode from catalogue.course_campuses cc where cc.delivery_mode>u.m order by 1 limit 1) from u where u.m is not null
    ), q as (
      select m value,upper(left(replace(m,'_',' '),1))||substr(replace(m,'_',' '),2) label,null::text meta
      from (
        select t.m from t where t.m is not null
          and exists(select 1 from catalogue.courses c where nullif(btrim(c.delivery_mode),'')=t.m
                       and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        union
        select u.m from u where u.m is not null
          and exists(select 1 from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id
                     where cc.delivery_mode=u.m and nullif(btrim(c.delivery_mode),'') is null
                       and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
      ) x
      where m is not null and btrim(m)<>''
        and (v_query is null or lower(replace(m,'_',' ')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  elsif v_kind='english_test' then
    -- 23 Nov 2026 (S2-Build s977): the English tests that active course requirements name (ref.english_tests), for the counselling filter
    with q as (
      select t.code value, coalesce(nullif(btrim(t.name),''),t.code) label
      from ref.english_tests t
      where exists(select 1 from catalogue.course_english_requirements er where er.english_test_id=t.id and coalesce(er.status,'active')='active')
        and (v_query is null or lower(t.code||' '||coalesce(t.name,'')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label) order by lower(label),value) from page),'[]'::jsonb),
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

-- Website API v3 search plans each call with its own values (payload unchanged; Decision 277)
alter function public.website_v3_course_search_core(jsonb, integer, integer, text) set plan_cache_mode = 'force_custom_plan';

-- Parity: the replaced and the new list answer the same rows, in the same order, with the same total (eight lists, signed in as a
-- Platform Admin); lists without a state also give the same fields. The City column's state-only cities are the one intended difference.
do $p$
declare v_admin uuid; a jsonb; b jsonb; v_args jsonb; v_full boolean;
begin
  if to_regprocedure('pg_temp.s977_old_base(jsonb)') is null then return; end if;
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  for v_args, v_full in select x.a, x.f from (values
      ('{"country_code":"AU","subdivision_code":"AU-NSW","lifecycle_status":"active","sort":"intl_fee","direction":"asc","limit":50}'::jsonb, false),
      ('{"country_code":"AU","subdivision_code":"AU-NSW","lifecycle_status":"active","sort":"intl_fee","direction":"desc","limit":50,"offset":50}'::jsonb, false),
      ('{"country_code":"AU","subdivision_code":"AU-VIC","lifecycle_status":"active","limit":50}'::jsonb, false),
      ('{"country_code":"AU","subdivision_code":"AU-TAS","sort":"field","direction":"asc","limit":50}'::jsonb, false),
      ('{"country_code":"CA","subdivision_code":"CA-ON","lifecycle_status":"active","limit":50}'::jsonb, false),
      ('{"country_code":"AU","lifecycle_status":"active","sort":"provider","direction":"desc","has_fee":true,"limit":50}'::jsonb, true),
      ('{"country_code":"NZ","lifecycle_status":"active","sort":"intl_fee","direction":"desc","limit":50}'::jsonb, true),
      ('{"query":"nursing","lifecycle_status":"active","limit":50}'::jsonb, true)) x(a, f)
  loop
    a := pg_temp.s977_old_base(v_args);
    b := security.admin_course_page_fast_base(v_args);
    if (a->'total') is distinct from (b->'total') or jsonb_path_query_array(a, '$.items[*].id') is distinct from jsonb_path_query_array(b, '$.items[*].id') then
      raise exception 'parity: % answers different rows (total % / %)', v_args, a->'total', b->'total';
    end if;
    if v_full and (a->'items') is distinct from (b->'items') then raise exception 'parity: % answers different fields', v_args; end if;
  end loop;
  perform set_config('request.jwt.claims', '', true);
end $p$;

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if not exists (select 1 from pg_indexes where schemaname = 'catalogue' and indexname = 'course_fees_intl_current_idx') then raise exception 'post-check: the index is missing'; end if;
  if position('sub_ids' in pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the state path is missing'; end if;
  if position('english_test' in pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the bounded path does not see the new filters'; end if;
  if position('english_test' in pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the English test list is missing'; end if;
  if (select count(*) from cron.job where active) <> (select n from s977_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s977_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
do $a$ declare v uuid; begin
  select ur.user_id into v from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v::text, 'role', 'authenticated')::text, true);
end $a$;
