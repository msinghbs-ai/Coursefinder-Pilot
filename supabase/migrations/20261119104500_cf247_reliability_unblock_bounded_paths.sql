-- CF-247 s720: reliability and throughput unblock (S2-Build; Platform Admin 19 Nov 2026 08:17, "Urgent Reliability & Throughput Unblock":
-- IQ-00609, IQ-00594/IQ-00588, IQ-00606, IQ-00348 and the stalled planner slots).
--
-- What was read live (19 Nov 2026 08:20-08:45 AEDT):
--   * IQ-00609: rollup-scheduler failed at 06:55 on the job's 120 s statement time-out inside security.course_coverage_build_v1 (target
--     course-coverage-build, hourly, 65 s average and up to 98 s, deferred 43 of 53 ticks in 12 h). It truncates and rebuilds
--     pipeline.course_attribute_coverage for all 36,031 active courses every run; security.aer_covered_courses_v1() alone takes 4.8 s.
--   * IQ-00594/IQ-00588: admission-rule runners B and C time out in the coverage-admit rules: security.coverage_admission_apply_v1 takes
--     security.consumer_api_snapshot_v1() before and after each batch (13 frozen consumer API reads at 20-25 rows; recorded as evidence in
--     pipeline.consumer_api_baselines, Decision 163, never a gate), and waits on the search-document writer lock
--     (pg_advisory_xact_lock, 08:05 and 08:15) while the full refresh holds it. coverage-admit ran 117 s of its 119 s budget.
--   * IQ-00606: svc_page_text_next_v1 fails with "ON CONFLICT DO UPDATE command cannot affect row a second time": two courses can share one
--     stored page, so one call claims the same page twice.
--   * IQ-00348: svc_evidence_link_index_next_v1 sorts every eligible artifact of every ranked provider before taking 60 (9.5 s).
--   * Planner: 40 of 40 automatic enrichment plans are open (plans.auto_open_max), so the planner has created nothing since 04:41; 34 have had no
--     job movement for 2 h (their jobs done), 35 were created more than 6 h ago.
-- What it changes (CREATE OR REPLACE of existing functions, md5-guarded; settings rows; one rollup target's schedule; no new table or function;
-- the frozen consumer API is only read, never changed; G3 75/48):
--   1. security.course_coverage_build_v1 is provider-chunked: each run rebuilds the providers whose coverage rows are oldest, up to
--      batch.course_coverage_courses courses (default 1,500); every per-course scan, the AER covered set included, is restricted to the chunk;
--      country tiers still come from every provider. The whole table (36,031 courses) is refreshed about every 24 runs (2 hours); course-coverage-build runs every 5 minutes.
--      The chunk's statistics are taken before its reads (a temporary table has none), the Enrich state is read course by course (index) and the
--      open absences by a join (measured on 2,900 courses: 4.8 s and 0.6 s became 0.5 s and 0.2 s); the chunk order walks the provider index
--      instead of grouping every coverage row (1.1 s), and the chunk's tables have statistics before the write.
--      The daily counts (course_coverage_daily, course_coverage_daily_by_country) move by each run's change instead of a count of the whole
--      table (3.9 s measured); the first run of a day starts from the latest earlier day's counts. Rows of providers with no active course left
--      are removed by provider, not by a scan of the whole table.
--   2. security.consumer_api_snapshot_v1 reads admit.consumer_snapshot_page_size rows (default 5), cheap reads first and the two free-text
--      searches (about 7 s each, measured) last, and starts no read after admit.consumer_snapshot_budget_ms (default 6,000 ms), marking the
--      cases it skipped. The same frozen reads, smaller pages; about 6-8 s a snapshot instead of about 25 s.
--   3. security.coverage_admission_apply_v1 never waits for the search-document writer: when it is busy the batch's courses go to
--      search.refresh_requests (processed by the search refresh job), as security.intake_dates_apply_v1 already does.
--   4. svc_page_text_next_v1 claims each stored page once (the items still list every course that shares it).
--   5. svc_evidence_link_index_next_v1 walks ranked providers in order and stops at the limit (keyset; 3.9 s measured, was 9.5 s).
--   6. security.enrich_plan_auto_v1 first releases automatic plans with no job movement for plans.auto_stall_hours (default 2) or whose held
--      steps all wait on budget windows that have ended (state cancelled, outcome released_stalled, detail kept), then counts its room.
-- Nothing is dropped. Replaces: the full rebuild of course_attribute_coverage, the blocking writer-lock wait in the coverage admission, the
-- 20-25-row snapshot reads and the global sort of the evidence index. Retires: nothing.

