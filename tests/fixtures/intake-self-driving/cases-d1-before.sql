-- Guards: F-INT D1 (a start date printed on the course page is admitted only when corroborated; default off; Platform Admin data population mandate, 9 Nov 2026),
--   the setup and the baseline BEFORE migration 20261109042000, on the plan as it stands after 20261109040000 and 20261109041000.
-- Production-shaped universities (measured read-only 9 Nov 2026): Federation (P1: the page date is a start of the approved main calendar), Canberra (P2: the page
-- adapter reads international admissions only), Macquarie (P3: page only, audience unproven), Western Sydney-like (page adapter "Next Start Date", no dated calendar start),
-- Adelaide (a how-to-apply page behind the intake), Deakin (1 November 2028 rejected and withdrawn), and a university whose calendar is set aside (no calendar at all).
-- Every date is relative to the clock (the next 1 March, 26 July, 15 February, 9 August), so the cases do not age. Nothing here touches central.* settings.
\set ON_ERROR_STOP on
\set QUIET on

-- the production table has the adapter patterns the page reader uses (the fixture's stub holds four columns)
alter table pipeline.uni_adapters add column if not exists patterns jsonb;
do $$ begin perform setval(pg_get_serial_sequence('pipeline.course_intake_date_events', 'id'), greatest((select coalesce(max(id), 1) from pipeline.course_intake_date_events), 1)); end $$;

-- the year of the next day-month after next week (so a date is always in the future, inside the horizon, and never ages)
create or replace function public.sd_dy(p_month int, p_day int) returns int language sql stable as $f$
  select extract(year from (now() at time zone 'Australia/Melbourne'))::int
         + case when make_date(extract(year from (now() at time zone 'Australia/Melbourne'))::int, p_month, p_day) > (now() at time zone 'Australia/Melbourne')::date + 7 then 0 else 1 end $f$;

create table public.sd_d1 (name text primary key, intake_id uuid, course_id uuid, provider_id uuid, expect text, new_start date);
create table public.sd_d1_prov (name text primary key, provider_id uuid, proposal_id uuid);

-- a university: a copy of the fixture's first university, with an approved calendar (one period per start) and, when given, its page adapter
create or replace function public.sd_d1_prov(p_name text, p_url text, p_starts jsonb, p_adapter text default null) returns uuid language plpgsql as $f$
declare v_prov uuid := gen_random_uuid(); v_src uuid := '08609bcf-387d-1316-2a52-9fbc0edff508'; v_prop uuid;
begin
  insert into catalogue.providers select (jsonb_populate_record(null::catalogue.providers, to_jsonb(p) || jsonb_build_object('id', v_prov, 'canonical_name', 'Fixture D1 ' || p_name,
         'display_name', 'Fixture D1 ' || p_name, 'stable_key', 'provider:au:fixture:d1:' || lower(p_name)))).* from catalogue.providers p where p.id = v_src;
  v_prop := public.fixture_calendar_for(v_prov, p_url, 'ai:gpt-4.1-mini:calendar-v2.1', jsonb_build_object('scope', 'main_teaching', 'periods',
    (select jsonb_agg(jsonb_build_object('period', s->>'period', 'months', jsonb_build_array((s->>'m')::int), 'years', jsonb_build_array((s->>'y')::int),
                                          'quotes', jsonb_build_array((s->>'period') || ': ' || (s->>'d') || '/' || (s->>'m') || '/' || (s->>'y')),
                                          'starts', jsonb_build_array(jsonb_build_object('year', (s->>'y')::int, 'month', (s->>'m')::int, 'day', (s->>'d')::int, 'date', null,
                                                    'quote', (s->>'period') || ': ' || (s->>'d') || '/' || (s->>'m') || '/' || (s->>'y'), 'meaning', 'teaching_start')),
                                          'deadlines', '[]'::jsonb)) from jsonb_array_elements(p_starts) s)));
  if p_adapter is not null then insert into pipeline.uni_adapters(provider_id, enabled, admit, patterns) values (v_prov, true, false, jsonb_build_object('intakes', p_adapter)); end if;
  insert into public.sd_d1_prov values (p_name, v_prov, v_prop);
  return v_prov;
end $f$;

-- a course of that university: its intake month, its stored page wording (one item each), and the expected plan result with the switch on
create or replace function public.sd_d1_course(p_name text, p_prov text, p_label text, p_snips text[], p_expect text, p_start date default null, p_year int default null, p_url text default null) returns uuid language plpgsql as $f$
declare v_prov uuid := (select provider_id from public.sd_d1_prov where name = p_prov); v_src uuid; v_int uuid; v_course uuid; n int;
begin
  select i.id into v_src from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where c.provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508' and i.evidence_id is not null and i.status = 'active' order by i.id limit 1;
  v_int := public.fixture_clone_intake(v_src, p_label, 'x', p_year);
  select course_id into v_course from catalogue.course_intakes where id = v_int;
  update catalogue.courses set provider_id = v_prov where id = v_course;
  update pipeline.coverage_course_pages g set candidates = g.candidates || jsonb_build_object('intake_context', to_jsonb(p_snips)) where g.course_id = v_course;
  if p_url is not null then
    update pipeline.evidence_artifacts e set source_url = p_url where e.id = (select evidence_id from catalogue.course_intakes where id = v_int);
    update pipeline.coverage_course_pages g set url = p_url, candidates = g.candidates || jsonb_build_object('final_url', p_url) where g.course_id = v_course;
  end if;
  select count(*) + 1 into n from public.sd_d1;
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, country_code, course_stable_key, intake_options)
  select c.id, v_prov, '6cc98ba2-045f-e409-8d24-356d14447085', 'Fixture D1 ' || p_prov, c.canonical_title, lower(c.canonical_title), to_tsvector('simple', c.canonical_title), 'published', 'AU',
         'course:cricos:fixtured1:' || lpad(n::text, 4, '0'), '[]'::jsonb from catalogue.courses c where c.id = v_course;
  insert into public.sd_d1(name, intake_id, course_id, provider_id, expect, new_start) values (p_name, v_int, v_course, v_prov, p_expect, p_start);
  return v_course;
