-- Intake dates fixtures (CF-247, Platform Admin 2 Nov 2026 11:10 §2 and 11:18): intake year, exact start date and application deadline from the
-- university's approved calendar, and the chain stored reading -> intake row -> search projection -> consumer API intake objects.
-- Each case raises a notice "PASS ..." or stops with an error. Years are relative to today (Y this year, N next year, L last year), so the
-- fixtures never age. The calendar of provider "harbour" is the real parser's reading of calendar.md (passed in by run.sh as :cal); the
-- calendar of provider "bay" was approved before calendar-dates-v1 (months and quotes only). No live data.
\set ON_ERROR_STOP 1
create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAIL %', p_what; end if; end $f$;
create function pg_temp.u(p text) returns uuid language sql immutable as $f$ select md5(p)::uuid $f$;
create function pg_temp.y(p int) returns int language sql stable as $f$ select extract(year from (now() at time zone 'Australia/Melbourne'))::int + p $f$;
-- a course with its own proved page (bound, read, code in the address and the title) and an intake row read from that page
create function pg_temp.course(p_key text, p_prov text, p_host text, p_code text, p_title text) returns void language plpgsql as $f$
declare v_url text := 'https://www.' || p_host || '/study/' || lower(replace(p_title, ' ', '-')) || '-' || lower(p_code);
begin
  insert into catalogue.courses(id, provider_id, canonical_title, course_code, study_level_id)
  values (pg_temp.u(p_key), pg_temp.u(p_prov), p_title, p_code, (select id from ref.study_levels where code = 'masters_coursework'));
  insert into search.course_documents(course_id, country_code) values (pg_temp.u(p_key), 'AU');
  insert into pipeline.evidence_artifacts(id, storage_path, source_url) values (pg_temp.u('ev ' || p_key), 'snap/' || md5(p_key) || '.html.gz', v_url);
  alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id, candidates)
  values (pg_temp.u(p_key), pg_temp.u(p_prov), v_url, 'cricos_search', 'bound', 'read', 'cricos_code', pg_temp.u('ev ' || p_key),
          jsonb_build_object('page_title', p_title || ' (' || p_code || ') | ' || (select canonical_name from catalogue.providers where id = pg_temp.u(p_prov)), 'final_url', v_url));
  alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
end $f$;
create function pg_temp.intake(p_key text, p_month text, p_year int default null, p_page text default null) returns uuid language sql as $f$
  insert into catalogue.course_intakes(course_id, intake_year, intake_label, status, source_id, evidence_id, confidence, source_intake_key)
  values (pg_temp.u(p_key), p_year, p_month, 'active', pg_temp.u('sweep'), pg_temp.u('ev ' || coalesce(p_page, p_key)), 1,
          p_key || ':' || coalesce(p_year::text, 'current') || ':' || lower(p_month)) returning id $f$;
create function pg_temp.row(p_key text, p_month text) returns catalogue.course_intakes language sql as $f$
  select * from catalogue.course_intakes where course_id = pg_temp.u(p_key) and intake_label = p_month and status = 'active' $f$;
create function pg_temp.rec(p_key text, p_month text) returns pipeline.course_intake_dates language sql as $f$
  select d.* from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id where i.course_id = pg_temp.u(p_key) and i.intake_label = p_month $f$;
create function pg_temp.switch(p_on boolean) returns void language sql as $f$
  update pipeline.platform_toolset_settings set value = to_jsonb(p_on) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled' $f$;

-- providers, sources, gates ------------------------------------------------------------------------------------------------------------
insert into ref.countries(id, iso_alpha2) values (pg_temp.u('AU'), 'AU');
insert into pipeline.coverage_admission_countries values (pg_temp.u('AU'), true, 'AUD');
insert into catalogue.providers(id, canonical_name, website, country_id) values
  (pg_temp.u('harbour'), 'Harbour University', 'https://www.harbour.edu.au', pg_temp.u('AU')),
  (pg_temp.u('bay'), 'Bay University', 'https://www.bay.edu.au', pg_temp.u('AU')),
  (pg_temp.u('nocal'), 'Inland University', 'https://www.inland.edu.au', pg_temp.u('AU'));