-- settings (G2)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'batch.course_coverage_courses', 'Coverage build: courses per run', 'Each run rebuilds the providers whose coverage rows are oldest, up to this many active courses.',
   'number', to_jsonb(1500), 200, 40000, 'courses', 101, 'Job sizes', 'security.course_coverage_build_v1', 'CF-247 s720 (Platform Admin 19 Nov 2026 08:17, IQ-00609): bounded coverage build'),
  ('pipeline', 'admit.consumer_snapshot_page_size', 'Admission evidence: consumer API rows read', 'Rows each consumer API read returns in the before/after evidence snapshot of an admission batch.',
   'number', to_jsonb(5), 1, 25, 'rows', 641, 'Admission checks', 'security.consumer_api_snapshot_v1', 'CF-247 s720 (IQ-00594/IQ-00588): bounded admission evidence snapshot'),
  ('pipeline', 'admit.consumer_snapshot_budget_ms', 'Admission evidence: snapshot time budget', 'The evidence snapshot stops after this long and marks the reads it skipped.',
   'number', to_jsonb(6000), 1000, 60000, 'ms', 642, 'Admission checks', 'security.consumer_api_snapshot_v1', 'CF-247 s720 (IQ-00594/IQ-00588): bounded admission evidence snapshot'),
  ('pipeline', 'plans.auto_stall_hours', 'Automatic plans: release after no movement for', 'An automatic plan whose jobs have not moved for this long, or whose held steps all wait on ended budget windows, is released so the planner has room.',
   'number', to_jsonb(2), 1, 48, 'hours', 121, 'Onboarding', 'security.enrich_plan_auto_v1', 'CF-247 s720 (Platform Admin 19 Nov 2026 08:17): reclaim stalled planner slots')
on conflict do nothing;