end $f$;

do $$
declare
  yA int := public.sd_dy(3, 1); yB int := public.sd_dy(7, 26); yF int := public.sd_dy(2, 15); yG int := public.sd_dy(8, 9); yC int := public.sd_dy(2, 22); y0 int := public.fixture_dk_y0();
  v_fed text := 'Start dates\s+((?:Anytime(?:.|\n){0,40}?)?\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)(?:.|\n){0,200}?)\s+Locations';
  v_can text := '(\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+20\d\d)\s+(?:(?:[A-Za-z]+\s+){1,3}for domestic admissions\s+)?Open for international admissions';
  v_mac text := 'Location and start dates\s+((?:.|\n){0,250}?)\s+(?:Summary|Overview|Entry requirements)';
  v_wsu text := 'Next Start Date\s*((?:\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+20\d\d\s*)+)';
  fed_a text := 'adapter pattern: 01 March ' || yA || ' 26 July ' || yB;                  -- Federation: the adapter's dates in the page's order
  fed_b text := 'Start dates 25 January ' || yA || ' 01 March ' || yA || ' 28 June ' || yA || ' 26 July ' || yB;
begin
  -- Federation (P1): an approved main calendar with semester 1 on 1 March, semester 2 on 26 July, and a pathway program starting 15 February
  perform public.sd_d1_prov('Federation', 'https://leadership.fixture-d1fed.example/key-dates', jsonb_build_array(
    jsonb_build_object('period', 'semester 1', 'y', yA, 'm', 3, 'd', 1), jsonb_build_object('period', 'semester 2', 'y', yB, 'm', 7, 'd', 26),
    jsonb_build_object('period', 'pathway program', 'y', yF, 'm', 2, 'd', 15)), v_fed);
  perform public.sd_d1_course('fMar', 'Federation', 'March', array[fed_a, fed_b], 'filled', make_date(yA, 3, 1));
  perform public.sd_d1_course('fJul', 'Federation', 'July', array[fed_a, fed_b], 'filled', make_date(yB, 7, 26));
  perform public.sd_d1_course('fJan', 'Federation', 'January', array[fed_a, fed_b], 'skipped');       -- 25 January is on the page only: P3
  perform public.sd_d1_course('fPath', 'Federation', 'February', array['Start dates: 15 February ' || yF], 'skipped');     -- equals a pathway start only: not corroboration
  perform public.sd_d1_course('fNoLabel', 'Federation', 'March', array['Come and see us on 1 March ' || yA || ' at the open day'], 'skipped');
  perform public.sd_d1_course('fRange', 'Federation', 'March', array['Start dates: 1-5 March ' || yA], 'skipped');
  perform public.sd_d1_course('fTwo', 'Federation', 'March', array['Start dates: 1 March ' || yA || ' and 15 March ' || yA], 'skipped');
  perform public.sd_d1_course('fNoYear', 'Federation', 'March', array['Start dates: 1 March at the main campus'], 'skipped');                -- no full date: the calendar route as before
  perform public.sd_d1_course('fClose', 'Federation', 'March', array['Applications close 1 March ' || yA || '. Study with us'], 'skipped');   -- a closing date is not a start
  perform public.sd_d1_course('fPast', 'Federation', 'March', array['Start dates: 1 March ' || (yA - 2)], 'skipped');
  perform public.sd_d1_course('fFar', 'Federation', 'March', array['Start dates: 1 March ' || (yA + 2)], 'skipped');
  perform public.sd_d1_course('fYear', 'Federation', 'March', array['Start dates: 1 March ' || (yA + 1)], 'skipped', null, yA);     -- the intake holds year yA, the page prints yA + 1
  perform public.sd_d1_course('fLock', 'Federation', 'March', array[fed_a, fed_b], 'skipped');
  perform public.sd_d1_course('fHold', 'Federation', 'July', array[fed_a, fed_b], 'skipped');
  -- Canberra (P2): the calendar has semester 1 on 22 February (not the page date); the adapter reads international admissions only
  perform public.sd_d1_prov('Canberra', 'https://leadership.fixture-d1can.example/key-dates', jsonb_build_array(jsonb_build_object('period', 'semester 1', 'y', yC, 'm', 2, 'd', 22)), v_can);
  perform public.sd_d1_course('cFeb', 'Canberra', 'February', array['adapter pattern: 15 February ' || yF || ' | 09 August ' || yG], 'filled', make_date(yF, 2, 15));
  perform public.sd_d1_course('cAug', 'Canberra', 'August', array['adapter pattern: 15 February ' || yF || ' | 09 August ' || yG], 'filled', make_date(yG, 8, 9));
  perform public.sd_d1_course('cDom', 'Canberra', 'February', array['Start dates: 15 February ' || yF || ' for domestic students'], 'skipped');
  perform public.sd_d1_course('cMix', 'Canberra', 'February', array['Start dates: 15 February ' || yF || ' for international and domestic students'], 'skipped');
  perform public.sd_d1_course('cPage', 'Canberra', 'February', array['International students: start dates 15 February ' || yF], 'filled', make_date(yF, 2, 15));   -- the page itself names the audience
  -- Macquarie (P3): the calendar does not carry the date; the adapter does not name the audience
  perform public.sd_d1_prov('Macquarie', 'https://leadership.fixture-d1mac.example/key-dates', jsonb_build_array(jsonb_build_object('period', 'session 1', 'y', yC, 'm', 2, 'd', 28)), v_mac);
  perform public.sd_d1_course('mFeb', 'Macquarie', 'February', array['adapter pattern: North Ryde 22 February ' || yC], 'skipped');
  -- Western Sydney-like (P3): the adapter reads "Next Start Date" and the calendar prints no dated start of that day
  perform public.sd_d1_prov('Western', 'https://leadership.fixture-d1wsu.example/key-dates', jsonb_build_array(jsonb_build_object('period', 'session 1', 'y', yC, 'm', 2, 'd', 28)), v_wsu);
  perform public.sd_d1_course('wFeb', 'Western', 'February', array['adapter pattern: 22 February ' || yC], 'skipped');
  -- Adelaide: the intake's page is the how-to-apply page, not the course's own; the calendar would corroborate the date
  perform public.sd_d1_prov('Adelaide', 'https://leadership.fixture-d1ade.example/key-dates', jsonb_build_array(jsonb_build_object('period', 'semester 1', 'y', yA, 'm', 3, 'd', 1)), v_fed);
  perform public.sd_d1_course('aOwn', 'Adelaide', 'March', array['Start dates 01 March ' || yA || ' Locations North Terrace'], 'filled', make_date(yA, 3, 1));
  perform public.sd_d1_course('aHow', 'Adelaide', 'March', array['Start dates 01 March ' || yA || ' Locations North Terrace'], 'skipped', null, null, 'https://fixture-d1ade.example/study/how-to-apply');
  -- Deakin: 1 November 2028 was rejected and withdrawn; the calendar still prints it (as the contaminated reading did)
  perform public.sd_d1_prov('Deakin', 'https://leadership.fixture-d1dk.example/key-dates', jsonb_build_array(jsonb_build_object('period', 'trimester 3', 'y', 2028, 'm', 11, 'd', 1)), null);
  perform public.sd_d1_course('dFar', 'Deakin', 'November', array['Start dates: 1 November 2028'], 'skipped');
  perform public.sd_d1_course('dRej', 'Deakin', 'November', array['Start dates: 1 November 2028'], 'skipped');
  perform public.sd_d1_course('dWd', 'Deakin', 'November', array['Start dates: 1 November 2028'], 'skipped');
  -- a university whose only calendar is set aside by its address: no valid calendar, so the page date is never reached
  perform public.sd_d1_prov('Excluded', 'https://fixture-d1x.example/study-abroad/key-dates', jsonb_build_array(jsonb_build_object('period', 'semester 1', 'y', yA, 'm', 3, 'd', 1)), null);
  perform public.sd_d1_course('xMar', 'Excluded', 'March', array['Start dates: 1 March ' || yA], 'skipped');
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(course_id) from public.sd_d1), true);
end $$;

