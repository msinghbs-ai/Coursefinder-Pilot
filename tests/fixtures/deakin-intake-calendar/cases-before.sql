-- Guards: IQ-00313 (Deakin commencement-date contamination, 8 Nov 2026): the defect, reproduced on the production definitions BEFORE migration 20261108050000.
-- A university whose approved calendar was read before calendar-v2.1 (no `starts` array) holds "Trimester 3: 1 Nov - 28 Jan <next year>". The old resolver
-- (security.calendar_proposal_dates_v1, md5 84aa52bc = production) took the first year anywhere in the quote, so the 1 November start was dated in the
-- year of the END date. This file builds a university like that, runs the production job code (security.intake_dates_apply_v1) so the contamination is
-- written by the real path, and stores the Website and Zoho items with the wrong date by the production scans. cases-after.sql then proves the fix.
-- The dates are relative to the clock (the next 1 November) so the test does not age.
\set ON_ERROR_STOP on
\set QUIET on


create table if not exists public.dk_cases (name text primary key, intake_id uuid, course_id uuid, provider_id uuid, proposal_id uuid, y0 int);

-- the university: a copy of the fixture's first university (same website, so the page check passes), with a stable key as production has
do $$
declare v_prov uuid := gen_random_uuid(); v_src_prov uuid := '08609bcf-387d-1316-2a52-9fbc0edff508'; v_prop uuid; v_src uuid; v_src_fs uuid; y0 int := public.fixture_dk_y0();
begin
  insert into catalogue.providers select (jsonb_populate_record(null::catalogue.providers, to_jsonb(p) || jsonb_build_object('id', v_prov, 'canonical_name', 'Fixture Deakin-like University',
         'display_name', 'Fixture Deakin-like University', 'stable_key', 'provider:au:fixture:deakinlike'))).* from catalogue.providers p where p.id = v_src_prov;
  -- the approved calendar, read before calendar-v2.1: periods with months, years and quotes but no `starts`
  v_prop := public.fixture_calendar_for(v_prov, 'https://leadership.fixture-deakin.example/academic-calendars', 'ai:gpt-4.1-mini', jsonb_build_object('scope', 'main_teaching', 'periods', jsonb_build_array(
    jsonb_build_object('period', 'trimester 1', 'months', jsonb_build_array(3), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array('Trimester 1: 8 Mar - 4 Jun ' || y0)),
    jsonb_build_object('period', 'trimester 2', 'months', jsonb_build_array(7), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array('Trimester 2: 12 Jul - 8 Oct ' || y0)),
    -- the production quote: a teaching period that STARTS on 1 November and ENDS in January of the next year; the reader's own years are the start years
    jsonb_build_object('period', 'trimester 3', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0 - 1, y0), 'quotes', jsonb_build_array('Trimester 3: 1 Nov - 28 Jan ' || (y0 + 1))),
    jsonb_build_object('period', 'trimester 5', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0 - 1), 'quotes', jsonb_build_array('Trimester 5: 1 Nov - 28 Jan ' || (y0 + 1))),
    jsonb_build_object('period', 'trimester 6', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0 + 2), 'quotes', jsonb_build_array('Trimester 6: 1 Nov ' || (y0 + 2) || ' - 28 Jan ' || (y0 + 3))),
    jsonb_build_object('period', 'trimester 7', 'months', jsonb_build_array(1), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array('Trimester 7: 5 Jan - 30 Mar ' || y0)),
    jsonb_build_object('period', 'trimester 8', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0, y0 + 1), 'quotes', jsonb_build_array('Trimester 8: 1 Nov ' || y0 || ' - 28 Jan ' || (y0 + 1))),
    jsonb_build_object('period', 'trimester 9', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array(y0 || ' teaching dates - Trimester 9: 1 Nov - 28 Jan')),
    -- ACU-like (weekday before the end date) and Torrens-like (a table row: the year printed after several dates)
    jsonb_build_object('period', 'research term 4', 'months', jsonb_build_array(10), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array('Mon 4 Oct - Sun 2 Jan ' || (y0 + 1))),
    jsonb_build_object('period', 'main intake 4', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0 + 1), 'quotes', jsonb_build_array('Main intake 4** | 02 Nov | 20 Nov | 07 Feb ' || (y0 + 1))),
    -- calendar-v2.1 shape (a `starts` array with its own year): unchanged by the fix
    jsonb_build_object('period', 'trimester 10', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array('Trimester 10: 1 Nov ' || y0),
       'starts', jsonb_build_array(jsonb_build_object('year', y0, 'month', 11, 'day', 1, 'date', null, 'quote', 'Trimester 10: 1 Nov ' || y0, 'meaning', 'teaching_start')), 'deadlines', '[]'::jsonb))));
  insert into public.dk_cases(name, provider_id, proposal_id, y0) values ('calendar', v_prov, v_prop, y0);
