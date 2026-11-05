-- Guards: Platform Admin direction 5 Nov 2026 15:50 §6 (pre-production gate) and P0 IQ-00313: migration 20261105060000 on the
-- production-parity fixture (ten universities, one with 5,200 courses; one with no approved calendar). Regressions: obsolete 2023 calendar
-- losing to current 2027 evidence, Term 1 / T1 canonical matching, different institution or pathway college, testimonial falsely presented as
-- intake evidence, course-specific exceptions, provider starvation under heavily skewed course counts, zero-eligible university (it takes
-- nothing and blocks nobody), duplicate or unchanged work suppression, manual locks, real admission and consumer publication, governed withdrawal.
\set ON_ERROR_STOP on
\set QUIET on
create temp table k(name text primary key, id uuid);

-- the selector across ten universities (before any admission in this file) ---------------------------------------------------------------
do $$
declare v_t0 timestamptz; v_ms numeric; n_prov int; n_max int; n_univ1 int; v_share int := security.pipeline_num_v1('intake_dates.provider_share', 25)::int; n_elig int;
begin
  select count(distinct c.provider_id) into n_elig from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and exists (select 1 from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved');
  v_t0 := clock_timestamp();
  create temp table sel1 as select * from security.intake_dates_plan_v3(null, 200);
  v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
  if v_ms > 8000 then raise exception 'the fair plan took % ms for 200 rows (limit 8,000)', v_ms::int; end if;  -- the preview's statement limit
  select count(distinct provider_id), max(n) into n_prov, n_max from (select provider_id, count(*) n from sel1 group by 1) z;
  select count(*) into n_univ1 from sel1 s join jsonb_array_elements(security.intake_ui_scopes_v1()) x on (x->>'id')::uuid = s.provider_id where x->>'name' = 'Fixture Australian University 1';
  if (select count(*) from sel1) <> 200 or n_prov < least(n_elig, 200 / v_share) or n_max > v_share then
    raise exception 'starvation: % rows, % universities (eligible %), most for one %', (select count(*) from sel1), n_prov, n_elig, n_max; end if;
  if n_univ1 > v_share then raise exception 'the 5,200-course university took % rows', n_univ1; end if;
  raise notice 'PASS starvation: 200 rows over % universities (% eligible), at most % each; the 5,200-course university takes % (before the change one university took all 200); % ms', n_prov, n_elig, n_max, n_univ1, v_ms::int;
end $$;

-- a university whose rows were all served is behind one never served in the next run (progress persists) --------------------------------
do $$
declare v_first uuid; v_missing uuid[];
begin
  -- the universities that did not fit the first batch come first next time: mark the selected ones as served now
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, inputs_fp, next_action)
  select intake_id, course_id, provider_id, 'skipped', 'fixture: served', now(), inputs_fp, 'evidence_ambiguous' from sel1
  on conflict (intake_id) do update set outcome = 'skipped', reason = 'fixture: served', applied_at = now(), inputs_fp = excluded.inputs_fp, next_action = 'evidence_ambiguous', next_revisit_at = null;
  select array_agg(distinct p.provider_id) into v_missing from security.intake_dates_plan_v3(null, 400) p where p.provider_id not in (select provider_id from sel1);
  create temp table sel2 as select * from security.intake_dates_plan_v3(null, 200);
  if exists (select 1 from sel2 join sel1 using (intake_id)) then raise exception 'unchanged rows selected again'; end if;
  if v_missing is not null and not exists (select 1 from sel2 where provider_id = any (v_missing)) then raise exception 'a university that waited was not served next: %', v_missing; end if;
  -- it comes first among universities of its focus standing (focus universities first in every round, then the rest)
  if v_missing is not null and (select s.provider_id from (select p.*, row_number() over () rn from security.intake_dates_plan_v3(null, 200) p) s
                                  left join pipeline.enrich_focus_providers f on f.provider_id = s.provider_id and f.in_focus
                                 where (f.provider_id is null) = (select bool_and(f2.provider_id is null) from unnest(v_missing) m
                                                                    left join pipeline.enrich_focus_providers f2 on f2.provider_id = m and f2.in_focus)
                                 order by s.rn limit 1) <> all (v_missing) then raise exception 'the waiting university is not first among its peers'; end if;
  raise notice 'PASS persistence: the next run takes none of the rows already decided and starts with the universities that waited (%)', coalesce(array_length(v_missing, 1), 0);
