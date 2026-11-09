-- Guards: F-INT (valid course intake dates; data population mandate 9 Nov 2026), defects D3 and D2 BEFORE migration 20261109040000, on the production definitions:
--   D3  a row held for evidence (evidence_ambiguous, reader_correction_needed) has no revisit time, so it is never looked at again;
--   D2  a course page read again with new intake wording (same evidence id) is not queued again, because the fingerprint does not hold the wording.
-- Everything is written by the production job code (security.intake_dates_apply_v1). Dates are relative to the clock (the next 1 November) so the test does not age.
\set ON_ERROR_STOP on
\set QUIET on

-- the fixture's event numbering is brought past its rows (the production sequence is never behind its table)
do $$ begin perform setval(pg_get_serial_sequence('pipeline.course_intake_date_events', 'id'), greatest((select coalesce(max(id), 1) from pipeline.course_intake_date_events), 1)); end $$;

create table if not exists public.sd_cases (name text primary key, intake_id uuid, course_id uuid, provider_id uuid, proposal_id uuid, y0 int);

-- the university: a copy of the fixture's first university, with an approved calendar in the calendar-v2.1 shape (one dated start: Trimester 3, 1 November)
do $$
declare v_prov uuid := gen_random_uuid(); v_src_prov uuid := '08609bcf-387d-1316-2a52-9fbc0edff508'; v_prop uuid; y0 int := public.fixture_dk_y0();
begin
  insert into catalogue.providers select (jsonb_populate_record(null::catalogue.providers, to_jsonb(p) || jsonb_build_object('id', v_prov, 'canonical_name', 'Fixture Self-driving University',
         'display_name', 'Fixture Self-driving University', 'stable_key', 'provider:au:fixture:selfdriving'))).* from catalogue.providers p where p.id = v_src_prov;
  v_prop := public.fixture_calendar_for(v_prov, 'https://leadership.fixture-selfdriving.example/academic-calendars', 'ai:gpt-4.1-mini:calendar-v2.1', jsonb_build_object('scope', 'main_teaching', 'periods', jsonb_build_array(
    jsonb_build_object('period', 'trimester 3', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0), 'quotes', jsonb_build_array('Trimester 3: 1 Nov ' || y0),
       'starts', jsonb_build_array(jsonb_build_object('year', y0, 'month', 11, 'day', 1, 'date', null, 'quote', 'Trimester 3: 1 Nov ' || y0, 'meaning', 'teaching_start')), 'deadlines', '[]'::jsonb))));
  insert into public.sd_cases(name, provider_id, proposal_id, y0) values ('calendar', v_prov, v_prop, y0);
end $$;

-- the courses (a page's intake wording is what the plan reads)
do $$
declare v_prov uuid := (select provider_id from public.sd_cases where name = 'calendar'); v_src uuid; r record; v_int uuid; v_course uuid; n int := 0;
begin
  select i.id into v_src from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where c.provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508' and i.evidence_id is not null and i.status = 'active' order by i.id limit 1;
  for r in select * from (values
    ('sAmb1', 'Study with us. Apply now'),              -- names no study period: held, evidence ambiguous
    ('sAmb2', 'Intakes Trimesters 1, 2'),               -- November is not a Trimester 1 or 2 start: held, evidence ambiguous
    ('sPage', 'Intakes Trimesters 1, 2'),               -- held, then its page is read again and now says Trimester 3 (D2)
    ('sSame', 'Intakes Trimesters 1, 2'),               -- held, then its page is read again with the same wording (D2: no new look)
    ('sNoRead', null),                                  -- no stored reading of the page: held, reader correction needed
    ('sElig', 'Intakes Trimesters 1, 2, 3'),            -- eligible, not yet decided (fill regression, before and after)
    ('sRej', 'Intakes Trimesters 1, 2, 3'),             -- eligible; a person rejects the calendar value
    ('sWd', 'Intakes Trimesters 1, 2, 3'),              -- eligible; filled, then withdrawn by a person
    ('sLock', 'Intakes Trimesters 1, 2, 3'),            -- eligible; locked by hand
    ('sMY', 'Start dates: November ' || public.fixture_dk_y0() || ' intake')) t(name, wording)  -- the page prints a month followed by a year (22P02 on the production gate; reached on the month-only path)
  loop
    v_int := public.fixture_clone_intake(v_src, 'November', r.wording);
    select course_id into v_course from catalogue.course_intakes where id = v_int;
    update catalogue.courses set provider_id = v_prov where id = v_course;
    n := n + 1;
    insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, country_code, course_stable_key, intake_options)
    select c.id, v_prov, '6cc98ba2-045f-e409-8d24-356d14447085', 'Fixture Self-driving University', c.canonical_title, lower(c.canonical_title), to_tsvector('simple', c.canonical_title), 'published', 'AU',
           'course:cricos:fixturesd:' || lpad(n::text, 3, '0'), '[]'::jsonb from catalogue.courses c where c.id = v_course;
    insert into public.sd_cases(name, intake_id, course_id, provider_id, y0) values (r.name, v_int, v_course, v_prov, public.fixture_dk_y0());
  end loop;
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(course_id) from public.sd_cases where course_id is not null), true);
end $$;

