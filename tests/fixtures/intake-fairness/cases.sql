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
declare n_prov int; n_max int; n_univ1 int; v_share int := security.pipeline_num_v1('intake_dates.provider_share', 25)::int; n_elig int;
begin
  select count(distinct c.provider_id) into n_elig from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and exists (select 1 from pipeline.provider_policy_proposals p where p.provider_id = c.provider_id and p.kind = 'intake_calendar' and p.status = 'approved');
  create temp table sel1 as select * from security.intake_dates_plan_v3(null, 200);
  select count(distinct provider_id), max(n) into n_prov, n_max from (select provider_id, count(*) n from sel1 group by 1) z;
  select count(*) into n_univ1 from sel1 s join jsonb_array_elements(security.intake_ui_scopes_v1()) x on (x->>'id')::uuid = s.provider_id where x->>'name' = 'Fixture Australian University 1';
  if (select count(*) from sel1) <> 200 or n_prov < least(n_elig, 200 / v_share) or n_max > v_share then
    raise exception 'starvation: % rows, % universities (eligible %), most for one %', (select count(*) from sel1), n_prov, n_elig, n_max; end if;
  if n_univ1 > v_share then raise exception 'the 5,200-course university took % rows', n_univ1; end if;
  raise notice 'PASS starvation: 200 rows over % universities (% eligible), at most % each; the 5,200-course university takes % (before the change one university took all 200)', n_prov, n_elig, n_max, n_univ1;
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
  raise notice 'PASS persistence: the next run takes none of the rows already decided and starts with the universities that waited (%)', coalesce(array_length(v_missing, 1), 0);
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
    ('locked', public.fixture_clone_intake(src, 'February', 'Intakes: Term 1 (February)', 2027));
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
  raise notice 'PASS precedence: the 2023 reading is set aside as an obsolete edition (kept, approved); Teaching period T1 and Term 1 are one period; sub-periods keep their names';
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
      when r.name = 'testimonial' and not (r.outcome = 'skipped' and r.start_date is null) then ' testimonial ' || row_to_json(r)::text
      when r.name = 'testimonial_term' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page does not state term 1 as its own intake%') then ' testimonial_term ' || row_to_json(r)::text
      when r.name = 'testimonial_may' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page does not state % as an intake (offering evidence missing%') then ' ' || r.name || ' ' || row_to_json(r)::text
      when r.name = 'college_jan' and not (r.outcome = 'skipped' and r.start_date is null) then ' college_jan ' || row_to_json(r)::text
      when r.name = 'college_may' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'wrong_institution_or_campus' and r.reason like 'the course''s intakes (January, May, August) do not all start in%') then ' ' || r.name || ' ' || row_to_json(r)::text
      when r.name = 'own_date' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page gives its own start date%') then ' own_date ' || row_to_json(r)::text
      when r.name = 'locked' and not (r.outcome = 'skipped' and r.start_date is null and r.failure_class = 'admission_held') then ' locked ' || row_to_json(r)::text
      else '' end;
  end loop;
  if f <> '' then raise exception 'admission cases:%', f; end if;
  -- the same inputs: nothing is looked at again
  v := security.intake_dates_apply_v1(100, v_courses);
  if (v->>'looked_at')::int <> 0 then raise exception 'unchanged rows looked at again: %', v; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';  -- as in production (IQ-00313)
  raise notice 'PASS admission: Term 1 and Term 2 2027 admitted from the current calendar (named Term on the course page, published); a testimonial, a pathway timetable, a course date and a lock keep the month with their class; unchanged rows not repeated';
end $$;

-- governed withdrawal: only what the process admitted, only while held, never under a lock; the website source follows -------------------
do $$
declare v jsonb; t1 uuid := (select id from k where name = 'term1'); ok boolean := false; n_ev int;
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
  raise notice 'PASS withdrawal: Platform Admin only; the admitted start date reverted, the year held before kept, history appended, Website API v2 source verified; not re-admitted; never twice; a lock is respected';
end $$;