end $$;

-- focus priority within a round (17:26 production finding): a focus university served before comes ahead of universities outside the focus list
do $$
declare v_focus uuid; v_first uuid; n_focus int;
begin
  select (x->>'id')::uuid into v_focus from jsonb_array_elements(security.intake_ui_scopes_v1()) x where x->>'name' = 'Fixture Australian University 4';
  insert into pipeline.enrich_focus_providers(provider_id, rank, gaps, in_focus) values (v_focus, 1, 1, true)
  on conflict (provider_id) do update set rank = 1, in_focus = true;
  update pipeline.enrich_focus_providers set in_focus = false where provider_id <> v_focus;
  -- it was served a moment ago; every other university waited longer or was never served
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, inputs_fp, next_action)
  select i.id, i.course_id, c.provider_id, 'skipped', 'fixture: focus served', now(), 'fixture-focus', 'evidence_ambiguous'
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where c.provider_id = v_focus limit 1
  on conflict (intake_id) do nothing;
  select provider_id into v_first from security.intake_dates_plan_v3(null, 1);
  select count(*) into n_focus from security.intake_dates_plan_v3(null, 200) where provider_id = v_focus;
  if v_first <> v_focus or n_focus <> security.pipeline_num_v1('intake_dates.provider_share', 25)::int then
    raise exception 'focus priority: first %, focus rows %', v_first, n_focus; end if;
  update pipeline.enrich_focus_providers set in_focus = true where provider_id <> v_focus;  -- restore the fixture's focus list
  raise notice 'PASS focus priority: a focus university served a moment ago still comes first in its round (% rows) ahead of universities outside the focus list that were never served', n_focus;
end $$;