insert into pipeline.sources(id, source_type, provider_id, label) values (pg_temp.u('sweep'), 'provider_course_page_sweep', null, 'course pages (coverage sweep)');
insert into search.enrichment_gates values ('courses', 'course_intake', 'approved');
insert into search.enrichment_source_gates values ('courses', 'course_intake', pg_temp.u('sweep'), 'approved');

-- the stored readings: Harbour's calendar as the parser reads it now (calendar-dates-v1), approved by a person; Bay's approved before it
insert into pipeline.provider_policy_proposals(id, provider_id, kind, parser, url, proposal, status, decided_at)
values (pg_temp.u('cal harbour'), pg_temp.u('harbour'), 'intake_calendar', 'provider-policy-v0.2.5', 'https://www.harbour.edu.au/calendar', :'cal'::jsonb, 'approved', now());
insert into pipeline.provider_policy_proposals(id, provider_id, kind, parser, url, proposal, status, decided_at)
select pg_temp.u('cal bay'), pg_temp.u('bay'), 'intake_calendar', 'provider-policy-v0.2.2', 'https://www.bay.edu.au/key-dates',
       jsonb_build_object('parser', 'provider-policy-v0.2.2', 'periods', jsonb_build_array(
         -- as live: the approved Semester 1 also lists July, from a supplementary exams row
         jsonb_build_object('period', 'semester 1', 'months', '[3, 7]'::jsonb, 'years', jsonb_build_array(pg_temp.y(1)),
                            'quotes', jsonb_build_array(format('2 March %s | Semester 1 commences', pg_temp.y(1)), format('Supplementary exams start from | Tuesday 8 July %s', pg_temp.y(1)))),
         jsonb_build_object('period', 'semester 2', 'months', '[2]'::jsonb, 'years', '[]'::jsonb, 'quotes', '["Start date | Monday 16 February"]'::jsonb),
         -- as live: a day range, so the day is not certain (year only)
         jsonb_build_object('period', 'term 1', 'months', '[1]'::jsonb, 'years', jsonb_build_array(pg_temp.y(1)),
                            'quotes', jsonb_build_array(format('Term 1 | 18 – 20 January %s | 25 January %s | 9 April %s', pg_temp.y(1), pg_temp.y(1), pg_temp.y(1)))))),
       'approved', now();

-- courses: every one with its own proved page; the intake row is read from that page unless said otherwise ---------------------------------
select pg_temp.course('exact', 'harbour', 'harbour.edu.au', 'MC271', 'Master of Data Science'),
       pg_temp.course('monthonly', 'harbour', 'harbour.edu.au', 'MC272', 'Master of Public Health'),
       pg_temp.course('rolling', 'harbour', 'harbour.edu.au', 'MC273', 'Master of Urban Planning'),
       pg_temp.course('past', 'harbour', 'harbour.edu.au', 'MC274', 'Master of Marine Science'),
       pg_temp.course('locked', 'harbour', 'harbour.edu.au', 'MC275', 'Master of Social Work'),
       pg_temp.course('refused', 'harbour', 'harbour.edu.au', 'MC276', 'Master of Architecture'),
       pg_temp.course('sibling', 'harbour', 'harbour.edu.au', 'GD277', 'Graduate Diploma of Teaching'),
       pg_temp.course('heldby', 'harbour', 'harbour.edu.au', 'MC278', 'Master of Teaching'),
       pg_temp.course('oldshape', 'bay', 'bay.edu.au', 'MC301', 'Master of Engineering'),
       pg_temp.course('nocal', 'nocal', 'inland.edu.au', 'MC401', 'Master of Nursing');
select pg_temp.intake('exact', 'March'), pg_temp.intake('exact', 'July'), pg_temp.intake('monthonly', 'November'),
       pg_temp.intake('rolling', 'July'), pg_temp.intake('past', 'March', pg_temp.y(-1)), pg_temp.intake('locked', 'March'),
       pg_temp.intake('refused', 'March'), pg_temp.intake('sibling', 'March', null, 'heldby'),
       pg_temp.intake('oldshape', 'March'), pg_temp.intake('oldshape', 'February'), pg_temp.intake('oldshape', 'July'), pg_temp.intake('oldshape', 'January'), pg_temp.intake('nocal', 'March');