-- settings as production (9 Nov 2026): named-period lists on, the unique-month path off, the job on, 14 days
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.name_period_lists';
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';

-- the wording that the eligible-course plan result is compared on, after the migration
create table public.sd_plan_before as
select p.new_year, p.new_start, p.new_deadline, p.outcome, p.reason, p.start_precision, p.deadline_kind, p.start_quote, p.periods, p.next_action
  from security.intake_dates_plan_v3(array[(select course_id from public.sd_cases where name = 'sElig')], 10) p;

-- 1 the production job decides the held courses -------------------------------------------------------------------------------------------------
do $$
declare v jsonb; r record; f text := ''; n int;
begin
  v := security.intake_dates_apply_v1(100, (select array_agg(course_id) from public.sd_cases where name in ('sAmb1', 'sAmb2', 'sPage', 'sSame', 'sNoRead')));
  for r in select k.name, d.outcome, d.next_action, d.next_revisit_at, d.deterministic, d.failure_class, d.inputs_fp from public.sd_cases k join pipeline.course_intake_dates d on d.intake_id = k.intake_id
            where k.name in ('sAmb1', 'sAmb2', 'sPage', 'sSame', 'sNoRead') loop
    if r.outcome <> 'skipped' or r.inputs_fp is null then f := f || ' ' || r.name || ' not held: ' || row_to_json(r)::text; end if;
    if r.name <> 'sNoRead' and r.next_action <> 'evidence_ambiguous' then f := f || ' ' || r.name || ' next_action ' || r.next_action; end if;
    if r.name = 'sNoRead' and r.next_action <> 'reader_correction_needed' then f := f || ' sNoRead next_action ' || r.next_action; end if;
    -- D3 defect: deterministic, no revisit time
    if not r.deterministic or r.next_revisit_at is not null then f := f || ' ' || r.name || ' has a revisit time before the fix: ' || row_to_json(r)::text; end if;
  end loop;
  if f <> '' then raise exception 'before (D3):%', f; end if;
  raise notice 'PASS defect D3: the production job holds the courses as evidence_ambiguous (the page names no period, or not this month) and reader_correction_needed (no stored reading); each is a deterministic failure and next_revisit_at is null, so it is never looked at again';
end $$;

-- 2 the two held pages are read again: sPage with new intake wording, sSame with the same wording ------------------------------------------------------
do $$
declare p record; n int; k record;
begin
  -- the stored reading of the page changes: new wording for sPage; for sSame the page is read again and says the same
  update pipeline.coverage_course_pages g set candidates = g.candidates || jsonb_build_object('intake_context', jsonb_build_array('Intakes Trimesters 1, 2, 3')), read_at = clock_timestamp() + interval '1 second'
   where g.course_id = (select course_id from public.sd_cases where name = 'sPage');
  update pipeline.coverage_course_pages g set read_at = clock_timestamp() + interval '1 second' where g.course_id = (select course_id from public.sd_cases where name = 'sSame');
  select count(*) into n from security.intake_dates_plan_v3((select array_agg(course_id) from public.sd_cases where name in ('sPage', 'sSame', 'sAmb1', 'sAmb2', 'sNoRead')), 100);
  if n <> 0 then raise exception 'D2 defect did not reproduce: % rows queued', n; end if;
  raise notice 'PASS defect D2: sPage was read again and its intake wording now names Trimester 3, yet the plan queues nothing (the fingerprint holds the calendar set, evidence id, course URL and settings, not the wording)';