-- selection, three properties tested independently (Platform Admin 5 Nov 2026 18:00): provider fairness, focus priority, explicit pilot scope.
-- Production shape: a 4-university pilot (run_now.cohort_top_au_universities), focus providers outside the pilot served longest ago,
-- providers outside both, and one pilot university with no eligible work.
do $$
declare v_pilot uuid[]; v_focus_np uuid[]; n_pilot int; n_np int; n_focus_np int; n_nonfocus int; v_max int; v_first_np uuid; v_share int := security.pipeline_num_v1('intake_dates.provider_share', 25)::int;
        v_zero uuid; n_prov int;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(4) where toolset_key = 'pipeline' and key = 'run_now.cohort_top_au_universities';
  if not found then insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, unit, section, used_by, reason)
    values ('pipeline', 'run_now.cohort_top_au_universities', 'fixture', 'number', to_jsonb(4), 'universities', 'fixture', 'fixture', 'fixture'); end if;
  select array_agg((e->>'id')::uuid) into v_pilot from jsonb_array_elements(security.intake_ui_scopes_v1()) e;
  if array_length(v_pilot, 1) <> 4 then raise exception 'pilot size %', array_length(v_pilot, 1); end if;
  -- two universities outside the pilot are in focus and were served long ago; the pilot was served a moment ago
  select array_agg(id) into v_focus_np from (select (e->>'id')::uuid id from jsonb_array_elements((select jsonb_agg(x) from (select jsonb_build_object('id', p.id) x from catalogue.providers p
      where p.id in (select distinct c.provider_id from catalogue.courses c join catalogue.course_intakes i on i.course_id = c.id where i.status = 'active') and p.id <> all (v_pilot)
      and exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = p.id and pp.kind = 'intake_calendar' and pp.status = 'approved') order by p.id limit 2) z)) e) y;
  update pipeline.enrich_focus_providers set in_focus = false;
  insert into pipeline.enrich_focus_providers(provider_id, rank, gaps, in_focus) select x, 50 + row_number() over (), 1, true from unnest(v_focus_np) x
  on conflict (provider_id) do update set in_focus = true, rank = excluded.rank;
  insert into pipeline.enrich_focus_providers(provider_id, rank, gaps, in_focus) select x, row_number() over (), 1, true from unnest(v_pilot) x
  on conflict (provider_id) do update set in_focus = true, rank = excluded.rank;
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, inputs_fp, next_action)
  select distinct on (c.provider_id) i.id, i.course_id, c.provider_id, 'skipped', 'fixture: pilot served', now(), 'fixture-pilot', 'evidence_ambiguous'
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where c.provider_id = any (v_pilot) order by c.provider_id, i.id
  on conflict (intake_id) do nothing;
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, inputs_fp, next_action)
  select distinct on (c.provider_id) i.id, i.course_id, c.provider_id, 'skipped', 'fixture: focus served long ago', now() - interval '1 day', 'fixture-focus-np', 'evidence_ambiguous'
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where c.provider_id = any (v_focus_np) order by c.provider_id, i.id
  on conflict (intake_id) do nothing;
  create temp table sel_p as select p.*, row_number() over () rn from security.intake_dates_plan_v3(null, 200) p;
  select count(*) filter (where provider_id = any (v_pilot)), count(*) filter (where provider_id <> all (v_pilot)),
         count(*) filter (where provider_id = any (v_focus_np)), count(distinct provider_id) into n_pilot, n_np, n_focus_np, n_prov from sel_p;
  select max(n) into v_max from (select provider_id, count(*) n from sel_p group by 1) z;
  -- pilot scope: the pilot takes its share (60% of 200) although it was served a moment ago, every pilot university with eligible rows is in it
  if n_pilot <> 120 or (select count(distinct provider_id) from sel_p where provider_id = any (v_pilot)) <> (select count(distinct c.provider_id) from security.intake_dates_plan_v3(null, 5000) x join catalogue.courses c on c.id = x.course_id where c.provider_id = any (v_pilot)) then
    raise exception 'pilot scope: % pilot rows', n_pilot; end if;
  -- global: the rest goes outside the pilot, at least three providers, focus providers outside the pilot first
  select provider_id into v_first_np from sel_p where provider_id <> all (v_pilot) order by rn limit 1;
  if n_np <> 80 or v_first_np <> all (v_focus_np) or n_focus_np = 0 then raise exception 'global share: % rows, first %, focus %', n_np, v_first_np, n_focus_np; end if;
  -- fairness: no provider takes more than two rounds (pilot round 2 fills its share) and at least five providers are served
  if v_max > 2 * v_share or n_prov < 5 then raise exception 'fairness: max % over % providers', v_max, n_prov; end if;
  -- share 0: the pilot gets no reserved rows (v2.15.484 order: focus first, longest waiting first)
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.pilot_batch_share';
  if (select provider_id from security.intake_dates_plan_v3(null, 1)) <> all (v_focus_np) then raise exception 'share 0 did not restore focus-first order'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(60) where toolset_key = 'pipeline' and key = 'intake_dates.pilot_batch_share';
  -- a pilot with no eligible rows blocks nobody: the batch is filled by the others
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'run_now.cohort_top_au_universities';
  select (e->>'id')::uuid into v_zero from jsonb_array_elements(security.intake_ui_scopes_v1()) e;
  -- every eligible row of the one-university pilot is already decided with its current inputs: it has no eligible work now
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, inputs_fp, next_action)
  select x.intake_id, x.course_id, x.provider_id, 'skipped', 'fixture: decided', now(), x.inputs_fp, 'evidence_ambiguous'
    from security.intake_dates_plan_v3((select array_agg(c.id) from catalogue.courses c where c.provider_id = v_zero), 100000) x
  on conflict (intake_id) do update set inputs_fp = excluded.inputs_fp, next_revisit_at = null;
  if exists (select 1 from security.intake_dates_plan_v3(null, 200) where provider_id = v_zero)
     or (select count(*) from security.intake_dates_plan_v3(null, 200)) <> 200 then raise exception 'a pilot with no eligible work blocked the batch'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(10) where toolset_key = 'pipeline' and key = 'run_now.cohort_top_au_universities';
  update pipeline.enrich_focus_providers set in_focus = true;
  -- the preview path (course ids given) is unchanged: no pilot reservation applies
  if (select count(*) from security.intake_dates_plan_v3((select array_agg(distinct course_id) from sel_p where provider_id = any (v_pilot)), 50)) = 0 then raise exception 'preview path'; end if;
  raise notice 'PASS selection: pilot scope takes its share (% rows, every pilot university with eligible work) though served a moment ago; the rest goes to % rows outside the pilot, focus providers first; at most % rows a provider over % providers; share 0 restores focus order; the preview path is unchanged', n_pilot, n_np, v_max, n_prov;