-- a person locked Social Work's intakes; Architecture's page was refused for it; the Graduate Diploma's month came from the Master's page
insert into pipeline.manual_locks values ('course', pg_temp.u('locked'), 'intakes');
insert into pipeline.page_rejections(course_id, url, provider_id, source, reason, signals)
select pg_temp.u('refused'), source_url, pg_temp.u('harbour'), 'layer4', 'not this course', '{}'::jsonb from pipeline.evidence_artifacts where id = pg_temp.u('ev refused');

-- 1. the stored readings hold the dated periods -----------------------------------------------------------------------------------------
do $$
begin
  perform pg_temp.ok((select count(*) from security.calendar_dated_periods_v1(pg_temp.u('harbour')) s
                       where s.kind = 'start' and s.period = 'semester 1' and s.on_date = make_date(pg_temp.y(1), 3, 1)) = 1, 'parser start with day and year');
  perform pg_temp.ok((select count(*) from security.calendar_dated_periods_v1(pg_temp.u('harbour')) s
                       where s.kind = 'deadline' and s.period = 'semester 1' and s.on_date = make_date(pg_temp.y(0), 11, 30)) = 1, '"applications close" row read as the deadline');
  perform pg_temp.ok((select count(*) from security.calendar_dated_periods_v1(pg_temp.u('harbour')) s
                       where s.kind = 'rolling' and s.period = 'semester 2' and s.rolling_text like '%Rolling, until places are filled%' and s.on_date is null) = 1, 'rolling deadline kept as text, no date');
  perform pg_temp.ok((select bool_and(s.year is null and s.on_date is null and s.day = 2) from security.calendar_dated_periods_v1(pg_temp.u('harbour')) s
                       where s.kind = 'start' and s.period = 'trimester 3'), 'a day with no printed year: year and date stay empty');
  perform pg_temp.ok((select count(*) from security.calendar_dated_periods_v1(pg_temp.u('harbour')) s where s.kind = 'start' and s.month = 6) = 0, 'exams are not a start');
  perform pg_temp.ok((select count(*) from security.calendar_dated_periods_v1(pg_temp.u('bay')) s
                       where s.kind = 'start' and s.on_date = make_date(pg_temp.y(1), 3, 2)) = 1, 'approved before calendar-dates-v1: the stored quote gives the day and year');
  perform pg_temp.ok((select bool_and(s.year is null and s.on_date is null) from security.calendar_dated_periods_v1(pg_temp.u('bay')) s where s.period = 'semester 2'), 'stored quote with no year: month only');
  perform pg_temp.ok((select count(*) from security.calendar_dated_periods_v1(pg_temp.u('bay')) s where s.month = 7) = 0, 'a stored exams row is never a start date');
  raise notice 'PASS stored readings: dated starts, deadlines, rolling text, month-only';
end $$;

-- 2. off by default: nothing changes while the switch is off; the job is paused --------------------------------------------------------
do $$
declare v jsonb;
begin
  perform pg_temp.ok((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled') = 'false'::jsonb, 'setting off');
  perform pg_temp.ok((select not active from cron.job where jobname = 'intake-dates-apply'), 'job paused');
  perform pg_temp.ok((select command from cron.job where jobname = 'intake-dates-apply') = 'select security.intake_dates_apply_v1(security.pipeline_num_v1(''batch.intake_dates_apply'', 200)::int)', 'job size from a setting');
  perform pg_temp.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'intake-dates-apply'), 'job catalogued');
  v := security.intake_dates_apply_v1(null);
  perform pg_temp.ok(v = '{"enabled": false, "filled": 0}'::jsonb, 'off: does nothing');
  perform pg_temp.ok(not exists (select 1 from catalogue.course_intakes where intake_year is not null and intake_year <> pg_temp.y(-1) or start_date is not null or application_deadline is not null), 'off: no intake changed');
  perform pg_temp.ok(not exists (select 1 from pipeline.course_intake_dates), 'off: nothing recorded');
  raise notice 'PASS off by default';
end $$;