create or replace function pg_temp.cf_edit_many(p_sig regprocedure, p_md5 text, p_old text[], p_new text[], p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_body text; v_c int; i int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), ''); v_body := v_src;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]); v_body := replace(v_body, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(v_body) then raise exception '% after the edits is not the expected body', p_sig; end if;
end $f$;

-- 1. provider-chunked coverage build
select pg_temp.cf_edit_many('security.course_coverage_build_v1()'::regprocedure, '704dd0cfaa33a19c61383028fa6e1af8',
  array[
    $o$declare v_n int; v_t0 timestamptz:=clock_timestamp();$o$,
    $o$  create temp table _c on commit drop as$o$,
    $o$     where co.lifecycle_status='active'; -- Decision 213: every country$o$,
    $o$      from (select provider_id, row_number() over (partition by min(country_code) order by count(*) desc, provider_id) rk from _c group by provider_id) x; -- tiers within each country$o$,
    $o$select distinct course_id from pipeline.layer2_course_discovery_candidates where selected and course_id is not null;$o$,
    $o$from pipeline.layer2_run_items where entity_type='course' group by entity_id;$o$,
    $o$      from pipeline.coverage_course_pages;$o$,
    $o$create temp table _aer_cov on commit drop as select x.course_id from security.aer_covered_courses_v1() x;$o$,
    $o$      from pipeline.layer4_review_items where entity_type='course' and status='pending'$o$,
    $o$from pipeline.layer3_work_items where entity_type='course' and status='layer4_required';$o$,
    $o$from pipeline.layer3_work_items where entity_type='course' and status in ('pending','reserved','failed','retry');$o$,
    $o$select distinct on (course_id, field) course_id, field, state from pipeline.field_enrich_items where course_id is not null order by course_id, field, id desc;$o$,
    $o$from pipeline.course_field_absence a join pipeline.field_absence_classes k on k.code=a.absence_class where a.resolved_at is null;$o$,
    $o$  truncate pipeline.course_attribute_coverage;$o$,
    $o$  delete from pipeline.course_coverage_daily where snapshot_date=current_date;
  insert into pipeline.course_coverage_daily(snapshot_date,attribute,state,tier,courses)
  select current_date, attribute, state, tier, count(*) from pipeline.course_attribute_coverage where country_code='AU' group by 2,3,4;
  -- Decision 213: daily counts by country
  update pipeline.course_coverage_daily_by_country set courses = 0, computed_at = now() where snapshot_date = current_date;
  insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)
  select current_date, country_code, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4,5
  on conflict (snapshot_date,country_code,attribute,state,tier) do update set courses = excluded.courses, computed_at = now();$o$,
    $o$return jsonb_build_object('rows',v_n,'courses',(select count(*) from _c),$o$
  ],
  array[
    $n$declare v_n int; v_t0 timestamptz:=clock_timestamp();
        v_batch int := greatest(1, security.pipeline_num_v1('batch.course_coverage_courses', 1500)::int); v_chunk uuid[]; v_gone uuid[]; v_full boolean := false;  -- 20261119104500 (s720)$n$,
    $n$  -- 20261119104500 (s720): provider-chunked. Every provider with active courses and its country; the chunk is the providers whose coverage rows
  -- are oldest (never built first), up to batch.course_coverage_courses courses (always at least one provider)
  create temp table _pc on commit drop as
    select co.provider_id, min(k.iso_alpha2::text) country_code, count(*) n
      from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id
     where co.lifecycle_status='active' group by co.provider_id;
  -- when each provider was last built: one row of each (a run writes one time per provider), found by the provider index
  create temp table _cp on commit drop as
    select pc.provider_id, (select x.computed_at from pipeline.course_attribute_coverage x where x.provider_id = pc.provider_id limit 1) last_at from _pc pc;
  select array_agg(z.provider_id) into v_chunk from (
    select q.provider_id, sum(q.n) over (order by q.last_at nulls first, q.provider_id) run_n, row_number() over (order by q.last_at nulls first, q.provider_id) rn
      from (select pc.provider_id, pc.n, x.last_at from _pc pc left join _cp x on x.provider_id = pc.provider_id) q) z
   where z.rn = 1 or z.run_n <= v_batch;
  -- providers whose rows remain but who have no active course left; their rows are removed in the same run
  v_gone := array(select p.id from catalogue.providers p
                   where not exists (select 1 from _pc pc where pc.provider_id = p.id)
                     and exists (select 1 from pipeline.course_attribute_coverage x where x.provider_id = p.id));
  create temp table _c on commit drop as$n$,
    $n$     where co.lifecycle_status='active' and co.provider_id = any(v_chunk); -- Decision 213: every country; 20261119104500: the chunk
  analyze _c;  -- s720: the chunk's statistics, so the per-course reads below use their indexes$n$,
    $n$      from (select provider_id, row_number() over (partition by country_code order by n desc, provider_id) rk from _pc) x; -- tiers within each country (every provider, s720)$n$,
    $n$select distinct course_id from pipeline.layer2_course_discovery_candidates where selected and course_id is not null and course_id in (select course_id from _c);$n$,
    $n$from pipeline.layer2_run_items where entity_type='course' and entity_id in (select course_id from _c) group by entity_id;$n$,
    $n$      from pipeline.coverage_course_pages where course_id in (select course_id from _c);$n$,
    $n$-- s720: the three rules of security.aer_covered_courses_v1, restricted to the chunk (the function itself reads every course, 4.8 s)
  create temp table _aer_cov on commit drop as
  with lv as (select l.id, array_remove(array[l.id] || array(select l2.id from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.level_equivalents'), '[]'::jsonb)) p
                                                          join ref.study_levels l2 on l2.short_code = split_part(p, '=', 2) where split_part(p, '=', 1) = l.short_code), null) ids
              from ref.study_levels l),
  pm as (select m.provider_id, array_agg(distinct x) levels
           from catalogue.provider_entry_matrix m
           cross join lateral unnest(array_remove(array[m.study_level_id], null) || coalesce(security.entry_label_levels_v1(m.level_label), '{}'::uuid[])) x
          where m.status = 'active' and m.course_id is null and m.matrix_kind = 'provider_minimum' and m.min_grade is not null and m.grade_scale is distinct from 'none'
            and m.provider_id = any(v_chunk)
          group by 1)
  select co.id course_id from catalogue.courses co join lv on lv.id = co.study_level_id join pm on pm.provider_id = co.provider_id and pm.levels && lv.ids
   where co.lifecycle_status = 'active' and co.provider_id = any(v_chunk)
  union
  select m.course_id from catalogue.provider_entry_matrix m
   where m.status = 'active' and m.course_id is not null and m.min_grade is not null and m.grade_scale is distinct from 'none' and m.course_id in (select course_id from _c)
  union
  select r.course_id from catalogue.course_entry_requirements r
   where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)
     and r.course_id in (select course_id from _c);$n$,
    $n$      from pipeline.layer4_review_items where entity_type='course' and status='pending' and entity_id in (select course_id from _c)$n$,
    $n$from pipeline.layer3_work_items where entity_type='course' and status='layer4_required' and entity_id in (select course_id from _c);$n$,
    $n$from pipeline.layer3_work_items where entity_type='course' and status in ('pending','reserved','failed','retry') and entity_id in (select course_id from _c);$n$,
    $n$select c.course_id, x.field, x.state from _c c
      cross join lateral (select distinct on (e.field) e.field, e.state from pipeline.field_enrich_items e where e.course_id = c.course_id order by e.field, e.id desc) x;  -- s720: course by course$n$,
    $n$from _c cc join pipeline.course_field_absence a on a.course_id = cc.course_id join pipeline.field_absence_classes k on k.code=a.absence_class where a.resolved_at is null;  -- s720: the chunk$n$,
    $n$  -- s720: the chunk's providers are rebuilt in place, and the rows of providers with no active course left are removed (derived rows)
  create index on _l4 (course_id, attribute); create index on _l3 (course_id, attribute);  -- s720: the review and Layer 3 checks are per row
  analyze _val; analyze _read; analyze _found; analyze _sw; analyze _l4; analyze _l3; analyze _ei; analyze _ab;  -- s720: the chunk's statistics for the write
  -- the counts of the rows removed are kept so the daily counts can move by this run's change
  create temp table _dold (country_code text, attribute text, state text, tier text, n int) on commit drop;
  with d as (delete from pipeline.course_attribute_coverage where provider_id = any(v_chunk || v_gone) returning country_code, attribute, state, tier)
  insert into _dold select country_code, attribute, state, tier, count(*)::int from d group by 1,2,3,4;$n$,
    $n$  -- s720: the daily counts move by this run's change (the rows removed above and the rows written now); this function is the only writer of
  -- these rows. The first run of a day starts from the latest earlier day's counts, or counts the whole table once when there are none.
  if not exists (select 1 from pipeline.course_coverage_daily_by_country where snapshot_date = current_date) then
    if exists (select 1 from pipeline.course_coverage_daily_by_country where snapshot_date < current_date) then
      insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)
      select current_date, country_code, attribute, state, tier, courses from pipeline.course_coverage_daily_by_country
       where snapshot_date = (select max(snapshot_date) from pipeline.course_coverage_daily_by_country where snapshot_date < current_date);
    else
      insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)
      select current_date, country_code, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4,5;
      v_full := true;
    end if;
  end if;
  if not v_full then
    -- Decision 213: daily counts by country
    insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)
    select current_date, country_code, attribute, state, tier, sum(n)::int from (
      select country_code, attribute, state, tier, -n n from _dold
      union all
      select country_code, attribute, state, tier, count(*)::int from pipeline.course_attribute_coverage where provider_id = any(v_chunk) group by 1,2,3,4) d
     group by 2,3,4,5
    on conflict (snapshot_date,country_code,attribute,state,tier) do update set courses = pipeline.course_coverage_daily_by_country.courses + excluded.courses, computed_at = now();
  end if;
  -- the Australian daily counts are the Australian rows of the counts by country
  delete from pipeline.course_coverage_daily where snapshot_date=current_date;
  insert into pipeline.course_coverage_daily(snapshot_date,attribute,state,tier,courses)
  select current_date, attribute, state, tier, courses from pipeline.course_coverage_daily_by_country
   where snapshot_date = current_date and country_code = 'AU' and courses <> 0;$n$,
    $n$return jsonb_build_object('rows',v_n,'courses',(select count(*) from _c),'providers',cardinality(v_chunk),'gone',cardinality(v_gone),'batch',v_batch,$n$
  ],
  '20261119104500 (s720)');