end $$;

-- calendars: an obsolete 2023 reading ("term 1") and the current 2027 reading ("teaching period t1/t2") ------------------------------------
do $$
declare src uuid; v_prov uuid := '08609bcf-387d-1316-2a52-9fbc0edff508';
begin
  select i.id into src from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join pipeline.evidence_artifacts e on e.id = i.evidence_id
   where c.provider_id = v_prov and i.status = 'active' and c.lifecycle_status = 'active'
     and not security.page_refused_v1(c.id, e.source_url) and security.course_page_check_v1(c.id, e.source_url, null, null)->>'verdict' = 'pass'
   order by i.id limit 1;
  insert into k values ('old2023', public.fixture_calendar('https://www.harbour.edu.au/key-dates-2023', 'ai:gpt-4.1-mini', $j${"periods": [
    {"period": "term 1", "months": [3], "years": [2023], "quotes": ["Term 1 March 2023"], "starts": [{"year": 2023, "month": 3, "day": 1, "date": "2023-03-01", "quote": "Term 1 March 2023", "meaning": "teaching_start"}], "deadlines": []}]}$j$::jsonb));
  insert into k values ('cur2027', public.fixture_calendar('https://www.harbour.edu.au/academic-calendar-2027', 'ai:gpt-4.1-mini:calendar-v2.1', $j${"parser": "ai:gpt-4.1-mini:calendar-v2.1", "scope": "main_teaching", "periods": [
    {"period": "teaching period t1", "months": [2], "years": [2027], "quotes": ["Teaching period T1 | 15 Feb - 23 Apr"], "starts": [{"year": 2027, "month": 2, "day": 15, "date": "2027-02-15", "quote": "Teaching period T1 | 15 Feb - 23 Apr", "year_quote": "year tabs 2026 | 2027: block 2 of \"### Term 1\" is 2027", "year_basis": "tabs", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "teaching period t2", "months": [5], "years": [2027], "quotes": ["Teaching period T2 | 31 May - 6 Aug"], "starts": [{"year": 2027, "month": 5, "day": 31, "date": "2027-05-31", "quote": "Teaching period T2 | 31 May - 6 Aug", "year_quote": "year tabs 2026 | 2027: block 2 of \"### Term 2\" is 2027", "year_basis": "tabs", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "teaching period t3", "months": [9], "years": [], "quotes": ["Teaching period T3 | 13 Sep - 19 Nov"], "starts": [{"year": null, "month": 9, "day": 13, "date": null, "quote": "Teaching period T3 | 13 Sep - 19 Nov", "meaning": "teaching_start"}], "deadlines": []}]}$j$::jsonb));
  insert into k values
    ('term1', public.fixture_clone_intake(src, 'February', 'Intakes: Term 1, Term 2 and Term 3 (February, May, September)', 2027)),
    ('term2', public.fixture_clone_intake(src, 'May', 'Intakes: Term 1, Term 2 and Term 3 (February, May, September)', 2027)),
    ('testimonial', public.fixture_clone_intake(src, 'February', 'Industry Partner: I commenced the Master of Industrial Research program in February 2023, having completed a Bachelor in Commerce', 2027)),
    ('testimonial_term', public.fixture_clone_intake(src, 'February', 'Student story: I commenced the program in Term 1 2023 and loved it', 2027)),
    ('testimonial_may', public.fixture_clone_intake(src, 'May', 'Industry Partner: I commenced the Master of Industrial Research program in February 2023, having completed a Bachelor in Commerce', 2027)),
    ('college_jan', public.fixture_clone_intake(src, 'January', 'Intakes January, May, August* Weekly class time Approximately 20-25 hours Progression Second year')),
    ('college_may', public.fixture_clone_intake(src, 'May', 'Intakes January, May, August* Weekly class time Approximately 20-25 hours Progression Second year')),
    ('own_date', public.fixture_clone_intake(src, 'February', 'Term 1 intake: classes begin 8 February 2027', 2027)),
    ('locked', public.fixture_clone_intake(src, 'February', 'Intakes: Term 1 (February)', 2027)),
    ('t1_label', public.fixture_clone_intake(src, 'February', 'T1 intake', 2027)),
    ('snippets', public.fixture_clone_intake(src, 'May', 'Student story: I commenced the program in May 2023 | Intakes: February and May')),
    ('may_verb', public.fixture_clone_intake(src, 'July', 'Students may start in February or July'));
  insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'course', course_id, 'intakes', 'value' from catalogue.course_intakes where id = (select id from k where name = 'locked');
  -- the Term courses are in the Website API v2 source (as published courses are); the projection refresh keeps their intakes current
  insert into search.course_documents(course_id, provider_id, intake_options)
  select i.course_id, v_prov, '[]'::jsonb from catalogue.course_intakes i where i.id in (select id from k where name in ('term1', 'term2')) on conflict do nothing;
end $$;

do $$
declare v jsonb;
begin
  -- the obsolete edition is set aside with its reason, never deleted; the current reading is used
  select jsonb_object_agg(s.url, jsonb_build_object('used', s.used, 'why', s.set_aside_reason)) into v from security.calendar_sources_v1('08609bcf-387d-1316-2a52-9fbc0edff508') s;
  if (v->'https://www.harbour.edu.au/key-dates-2023'->>'used')::boolean or v->'https://www.harbour.edu.au/key-dates-2023'->>'why' <> 'obsolete edition: its latest proved teaching start is in 2023'
     or not (v->'https://www.harbour.edu.au/academic-calendar-2027'->>'used')::boolean then raise exception 'sources: %', v; end if;
  if not exists (select 1 from pipeline.provider_policy_proposals where id = (select id from k where name = 'old2023') and status = 'approved') then raise exception 'the 2023 reading was changed'; end if;
  -- equivalent labels share one name
  if exists (select 1 from security.calendar_dated_periods_v2('08609bcf-387d-1316-2a52-9fbc0edff508') where period like 'teaching period t%')
     or not exists (select 1 from security.calendar_dated_periods_v2('08609bcf-387d-1316-2a52-9fbc0edff508') where period = 'term 1' and on_date = '2027-02-15') then raise exception 'canonical periods'; end if;
  if security.calendar_period_canonical_v1('Teaching period T1') <> 'term 1' or security.calendar_period_canonical_v1('T3') <> 'term 3' or security.calendar_period_canonical_v1('Term one') <> 'term 1'
     or security.calendar_period_canonical_v1('Teaching period S1') <> 'semester 1' or security.calendar_period_canonical_v1('Sem 2') <> 'semester 2' or security.calendar_period_canonical_v1('Tri 2') <> 'trimester 2'
     or security.calendar_period_canonical_v1('Teaching period T1A') <> 'teaching period t1a' then raise exception 'canonical names'; end if;
  -- a reading with only null-year starts, and a current-year edition, stay in use
  perform public.fixture_calendar('https://www.harbour.edu.au/null-year-dates', 'ai:gpt-4.1-mini:calendar-v2.1', '{"scope": "main_teaching", "periods": [{"period": "summer school", "months": [1], "years": [], "quotes": ["Summer school | 5 Jan"], "starts": [{"year": null, "month": 1, "day": 5, "date": null, "quote": "Summer school | 5 Jan", "meaning": "teaching_start"}], "deadlines": []}]}'::jsonb);
  perform public.fixture_calendar('https://www.harbour.edu.au/current-year-dates', 'ai:gpt-4.1-mini:calendar-v2.1', ('{"scope": "main_teaching", "periods": [{"period": "semester 2", "months": [7], "years": [' || extract(year from now())::int || '], "quotes": ["Semester 2 ' || extract(year from now())::int || ' | 20 July"], "starts": [{"year": ' || extract(year from now())::int || ', "month": 7, "day": 20, "date": "' || extract(year from now())::int || '-07-20", "quote": "Semester 2 ' || extract(year from now())::int || ' | 20 July", "meaning": "teaching_start"}], "deadlines": []}]}')::jsonb);
  if not (select bool_and(used) from security.calendar_sources_v1('08609bcf-387d-1316-2a52-9fbc0edff508') where url in ('https://www.harbour.edu.au/null-year-dates', 'https://www.harbour.edu.au/current-year-dates')) then
    raise exception 'a null-year or current-year reading was set aside'; end if;
  if security.intake_period_text_canonical_v1('Intakes: Teaching period T1, T2 and Sem 2; Tri 3') <> 'intakes: term 1, term 2 and semester 2; trimester 3' then raise exception 'page labels: %', security.intake_period_text_canonical_v1('Intakes: Teaching period T1, T2 and Sem 2; Tri 3'); end if;
  if security.intake_course_applicability_v1('Start your marketing career in February', 3, 2027, '[]'::jsonb, false) is null then raise exception 'marketing read as March'; end if;
  raise notice 'PASS precedence: the 2023 reading is set aside as an obsolete edition (kept, approved); Teaching period T1 and Term 1 are one period (on the calendar and on the course page); sub-periods keep their names; null-year and current-year readings stay in use';
end $$;

-- the plan and the job: admitted with course-specific evidence only; unique-month on for the applicability cases -----------------------------
do $$
declare v jsonb; f text := ''; r record; v_courses uuid[] := (select array_agg(course_id) from catalogue.course_intakes where id in (select id from k));
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
  v := security.intake_dates_apply_v1(100, v_courses);
  perform security.intake_publication_check_v1();
  for r in select k.name, d.outcome, d.reason, d.rule, d.failure_class, d.publication_state, i.start_date from k join pipeline.course_intake_dates d on d.intake_id = k.id join catalogue.course_intakes i on i.id = k.id loop
    f := f || case
      when r.name = 'term1' and not (r.outcome = 'filled' and r.start_date = '2027-02-15' and r.rule = 'calendar-v3' and r.publication_state = 'published') then ' term1 ' || row_to_json(r)::text
      when r.name = 'term2' and not (r.outcome = 'filled' and r.start_date = '2027-05-31' and r.publication_state = 'published') then ' term2 ' || row_to_json(r)::text
      when r.name = 'testimonial' and not (r.outcome = 'skipped' and r.start_date is null and r.reason in ('several study periods start in this month (month only)')
                                           or r.reason like 'the course page does not state February as an intake (offering evidence missing%') then ' testimonial ' || row_to_json(r)::text
      when r.name = 'testimonial_term' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page does not state term 1 as its own intake%') then ' testimonial_term ' || row_to_json(r)::text
      when r.name = 'testimonial_may' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page does not state % as an intake (offering evidence missing%') then ' ' || r.name || ' ' || row_to_json(r)::text
      when r.name = 'college_jan' and not (r.outcome = 'skipped' and r.start_date is null and (r.reason like 'the calendar has no future start in this month%' or r.reason like 'the calendar does not print the year%' or r.reason like 'the course''s intakes (January, May, August)%')) then ' college_jan ' || row_to_json(r)::text
      when r.name = 'college_may' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'wrong_institution_or_campus' and r.reason like 'the course''s intakes (January, May, August) do not all start in%') then ' ' || r.name || ' ' || row_to_json(r)::text
      when r.name = 't1_label' and not (r.outcome = 'filled' and r.start_date = '2027-02-15' and r.rule = 'calendar-v3') then ' t1_label ' || row_to_json(r)::text
      when r.name = 'snippets' and not (r.outcome = 'filled' and r.start_date = '2027-05-31' and r.rule = 'calendar-v3-unique-month') then ' snippets ' || row_to_json(r)::text
      when r.name = 'may_verb' and not (r.outcome = 'filled' and r.start_date between '2027-07-01' and '2027-07-31' and r.rule = 'calendar-v3-unique-month') then ' may_verb ' || row_to_json(r)::text
      when r.name = 'own_date' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page gives its own start date%') then ' own_date ' || row_to_json(r)::text
      when r.name = 'locked' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'admission_held') then ' locked ' || row_to_json(r)::text
      else '' end;
  end loop;
  if f <> '' then raise exception 'admission cases:%', f; end if;
  -- the same inputs: nothing is looked at again
  v := security.intake_dates_apply_v1(100, v_courses);
  if (v->>'looked_at')::int <> 0 then raise exception 'unchanged rows looked at again: %', v; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';  -- as in production (IQ-00313)
  raise notice 'PASS admission: Term 1 and Term 2 2027 admitted from the current calendar (named Term on the course page, published); a page saying T1 matches Term 1; a real intake beside a testimonial in another snippet is admitted; "may" the verb is never May; a testimonial, a pathway timetable, a course date and a lock keep the month with their class; unchanged rows not repeated';
end $$;

-- governed withdrawal: only what the process admitted, only while held, never under a lock; the website source follows -------------------
do $$
declare v jsonb; t1 uuid := (select id from k where name = 'term1'); ok boolean := false; n_ev int; wf uuid; wm uuid;
begin
  begin perform public.admin_intake_date_withdraw_v1(array[t1], 'fixture: no sign-in'); exception when others then ok := sqlstate = '42501'; end;
  if not ok then raise exception 'withdrawal without Platform Admin not refused'; end if;
  select count(*) into n_ev from pipeline.course_intake_date_events where intake_id = t1;
  v := security.intake_date_withdraw_v1(t1, 'fixture: unsupported intake evidence (IQ-00313 case)', 'fixture');
  if not (v->>'withdrawn')::boolean or not (v->>'website_verified')::boolean or (select start_date from catalogue.course_intakes where id = t1) is not null
     or (select intake_year from catalogue.course_intakes where id = t1) <> 2027 then raise exception 'withdraw: %', v; end if;   -- the year was held before: kept
  if (select count(*) from pipeline.course_intake_date_events where intake_id = t1) <> n_ev + 1
     or not exists (select 1 from pipeline.course_intake_date_events where intake_id = t1 and outcome = 'filled') then raise exception 'history changed'; end if;
  if (select failure_class from pipeline.course_intake_dates where intake_id = t1) <> 'course_level_exception' then raise exception 'withdrawn class'; end if;
  -- withdrawn and held: not re-admitted by the job even when its inputs change (the existing manual lock)
  if not exists (select 1 from pipeline.manual_locks where entity = 'course' and entity_id = (select course_id from catalogue.course_intakes where id = t1) and field = 'intakes' and mode = 'value') then raise exception 'no hold'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  v := security.intake_dates_apply_v1(100, array[(select course_id from catalogue.course_intakes where id = t1)]);
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  if (select start_date from catalogue.course_intakes where id = t1) is not null then raise exception 're-admitted after withdrawal'; end if;
  -- nothing to withdraw twice
  v := security.intake_date_withdraw_v1(t1, 'fixture: second time', 'fixture');
  if (v->>'withdrawn')::boolean then raise exception 'withdrawn twice'; end if;
  -- a lock blocks the withdrawal
  insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'course', course_id, 'intakes', 'value' from catalogue.course_intakes where id = (select id from k where name = 'term2');
  v := security.intake_date_withdraw_v1((select id from k where name = 'term2'), 'fixture: locked', 'fixture');
  if (v->>'withdrawn')::boolean or (select start_date from catalogue.course_intakes where id = (select id from k where name = 'term2')) is distinct from '2027-05-31' then raise exception 'lock: %', v; end if;
  -- the Platform Admin path: several intakes of one course in one call, then one hold for the course; recorded in the admin control log
  perform set_config('request.jwt.claim.sub', '21232f29-7a57-a5a7-4389-4a0e4a801fc3', true);
  wf := public.fixture_clone_intake((select id from k where name = 'term1'), 'February', 'Intakes: Term 1 and Term 2');
  wm := gen_random_uuid();
  insert into catalogue.course_intakes(id, course_id, intake_label, intake_year, status, evidence_id, source_id, confidence)
  select wm, course_id, 'May', null, 'active', evidence_id, source_id, confidence from catalogue.course_intakes where id = wf;
  update catalogue.course_intakes set intake_year = 2027, start_date = case when id = wf then '2027-02-15'::date else '2027-05-31'::date end where id in (wf, wm);
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, before_value, after_value, applied_at, inputs_fp, next_action)
  select i.id, i.course_id, '08609bcf-387d-1316-2a52-9fbc0edff508', 'filled', jsonb_build_object('year', null, 'start_date', null, 'application_deadline', null),
         jsonb_build_object('year', 2027, 'start_date', i.start_date, 'application_deadline', null), now(), 'fixture', 'awaiting_official_calendar'
    from catalogue.course_intakes i where i.id in (wf, wm);
  -- every admission is also an event (as intake_dates_apply_v1 appends one per decision)
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, before_value, after_value)
  select intake_id, course_id, provider_id, applied_at, 'calendar-v3', 'filled', before_value, after_value from pipeline.course_intake_dates where intake_id in (wf, wm);
  v := public.admin_intake_date_withdraw_v1(array[wf, wm], 'fixture: two intakes of one course');
  if (v->>'withdrawn')::int <> 2 then raise exception 'admin withdrawal: %', v; end if;
  if (select count(*) from pipeline.manual_locks where entity = 'course' and field = 'intakes' and entity_id = (select course_id from catalogue.course_intakes where id = wf)) <> 1
     or (select count(*) from catalogue.course_intakes where id in (wf, wm) and start_date is null and intake_year is null) <> 2
     or not exists (select 1 from pipeline.admin_control_events where area = 'intake_dates' and action = 'withdraw') then raise exception 'hold or audit missing'; end if;
  raise notice 'PASS withdrawal: Platform Admin only; the admitted start date reverted, the year held before kept, history appended, Website API v2 source verified; not re-admitted; never twice; a lock is respected; the Platform Admin path withdraws two intakes of one course in one call, holds the course once and records it';
end $$;

-- IQ-00313 provenance (5 Nov 2026 16:47): an admission later re-decided by another run is still withdrawn from its own record ---------------
do $$
declare v jsonb; t uuid;
begin
  t := public.fixture_clone_intake((select id from k where name = 'term1'), 'February', 'Industry Partner: I commenced the program in February 2023', 2027);
  update catalogue.course_intakes set start_date = '2027-02-15' where id = t;
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, before_value, after_value)
  select t, course_id, '08609bcf-387d-1316-2a52-9fbc0edff508', now() - interval '2 hours', 'calendar-v3-unique-month', 'filled',
         '{"year": 2027, "start_date": null, "application_deadline": null}'::jsonb, '{"year": 2027, "start_date": "2027-02-15", "application_deadline": null}'::jsonb from catalogue.course_intakes where id = t;
  -- a later run re-decided it (the value unchanged): the decision row no longer shows the admission
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, before_value, after_value, applied_at, inputs_fp, next_action)
  select t, course_id, '08609bcf-387d-1316-2a52-9fbc0edff508', 'skipped', 'the course page names no study period of the calendar (month only)',
         '{"year": 2027, "start_date": "2027-02-15", "application_deadline": null}'::jsonb, '{"year": 2027, "start_date": "2027-02-15", "application_deadline": null}'::jsonb, now(), 'fixture-redecided', 'reader_correction_needed'
    from catalogue.course_intakes where id = t;
  v := security.intake_date_withdraw_v1(t, 'fixture: re-decided admission (IQ-00313 Master of Industrial Research case)', 'fixture', true);
  if not (v->>'withdrawn')::boolean or (select start_date from catalogue.course_intakes where id = t) is not null or (select intake_year from catalogue.course_intakes where id = t) <> 2027 then
    raise exception 're-decided admission: %', v; end if;
  v := security.intake_date_withdraw_v1(t, 'fixture: second time after the withdrawal', 'fixture', true);
  if (v->>'withdrawn')::boolean then raise exception 'withdrawn twice'; end if;
  raise notice 'PASS provenance: an admission re-decided by a later run is withdrawn from its own record (start date reverted, the year held before kept); never twice';
end $$;