-- 3. the plan, then the apply with the switch on --------------------------------------------------------------------------------------
do $$
declare v jsonb; r pipeline.course_intake_dates;
begin
  perform pg_temp.switch(true);
  v := security.intake_dates_apply_v1(null);
  perform pg_temp.ok((v->>'filled')::int = 5 and (v->>'courses')::int = 3, 'filled 5 rows of 3 courses: ' || v::text);
  -- exact date and year kept, with the deadline
  perform pg_temp.ok((pg_temp.row('exact', 'March')).intake_year = pg_temp.y(1) and (pg_temp.row('exact', 'March')).start_date = make_date(pg_temp.y(1), 3, 1)
                     and (pg_temp.row('exact', 'March')).application_deadline = make_date(pg_temp.y(0), 11, 30), 'exact date, year and deadline');
  r := pg_temp.rec('exact', 'March');
  perform pg_temp.ok(r.outcome = 'filled' and r.start_precision = 'day' and r.deadline_kind = 'date' and r.periods = array['semester 1']
                     and r.start_quote like '1 March % | Semester 1 starts' and r.deadline_quote like '30 November % | Applications close for Semester 1', 'recorded with its quotes');
  raise notice 'PASS exact date and year kept';
  -- month-only stays month-only
  perform pg_temp.ok((pg_temp.row('monthonly', 'November')).intake_year is null and (pg_temp.row('monthonly', 'November')).start_date is null, 'month only stays month only');
  r := pg_temp.rec('monthonly', 'November');
  perform pg_temp.ok(r.outcome = 'skipped' and r.start_precision = 'month' and r.reason = 'the calendar prints no year for this month (month only)', 'month only: ' || coalesce(r.reason, 'no record'));
  raise notice 'PASS month-only stays month-only';
  -- rolling deadline marked, never a date
  perform pg_temp.ok((pg_temp.row('rolling', 'July')).intake_year = pg_temp.y(1) and (pg_temp.row('rolling', 'July')).start_date = make_date(pg_temp.y(1), 7, 26)
                     and (pg_temp.row('rolling', 'July')).application_deadline is null, 'rolling: start filled, no deadline date');
  r := pg_temp.rec('rolling', 'July');
  perform pg_temp.ok(r.deadline_kind = 'rolling' and r.deadline_text like '%Rolling, until places are filled%', 'rolling marked with its text');
  raise notice 'PASS rolling deadline marked';
  -- an "applications close" row became a deadline (Semester 1 only; Semester 2 has none)
  perform pg_temp.ok((pg_temp.row('exact', 'July')).application_deadline is null and (pg_temp.rec('exact', 'July')).deadline_kind = 'rolling', 'the deadline belongs to its own period');
  raise notice 'PASS an "applications close" row becomes a deadline';
  -- a past-year intake is not overwritten
  perform pg_temp.ok((pg_temp.row('past', 'March')).intake_year = pg_temp.y(-1) and (pg_temp.row('past', 'March')).start_date is null, 'past intake kept as history');
  perform pg_temp.ok((pg_temp.rec('past', 'March')).reason = 'the calendar prints no start in the intake''s own year', 'past: reason');
  raise notice 'PASS a past-year intake is not overwritten';
  -- manual lock respected
  perform pg_temp.ok((pg_temp.row('locked', 'March')).intake_year is null and (pg_temp.rec('locked', 'March')).reason = 'intakes locked by hand', 'lock respected');
  raise notice 'PASS manual lock respected';
  -- a refused page is not used; a page not proved to be the course's own (E16) is not used
  perform pg_temp.ok((pg_temp.row('refused', 'March')).intake_year is null and (pg_temp.rec('refused', 'March')).reason = 'page refused for this course', 'refused page');
  perform pg_temp.ok((pg_temp.row('sibling', 'March')).intake_year is null and (pg_temp.rec('sibling', 'March')).reason like 'page not proved to be the course''s own (E16 %', 'E16: ' || coalesce((pg_temp.rec('sibling', 'March')).reason, 'no record'));
  raise notice 'PASS a refused page is not used';
  -- the calendar approved before calendar-dates-v1: its stored quotes fill the year and date (backfill without re-reading)
  perform pg_temp.ok((pg_temp.row('oldshape', 'March')).start_date = make_date(pg_temp.y(1), 3, 2) and (pg_temp.row('oldshape', 'March')).application_deadline is null
                     and (pg_temp.rec('oldshape', 'March')).deadline_kind = 'not_stated', 'stored quote backfill');
  perform pg_temp.ok((pg_temp.row('oldshape', 'February')).intake_year is null, 'stored quote without a year stays month only');
  perform pg_temp.ok((pg_temp.row('oldshape', 'January')).intake_year = pg_temp.y(1) and (pg_temp.row('oldshape', 'January')).start_date is null
                     and (pg_temp.rec('oldshape', 'January')).start_precision = 'year', 'a day range gives the year only');
  perform pg_temp.ok((pg_temp.row('oldshape', 'July')).intake_year is null and (pg_temp.rec('oldshape', 'July')).reason = 'the calendar has no start in this month', 'exams row not used: ' || coalesce((pg_temp.rec('oldshape', 'July')).reason, 'no record'));
  -- no approved calendar: not looked at
  perform pg_temp.ok((pg_temp.rec('nocal', 'March')).intake_id is null and (pg_temp.row('nocal', 'March')).intake_year is null, 'no calendar, nothing');
  perform pg_temp.ok((select count(*) from public.fixture_refresh_calls) = 1, 'the search projection is refreshed once for the courses changed');
  raise notice 'PASS backfill from stored readings';