end $$;

-- the courses (a page's intake wording is what the plan reads): same stored shape as the fairness fixture's cloned courses
do $$
declare v_prov uuid := (select provider_id from public.dk_cases where name = 'calendar'); v_src uuid;
        r record; v_int uuid; v_course uuid; n int := 0;
begin
  select i.id into v_src from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where c.provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508' and i.evidence_id is not null and i.status = 'active' order by i.id limit 1;
  for r in select * from (values
    ('cA', 'Intakes Trimesters 1, 2, 3'), ('cB', 'Intakes Trimesters 1, 2, 3'), ('cC', 'Intakes Trimesters 1, 2, 3'), ('cD', 'Intakes Trimesters 1, 2, 3'),   -- written by the old job
    ('cN', 'Intakes Trimesters 1, 2, 3'), ('cRej', 'Intakes Trimesters 1, 2, 3'),                                                                          -- eligible, not yet written
    ('c12', 'Intakes Trimesters 1, 2'),                                                                                                                   -- November is not a Trimester 1 or 2 start
    ('cNone', 'Study with us. Apply now'),                                                                                                                -- names no study period
    ('cRef', 'Student story: I commenced Trimester 3 2023 and loved it'),                                                                                  -- a personal account is not an offering
    ('cFar', 'Intakes Trimester 6')) t(name, wording)
  loop
    v_int := public.fixture_clone_intake(v_src, 'November', r.wording);
    select course_id into v_course from catalogue.course_intakes where id = v_int;
    update catalogue.courses set provider_id = v_prov where id = v_course;
    n := n + 1;
    insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, country_code, course_stable_key, intake_options)
    select c.id, v_prov, '6cc98ba2-045f-e409-8d24-356d14447085', 'Fixture Deakin-like University', c.canonical_title, lower(c.canonical_title), to_tsvector('simple', c.canonical_title), 'published', 'AU',
           'course:cricos:fixturedk:' || lpad(n::text, 3, '0'), '[]'::jsonb from catalogue.courses c where c.id = v_course;
    insert into public.dk_cases(name, intake_id, course_id, provider_id, y0) values (r.name, v_int, v_course, v_prov, public.fixture_dk_y0());
  end loop;
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(course_id) from public.dk_cases where course_id is not null), true);
end $$;

-- settings as production (8 Nov 2026): named-period lists on, the unique-month path off, the job on
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.name_period_lists';
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';

-- 1 the defect, in the resolver ----------------------------------------------------------------------------------------------------------
do $$
declare y0 int := public.fixture_dk_y0(); v_prop uuid := (select proposal_id from public.dk_cases where name = 'calendar'); d record; f text := '';
begin
  select * into d from security.calendar_proposal_dates_v1(v_prop) where period = 'trimester 3' and kind = 'start';
  if d.on_date is distinct from make_date(y0 + 1, 11, 1) then raise exception 'the defect did not reproduce: "Trimester 3: 1 Nov - 28 Jan %" resolved to % (production gives %-11-01)', y0 + 1, d.on_date, y0 + 1; end if;
  select * into d from security.calendar_proposal_dates_v1(v_prop) where period = 'main intake 4' and kind = 'start';
  if d.year is distinct from y0 + 1 then raise exception 'table-row defect did not reproduce: %', d.year; end if;
  select * into d from security.calendar_proposal_dates_v1(v_prop) where period = 'research term 4' and kind = 'start';
  if d.on_date is distinct from make_date(y0 + 1, 10, 4) then raise exception 'ACU-like defect did not reproduce: %', d.on_date; end if;
  raise notice 'PASS defect (resolver): "Trimester 3: 1 Nov - 28 Jan %" is dated 1 November % (a year late); the Torrens-like table row takes the year printed after its LAST date; the ACU-like range is a year late', y0 + 1, y0 + 1;