update pipeline.rollup_targets set schedule = '2-59/5 * * * *', expected_ms = 8000, updated_at = now(),  -- fixed: the target's own schedule; batch size is the setting
       note = coalesce(note, '') || ' | 19 Nov 2026 (20261119104500, s720): provider-chunked (batch.course_coverage_courses), every 5 minutes; the whole table is refreshed about every 2 hours'
 where target_code = 'course-coverage-build';

-- 2. bounded consumer API evidence snapshot (same frozen reads, smaller pages, a time budget)
do $g$ begin
  if md5((select prosrc from pg_proc where oid = 'security.consumer_api_snapshot_v1()'::regprocedure)) <> '95c063d16fa95b0f06221cb74e11fd44'
     and position('20261119104500' in (select prosrc from pg_proc where oid = 'security.consumer_api_snapshot_v1()'::regprocedure)) = 0 then
    raise exception 'live security.consumer_api_snapshot_v1 differs from the definition this change replaces';
  end if;
end $g$;
do $r$
declare v_def text := replace(pg_get_functiondef('security.consumer_api_snapshot_v1()'::regprocedure), chr(13), '');
        v_body text := (select prosrc from pg_proc where oid = 'security.consumer_api_snapshot_v1()'::regprocedure);
        v_new text := $b$