end $$;

-- 4. idempotent: a second run looks at nothing; a re-admission without a year keeps the dates; an older year never replaces a later one ------
do $$
declare v jsonb; h text;
begin
  h := (select md5(string_agg(i::text, ',' order by i.id)) from catalogue.course_intakes i);
  v := security.intake_dates_apply_v1(null);
  perform pg_temp.ok((v->>'looked_at')::int = 0 and (v->>'filled')::int = 0, 'second run: nothing to do: ' || v::text);
  perform pg_temp.ok(h = (select md5(string_agg(i::text, ',' order by i.id)) from catalogue.course_intakes i), 'second run: no intake changed');
  perform pg_temp.ok((select count(*) from security.intake_dates_plan_v1(null, null)) = 0, 'the plan is empty');
  -- the admission write sends the month again with no year (as every reader does today)
  perform security.coverage_apply_course_v1(pg_temp.u('exact'), pg_temp.u('sweep'), pg_temp.u('ev exact'), 'https://x', 'h',
    jsonb_build_object('intakes', jsonb_build_array(jsonb_build_object('intake_label', 'March', 'source_intake_key', 'exact:current:march'))));
  perform pg_temp.ok((pg_temp.row('exact', 'March')).intake_year = pg_temp.y(1) and (pg_temp.row('exact', 'March')).start_date = make_date(pg_temp.y(1), 3, 1)
                     and (pg_temp.row('exact', 'March')).application_deadline = make_date(pg_temp.y(0), 11, 30), 're-admission without a year keeps year, date and deadline');
  -- an older year sent for the same intake does not replace the later one
  perform security.coverage_apply_course_v1(pg_temp.u('exact'), pg_temp.u('sweep'), pg_temp.u('ev exact'), 'https://x', 'h',
    jsonb_build_object('intakes', jsonb_build_array(jsonb_build_object('intake_label', 'March', 'intake_year', pg_temp.y(-1), 'start_date', make_date(pg_temp.y(-1), 3, 3), 'source_intake_key', 'exact:current:march'))));
  perform pg_temp.ok((pg_temp.row('exact', 'March')).intake_year = pg_temp.y(1) and (pg_temp.row('exact', 'March')).start_date = make_date(pg_temp.y(1), 3, 1), 'an older year never replaces a later one');
  -- a later year printed by a source replaces it, with its own date, and the old deadline goes
  perform security.coverage_apply_course_v1(pg_temp.u('exact'), pg_temp.u('sweep'), pg_temp.u('ev exact'), 'https://x', 'h',
    jsonb_build_object('intakes', jsonb_build_array(jsonb_build_object('intake_label', 'March', 'intake_year', pg_temp.y(2), 'start_date', make_date(pg_temp.y(2), 3, 6), 'source_intake_key', 'exact:current:march'))));
  perform pg_temp.ok((pg_temp.row('exact', 'March')).intake_year = pg_temp.y(2) and (pg_temp.row('exact', 'March')).start_date = make_date(pg_temp.y(2), 3, 6)
                     and (pg_temp.row('exact', 'March')).application_deadline is null, 'a later year replaces, and the older deadline goes');
  -- put it back for the chain below
  update catalogue.course_intakes set intake_year = pg_temp.y(1), start_date = make_date(pg_temp.y(1), 3, 1), application_deadline = make_date(pg_temp.y(0), 11, 30)
   where id = (pg_temp.row('exact', 'March')).id;
  -- a new approved calendar: rows are looked at again (once), and only empty columns are filled
  insert into pipeline.provider_policy_proposals(id, provider_id, kind, parser, url, proposal, status, decided_at)
  select pg_temp.u('cal harbour 2'), provider_id, kind, parser, url, proposal, 'approved', now() + interval '1 second' from pipeline.provider_policy_proposals where id = pg_temp.u('cal harbour');
  v := security.intake_dates_apply_v1(null);
  perform pg_temp.ok((v->>'filled')::int = 0 and (v->>'looked_at')::int > 0, 'new calendar: looked at again, nothing overwritten: ' || v::text);
  v := security.intake_dates_apply_v1(null);
  perform pg_temp.ok((v->>'looked_at')::int = 0, 'new calendar: once');
  raise notice 'PASS the backfill is idempotent';