end $$;

-- 2 the defect, in the job: the production code path writes the wrong date ----------------------------------------------------------------
do $$
declare y0 int := public.fixture_dk_y0(); v jsonb; r record; f text := ''; v_courses uuid[] := (select array_agg(course_id) from public.dk_cases where name in ('cA', 'cB', 'cC', 'cD'));
begin
  v := security.intake_dates_apply_v1(100, v_courses);
  for r in select k.name, i.start_date, i.intake_year, d.outcome, d.rule from public.dk_cases k join catalogue.course_intakes i on i.id = k.intake_id join pipeline.course_intake_dates d on d.intake_id = k.intake_id
            where k.name in ('cA', 'cB', 'cC', 'cD') loop
    if not (r.outcome = 'filled' and r.rule = 'calendar-v3' and r.start_date = make_date(y0 + 1, 11, 1) and r.intake_year = y0 + 1) then f := f || ' ' || row_to_json(r)::text; end if;
  end loop;
  if f <> '' then raise exception 'the job did not write the wrong date:%', f; end if;
  -- the other courses on the production plan (read only): the old plan fills a far period and an unproven one as well
  if (select p.new_start from security.intake_dates_plan_v3(array[(select course_id from public.dk_cases where name = 'cFar')], 10) p) is distinct from make_date(y0 + 2, 11, 1) then
    raise exception 'old plan: far period'; end if;
  raise notice 'PASS defect (job): the production job wrote 1 November % (intake year %) to four intakes whose course page says "Intakes Trimesters 1, 2, 3" (rule calendar-v3, the quote "Trimester 3: 1 Nov - 28 Jan %")', y0 + 1, y0 + 1, y0 + 1;
end $$;
-- the course-specific gate was passed legitimately: the page does name Trimester 3 as its own intake; the courses that do not were refused before the fix as well
do $$
declare r record; f text := '';
begin
  for r in select k.name, p.outcome, p.reason from public.dk_cases k, lateral security.intake_dates_plan_v3(array[k.course_id], 10) p where k.name in ('c12', 'cNone', 'cRef') loop
    if r.outcome <> 'skipped' then f := f || ' ' || r.name || ' ' || coalesce(r.reason, ''); end if;
  end loop;
  if f <> '' then raise exception 'course-specific eligibility (before): %', f; end if;
  raise notice 'PASS eligibility (before): a page that lists only Trimesters 1 and 2, names no period, or is a personal account is refused by the production gate; the contaminated four were eligible (the page names Trimester 3)';
end $$;

-- 3 the stored Website and Zoho items, written by the production scans, carry the wrong date -------------------------------------------------
do $$
declare v_y0 int := public.fixture_dk_y0(); v jsonb; n int;
begin
  v := security.website_sync_check_v1(100000);
  v := security.zoho_sync_check_v1(100000);
  select count(*) into n from public.dk_cases k join pipeline.website_sync_items w on w.entity = 'course' and w.ref_id = k.course_id and w.removed_at is null,
         jsonb_array_elements(w.item->'intakes') e where k.name in ('cA', 'cB', 'cC', 'cD') and e->>'start_date' = make_date(v_y0 + 1, 11, 1)::text;
  if n <> 4 then raise exception 'stored Website items with the wrong date: % (expected 4)', n; end if;
  select count(*) into n from public.dk_cases k join pipeline.zoho_sync_items z on z.entity = 'course' and z.ref_id = k.course_id and z.removed_at is null,
         jsonb_array_elements(z.item->'intakes') e where k.name in ('cA', 'cB', 'cC', 'cD') and e->>'start_date' = make_date(v_y0 + 1, 11, 1)::text;
  if n <> 4 then raise exception 'stored Zoho items with the wrong date: % (expected 4)', n; end if;
  raise notice 'PASS defect (projections): the production scans stored 1 November % in the Website items and in the Zoho items of the four courses', v_y0 + 1;
end $$;

-- the production resolver's output for the whole reading, kept so cases-after.sql can show that only the intended quotes changed
create table public.dk_old_dates as
select d.period, d.kind, d.year, d.month, d.day, d.on_date, d.quote from security.calendar_proposal_dates_v1((select proposal_id from public.dk_cases where name = 'calendar')) d;