-- settings as production (9 Nov 2026): named-period lists on, the unique-month path off, the job on; the page-date switch is not yet installed
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.name_period_lists';
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';

-- the fixture is what it claims: the two universities' calendars carry the dates they should (and none of the others)
do $$
declare yA int := public.sd_dy(3, 1); f text := '';
begin
  if (select count(*) from security.calendar_dated_periods_v2((select provider_id from public.sd_d1_prov where name = 'Federation')) s where s.kind = 'start' and s.year_ok and s.on_date is not null) <> 3 then f := f || ' federation calendar'; end if;
  if (select security.calendar_set_v1(provider_id) from public.sd_d1_prov where name = 'Excluded') not like 'none:%' then f := f || ' excluded calendar not set aside'; end if;
  if (select security.calendar_set_v1(provider_id) from public.sd_d1_prov where name = 'Federation') like 'none:%' then f := f || ' federation has no calendar'; end if;
  if f <> '' then raise exception 'fixture:%', f; end if;
  raise notice 'PASS D1 fixture: Federation, Canberra, Macquarie, Western Sydney-like, Adelaide and Deakin universities with approved calendars and page adapters; a university whose only calendar is set aside by its address has no calendar set';
end $$;

-- the baseline: the plan result of every case on the code before the migration (page-date switch absent), compared after the migration with the switch off
create table public.sd_d1_before as
select k.name, p.outcome, p.reason, p.new_year, p.new_start, p.new_deadline, p.start_precision, p.deadline_kind, p.start_quote, p.periods, p.next_action, p.rule
  from public.sd_d1 k left join lateral security.intake_dates_plan_v3(array[k.course_id], 10) p on true;
do $$
begin
  if exists (select 1 from public.sd_d1_before where new_start is not null) then raise exception 'a case is filled before the migration: %', (select string_agg(name, ',') from public.sd_d1_before where new_start is not null); end if;
  raise notice 'PASS D1 baseline: before the migration the calendar route fills none of the % page-date cases (a page that names no study period of the calendar is held month-only)', (select count(*) from public.sd_d1_before);
end $$;

-- the calendar settings the Platform Admin decides (central.auto_approve_calendar_dates, central.calendar_excluded_words ...) as they stand: the migration must leave every central.* setting as it is
create table public.sd_d1_central_before as select toolset_key, key, value from pipeline.platform_toolset_settings where key like 'central.%';