end $$;

-- 3 what the migration must not touch: every decision as it stands before it (revisit time, fingerprint, next action) ----------------------------------
create table public.sd_state_before as select intake_id, next_action, next_revisit_at, inputs_fp, applied_at from pipeline.course_intake_dates;

-- 4 the latent defect of security.intake_course_applicability_v1: a month followed by a year raises 22P02 (md5 d3789be9 = production) ---------------------------------
create table public.sd_appl_inputs (n int primary key, raw text, month int, year int, month_only boolean, periods text[], ptxt text);
insert into public.sd_appl_inputs(n, raw, month, year, month_only, periods, ptxt) values
  (1, 'Start dates: February 2027 intake', 2, 2027, false, null, null),
  (2, 'Start dates 25 January 2027 for international students', 1, 2027, false, null, null),
  (3, 'Intakes: May 2027, September 2027', 5, 2027, false, null, null),
  (4, 'Start dates: February 2023 intake', 2, 2027, false, null, null),
  (5, 'Intakes Trimesters 1, 2, 3', 11, 2027, false, null, null),
  (6, 'Intakes: February, July, November', 7, 2027, false, null, null),
  (7, 'Study with us. Apply now', 11, 2027, false, null, null),
  (8, 'Students may start in July. Semester 1 intake', 7, 2027, false, null, null),
  (9, 'I commenced Trimester 3 2023 and loved it', 11, 2027, false, array['trimester 3'], 'i commenced trimester 3 2023 and loved it'),
  (10, 'Trimester 3 intake', 11, 2027, false, array['trimester 3'], 'trimester 3 intake'),
  (11, 'Intakes: January, May and September', 9, 2027, true, null, null),
  (12, 'Next intake is in March. Applications open all year', 3, 2027, false, null, null);
create or replace function public.sd_appl(p_n int) returns text language plpgsql as $f$
declare i public.sd_appl_inputs;
begin
  select * into i from public.sd_appl_inputs where n = p_n;
  return coalesce(security.intake_course_applicability_v1(i.raw, i.month, i.year, '[]'::jsonb, i.month_only, i.periods, i.ptxt), '<offered>');
exception when others then return 'ERROR ' || sqlstate;
end $f$;
create table public.sd_appl_before as select n, public.sd_appl(n) result from public.sd_appl_inputs;
do $$
declare f text := ''; r record;
begin
  for r in select * from public.sd_appl_before where n in (1, 2, 3, 4) loop
    if r.result <> 'ERROR 22P02' then f := f || ' input ' || r.n || ' gave ' || r.result; end if;
  end loop;
  if exists (select 1 from public.sd_appl_before where n not in (1, 2, 3, 4) and result like 'ERROR%') then f := f || ' other inputs raise'; end if;
  -- the plan: the course whose page prints "November <year> intake" stops the job on the production code
  -- (the named-period path never reads a month with its year; the month-only path, setting intake_dates.month_unique_match, and any generic offering check do)
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  begin
    perform * from security.intake_dates_plan_v3(array[(select course_id from public.sd_cases where name = 'sMY')], 10);
    f := f || ' the plan did not raise for sMY';
  exception when sqlstate '22P02' then null;
  end;
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  if f <> '' then raise exception 'applicability defect did not reproduce:%', f; end if;
  raise notice 'PASS defect (applicability): "Start dates: February 2027 intake", "Start dates 25 January 2027 ...", "Intakes: May 2027, September 2027" and "February 2023" each raise 22P02 (invalid input syntax for type integer: "february") in security.intake_course_applicability_v1, and the plan raises it on the month-only path for a course whose page prints "November <year> intake"; the 8 other inputs return a result';
end $$;