end $$;

-- 5. the chain: stored reading -> intake row -> search projection -> consumer API intake objects --------------------------------------------
-- The consumer API builds intakes[] in api.website_v2_course_item from search.course_documents.intake_options. The expression below is the
-- live one (md5 8f2a0ac921c4507673c1232cf2ecc8aa, read 2 Nov 2026), unchanged; s220 checks it is the repository's text.
create function pg_temp.api_intakes(d search.course_documents) returns jsonb language sql stable as $f$
  select coalesce((select jsonb_agg(distinct jsonb_build_object('label', i->>'label', 'month', api.website_v2_label_month(i->>'label'), 'year', i->'year',
                  'start_date', i->'start_date', 'application_deadline', i->'application_deadline'))
                 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null), '[]'::jsonb) $f$;
do $$
declare v jsonb; o jsonb; a jsonb;
begin
  -- the live projection stages the rows; its apply copies the intake columns into search.course_documents with exactly these three lines
  v := search.refresh_course_enrichment_core_scoped_v1(array[pg_temp.u('exact'), pg_temp.u('monthonly'), pg_temp.u('rolling')], false);
  update search.course_documents d set
      intake_options=s.intake_options,
      earliest_intake_date=s.earliest_intake_date,
      has_intake=(jsonb_array_length(s.intake_options)>0)
    from cf_search_enrichment_stage s where d.course_id=s.course_id;
  o := (select intake_options from search.course_documents where course_id = pg_temp.u('exact'));
  perform pg_temp.ok(o @> jsonb_build_array(jsonb_build_object('label', 'March', 'year', pg_temp.y(1), 'start_date', make_date(pg_temp.y(1), 3, 1), 'application_deadline', make_date(pg_temp.y(0), 11, 30))),
                     'projection: search.course_documents.intake_options carries year, start date and deadline: ' || coalesce(o::text, 'null'));
  perform pg_temp.ok((select earliest_intake_date from search.course_documents where course_id = pg_temp.u('exact')) = make_date(pg_temp.y(1), 3, 1), 'projection: earliest intake date');
  a := (select pg_temp.api_intakes(d) from search.course_documents d where d.course_id = pg_temp.u('exact'));
  perform pg_temp.ok(a @> jsonb_build_array(jsonb_build_object('label', 'March', 'month', 3, 'year', pg_temp.y(1), 'start_date', make_date(pg_temp.y(1), 3, 1)::text,
                                                               'application_deadline', make_date(pg_temp.y(0), 11, 30)::text)), 'API: intakes[] year, start_date, application_deadline: ' || a::text);
  a := (select pg_temp.api_intakes(d) from search.course_documents d where d.course_id = pg_temp.u('monthonly'));
  perform pg_temp.ok(a = jsonb_build_array(jsonb_build_object('label', 'November', 'month', 11, 'year', null, 'start_date', null, 'application_deadline', null)), 'API: month only stays null (not held)');
  a := (select pg_temp.api_intakes(d) from search.course_documents d where d.course_id = pg_temp.u('rolling'));
  perform pg_temp.ok(a = jsonb_build_array(jsonb_build_object('label', 'July', 'month', 7, 'year', pg_temp.y(1), 'start_date', make_date(pg_temp.y(1), 7, 26)::text, 'application_deadline', null)),
                     'API: rolling deadline is null, never text in a date field');
  -- the object keys are exactly today's (no shape change)
  perform pg_temp.ok((select array_agg(k order by k) from jsonb_object_keys(a->0) k) = array['application_deadline', 'label', 'month', 'start_date', 'year'], 'API: the same five keys');
  raise notice 'PASS chain: stored reading -> intake row -> search projection -> consumer API';
end $$;