-- 20261119104500 (s720): the before/after evidence of an admission batch (pipeline.consumer_api_baselines, Decision 163): the same frozen reads,
-- admit.consumer_snapshot_page_size rows each, cheap reads first and the two free-text searches (about 7 s each) last, stopping at
-- admit.consumer_snapshot_budget_ms (the reads it skips are marked). A statement-timeout cancel cannot be caught, so the budget is checked
-- before each read.
declare res jsonb := '{}'::jsonb; r jsonb; t0 timestamptz; c record; v_start timestamptz := clock_timestamp();
        v_page int := greatest(1, security.pipeline_num_v1('admit.consumer_snapshot_page_size', 5)::int);
        v_budget int := greatest(1000, security.pipeline_num_v1('admit.consumer_snapshot_budget_ms', 6000)::int);
begin
  for c in select * from (values
    ('search_has_provider_tuition', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,null,null,null,true,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('search_has_scholarship', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,true,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('search_tuition_range', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,40000,60000,null,null,null,null,%1$s,0))$q$),
    ('search_nz', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['NZ'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('lookup_080729G', $q$select to_jsonb(public.zoho_edge_course_lookup_v1('080729G'))$q$),
    ('lookup_121174E', $q$select to_jsonb(public.zoho_edge_course_lookup_v1('121174E'))$q$),
    ('providers_university_au', $q$select to_jsonb(public.zoho_edge_provider_search_v1('university','AU',null,%1$s,0))$q$),
    ('filter_country', $q$select to_jsonb(public.zoho_edge_filter_options_v1('country',null,null,50,0))$q$),
    ('filter_subdivision_au', $q$select to_jsonb(public.zoho_edge_filter_options_v1('subdivision','AU',null,50,0))$q$),
    ('reference_bundle', $q$select to_jsonb(public.zoho_edge_reference_bundle_v1())$q$),
    ('website_preview_080729G', $q$select api.website_course_lookup_preview_v1('080729G')$q$),
    ('search_bachelor_au', $q$select to_jsonb(public.zoho_edge_course_search_v2('bachelor',array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('search_master_page2', $q$select to_jsonb(public.zoho_edge_course_search_v2('master',array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,%1$s))$q$)
  ) v(case_name, stmt) loop
    if extract(epoch from clock_timestamp() - v_start) * 1000 > v_budget then
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok', null, 'skipped', 'time budget', 'budget_ms', v_budget));
      continue;
    end if;
    begin
      t0 := clock_timestamp();
      execute format(c.stmt, v_page) into r;
      r := r - 'generated_at';
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok',true,'md5',md5(r::text),'bytes',length(r::text),'ms',round(extract(epoch from clock_timestamp()-t0)*1000),'rows_asked',v_page));
    exception when others then
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok',false,'error',sqlerrm));
    end;
  end loop;
  return res;
end $b$;
begin
  if position('20261119104500' in v_body) > 0 then return; end if;
  -- the definition keeps its own attributes (security, search path); only the body changes
  execute replace(v_def, v_body, v_new);
end $r$;

-- 3. the coverage admission never waits for the search-document writer
select pg_temp.cf_edit_many('security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure, 'd36afc8ba115bb8befaa1e8e1d0aea0c',
  array[$o$    perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    v_after:=security.consumer_api_snapshot_v1();$o$],
  array[$n$    -- 20261119104500 (s720): never wait for the search-document writer; when it is busy the courses go to the search refresh queue, as
    -- security.intake_dates_apply_v1 does (search.refresh_requests, processed by the search refresh job's next run)
    if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)
      perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    else
      insert into search.refresh_requests(requested_by) values ('coverage admission: ' || cardinality(v_courses) || ' courses (search writer busy)');
    end if;
    v_after:=security.consumer_api_snapshot_v1();$n$],
  '20261119104500 (s720)');

-- 4. one claim per stored page
select pg_temp.cf_edit_many('public.svc_page_text_next_v1(integer)'::regprocedure, '3fde717c00cd160b6dd3916ee761cc31',
  array[$o$    select evidence_id, course_id, 'claimed', now() from cand
    on conflict$o$],
  array[$n$    -- 20261119104500 (s720, IQ-00606): two courses can share one stored page; the page is claimed once (the items still list every course)
    select distinct on (evidence_id) evidence_id, course_id, 'claimed', now() from cand order by evidence_id, weight desc, csort
    on conflict$n$],
  '20261119104500 (s720');

-- 5. evidence index: ranked providers in order, stopping at the limit
do $g$ begin
  if md5((select prosrc from pg_proc where oid = 'public.svc_evidence_link_index_next_v1(integer)'::regprocedure)) <> 'bbf9a911ab66c7c63a5123efc4e9dedb'
     and position('20261119104500' in (select prosrc from pg_proc where oid = 'public.svc_evidence_link_index_next_v1(integer)'::regprocedure)) = 0 then
    raise exception 'live svc_evidence_link_index_next_v1 differs from the definition this change replaces';
  end if;
end $g$;
do $r$
declare v_def text := replace(pg_get_functiondef('public.svc_evidence_link_index_next_v1(integer)'::regprocedure), chr(13), '');
        v_body text := (select prosrc from pg_proc where oid = 'public.svc_evidence_link_index_next_v1(integer)'::regprocedure);
        v_new text := $b$
  -- 20261119104500 (s720, IQ-00348): ranked providers in order, each provider's newest unindexed artifacts, stopping at the limit (keyset; was a
  -- global sort of every eligible artifact, 9.5 s)
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.storage_path,'mime',x.mime_type,'url',x.source_url,'type',x.evidence_type)),'[]'::jsonb)
  from (select y.id, y.storage_path, y.mime_type, y.source_url, y.evidence_type
          from (select o.provider_id, o.rank_no from pipeline.layer2_onboarding_snapshot o order by o.rank_no) o
          cross join lateral (
            select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type, e.captured_at
              from pipeline.sources s join pipeline.evidence_artifacts e on e.source_id = s.id
              left join pipeline.evidence_link_index_state st on st.evidence_id = e.id
             where s.provider_id = o.provider_id and e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
               and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
               and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
               and (st.evidence_id is null or (st.status='error' and st.indexed_at < now()-interval '6 hours'))
             order by e.captured_at desc nulls last
             limit greatest(1,least(coalesce(p_limit,60),200))) y
         limit greatest(1,least(coalesce(p_limit,60),200))) x
$b$;
begin
  if position('20261119104500' in v_body) > 0 then return; end if;
  execute replace(v_def, v_body, v_new);
end $r$;

-- 6. the planner releases stalled automatic plans before it counts its room
select pg_temp.cf_edit_many('security.enrich_plan_auto_v1()'::regprocedure, 'f0c95d0bbef3ccac550585185c9784c9',
  array[$o$  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');$o$],
  array[$n$  -- 20261119104500 (s720): release automatic plans whose jobs have not moved for plans.auto_stall_hours, or whose held steps all wait on budget
  -- windows that have ended; the plan is kept (cancelled, outcome released_stalled) and its jobs are not touched
  update pipeline.enrich_plan_runs r
     set state = 'cancelled', finished_at = now(), updated_at = now(), outcome = 'released_stalled',
         outcome_detail = coalesce(r.outcome_detail, '{}'::jsonb) || jsonb_build_object('released_at', now(), 'rule', 's720',
           'reason', 'no job movement for ' || security.pipeline_num_v1('plans.auto_stall_hours', 2)::int || ' h, or every held step waits on an ended budget window')
   where r.mode = 'auto' and r.state in ('queued', 'running')
     and r.created_at < now() - make_interval(hours => security.pipeline_num_v1('plans.auto_stall_hours', 2)::int)
     and ((not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.steps) = 'array' then r.steps else '[]'::jsonb end) s
                        join pipeline.admin_jobs j on j.id::text = s->'ref'->>'id'
                       where s->'ref'->>'kind' = 'job' and j.updated_at > now() - make_interval(hours => security.pipeline_num_v1('plans.auto_stall_hours', 2)::int)))
          or (exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.steps) = 'array' then r.steps else '[]'::jsonb end) s where s ? 'held')
              and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.steps) = 'array' then r.steps else '[]'::jsonb end) s
                               where s ? 'held' and coalesce((s->'held'->>'ends_at')::timestamptz, 'infinity'::timestamptz) > now())));
  select count(*) into v_open from pipeline.enrich_plan_runs where mode = 'auto' and state in ('queued', 'running');$n$],
  '20261119104500 (s720)');

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_drift jsonb; v_a int; v_b int; v_prov uuid[];
begin
  -- the chunk's AER rules equal security.aer_covered_courses_v1 for the same courses (three providers with the most entry rows)
  select array_agg(provider_id) into v_prov from (select m.provider_id from catalogue.provider_entry_matrix m where m.status = 'active' group by 1 order by count(*) desc limit 3) z;
  select count(*) into v_a from security.aer_covered_courses_v1() x join catalogue.courses co on co.id = x.course_id where co.provider_id = any(v_prov) and co.lifecycle_status = 'active';
  select count(*) into v_b from (
    with lv as (select l.id, array_remove(array[l.id] || array(select l2.id from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.level_equivalents'), '[]'::jsonb)) p
                                                            join ref.study_levels l2 on l2.short_code = split_part(p, '=', 2) where split_part(p, '=', 1) = l.short_code), null) ids from ref.study_levels l),
    pm as (select m.provider_id, array_agg(distinct x) levels from catalogue.provider_entry_matrix m
             cross join lateral unnest(array_remove(array[m.study_level_id], null) || coalesce(security.entry_label_levels_v1(m.level_label), '{}'::uuid[])) x
            where m.status = 'active' and m.course_id is null and m.matrix_kind = 'provider_minimum' and m.min_grade is not null and m.grade_scale is distinct from 'none' and m.provider_id = any(v_prov) group by 1)
    select co.id from catalogue.courses co join lv on lv.id = co.study_level_id join pm on pm.provider_id = co.provider_id and pm.levels && lv.ids where co.lifecycle_status = 'active' and co.provider_id = any(v_prov)
    union select m.course_id from catalogue.provider_entry_matrix m join catalogue.courses co on co.id = m.course_id and co.lifecycle_status = 'active' and co.provider_id = any(v_prov)
           where m.status = 'active' and m.course_id is not null and m.min_grade is not null and m.grade_scale is distinct from 'none'
    union select r.course_id from catalogue.course_entry_requirements r join catalogue.courses co on co.id = r.course_id and co.lifecycle_status = 'active' and co.provider_id = any(v_prov)
           where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)) q;
  if v_a <> v_b then raise exception 'post-check: the chunk AER rules give % courses, security.aer_covered_courses_v1 gives %', v_b, v_a; end if;
  if (select count(*) from pg_proc where prosrc like '%20261119104500%' and oid in ('security.course_coverage_build_v1()'::regprocedure, 'security.consumer_api_snapshot_v1()'::regprocedure,
        'security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure, 'public.svc_page_text_next_v1(integer)'::regprocedure,
        'public.svc_evidence_link_index_next_v1(integer)'::regprocedure, 'security.enrich_plan_auto_v1()'::regprocedure)) <> 6 then
    raise exception 'post-check: not all six functions carry the change';
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 'consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
