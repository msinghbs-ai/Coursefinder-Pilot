-- Guards: F-INT page-date recovery (a start date the stored course page already prints is admitted on the next hourly run, not at the end of a 14-day revisit; the page reader reads
--   "Month D, YYYY" and year-heading lists and never takes a year heading for the year of the date before it; Platform Admin directive 10 Nov 2026 14:02), the setup and the
--   baseline BEFORE migration 20261110170000, on the plan as production holds it (read 10 Nov 2026, plan_v3 body md5 0d11bc5dfc4b0705f0722a1aa7905db6).
-- Production-shaped universities (measured read-only 10 Nov 2026): Federation (P1: the page date is a start of the approved main calendar) and Canberra (P2: the page adapter reads
-- international admissions only). Every date is relative to the clock, so the cases do not age. Nothing here touches central.* settings.
\set ON_ERROR_STOP on
\set QUIET on

alter table pipeline.uni_adapters add column if not exists patterns jsonb;
do $$ begin perform setval(pg_get_serial_sequence('pipeline.course_intake_date_events', 'id'), greatest((select coalesce(max(id), 1) from pipeline.course_intake_date_events), 1)); end $$;

-- the year of the next day-month after next week (so a date is always in the future, inside the horizon, and never ages)
create or replace function public.pr_dy(p_month int, p_day int) returns int language sql stable as $f$
  select extract(year from (now() at time zone 'Australia/Melbourne'))::int
         + case when make_date(extract(year from (now() at time zone 'Australia/Melbourne'))::int, p_month, p_day) > (now() at time zone 'Australia/Melbourne')::date + 7 then 0 else 1 end $f$;

create table public.pr_d1 (name text primary key, intake_id uuid, course_id uuid, provider_id uuid, expect text, new_start date);
create table public.pr_d1_prov (name text primary key, provider_id uuid, proposal_id uuid);

-- a university: a copy of the fixture's first university, with an approved calendar (one period per start) and, when given, its page adapter
create or replace function public.pr_d1_prov(p_name text, p_url text, p_starts jsonb, p_adapter text default null) returns uuid language plpgsql as $f$
declare v_prov uuid := gen_random_uuid(); v_src uuid := '08609bcf-387d-1316-2a52-9fbc0edff508'; v_prop uuid;
begin
  insert into catalogue.providers select (jsonb_populate_record(null::catalogue.providers, to_jsonb(p) || jsonb_build_object('id', v_prov, 'canonical_name', 'Fixture PR ' || p_name,
         'display_name', 'Fixture PR ' || p_name, 'stable_key', 'provider:au:fixture:pr:' || lower(p_name)))).* from catalogue.providers p where p.id = v_src;
  v_prop := public.fixture_calendar_for(v_prov, p_url, 'ai:gpt-4.1-mini:calendar-v2.1', jsonb_build_object('scope', 'main_teaching', 'periods',
    (select jsonb_agg(jsonb_build_object('period', s->>'period', 'months', jsonb_build_array((s->>'m')::int), 'years', jsonb_build_array((s->>'y')::int),
                                          'quotes', jsonb_build_array((s->>'period') || ': ' || (s->>'d') || '/' || (s->>'m') || '/' || (s->>'y')),
                                          'starts', jsonb_build_array(jsonb_build_object('year', (s->>'y')::int, 'month', (s->>'m')::int, 'day', (s->>'d')::int, 'date', null,
                                                    'quote', (s->>'period') || ': ' || (s->>'d') || '/' || (s->>'m') || '/' || (s->>'y'), 'meaning', 'teaching_start')),
                                          'deadlines', '[]'::jsonb)) from jsonb_array_elements(p_starts) s)));
  if p_adapter is not null then insert into pipeline.uni_adapters(provider_id, enabled, admit, patterns) values (v_prov, true, false, jsonb_build_object('intakes', p_adapter)); end if;
  insert into public.pr_d1_prov values (p_name, v_prov, v_prop);
  return v_prov;
end $f$;

-- a course of that university: its intake month, its stored page wording (one item each), and the expected plan result with the switch on
create or replace function public.pr_d1_course(p_name text, p_prov text, p_label text, p_snips text[], p_expect text, p_start date default null, p_year int default null, p_url text default null) returns uuid language plpgsql as $f$
declare v_prov uuid := (select provider_id from public.pr_d1_prov where name = p_prov); v_src uuid; v_int uuid; v_course uuid; n int;
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
  select count(*) + 1 into n from public.pr_d1;
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, country_code, course_stable_key, intake_options)
  select c.id, v_prov, '6cc98ba2-045f-e409-8d24-356d14447085', 'Fixture PR ' || p_prov, c.canonical_title, lower(c.canonical_title), to_tsvector('simple', c.canonical_title), 'published', 'AU',
         'course:cricos:fixturepr:' || lpad(n::text, 4, '0'), '[]'::jsonb from catalogue.courses c where c.id = v_course;
  insert into public.pr_d1(name, intake_id, course_id, provider_id, expect, new_start) values (p_name, v_int, v_course, v_prov, p_expect, p_start);
  return v_course;
end $f$;

-- settings as production (10 Nov 2026): named-period lists on, the unique-month path off, revisits from stored inputs on (14 days), the job on, the page-date switch on.
-- The switch starts at 0 only to give the rows the decision they got before 9 Nov 09:30 UTC (month only), as production's 9,030 rows have.
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key in ('intake_dates.name_period_lists', 'intake_dates.revisit_stored_inputs');
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key in ('intake_dates.month_unique_match', 'intake_dates.page_date_admit');
update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';

do $$
declare
  yA int := public.pr_dy(3, 1); yB int := public.pr_dy(7, 26); yF int := public.pr_dy(2, 15); yG int := public.pr_dy(8, 9); yC int := public.pr_dy(2, 22);
  v_fed text := 'Start dates\s+((?:Anytime(?:.|\n){0,40}?)?\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)(?:.|\n){0,200}?)\s+Locations';
  v_can text := '(\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+20\d\d)\s+(?:(?:[A-Za-z]+\s+){1,3}for domestic admissions\s+)?Open for international admissions';
  fed_a text := 'adapter pattern: 01 March ' || yA || ' 26 July ' || yB;
  fed_b text := 'Start dates 25 January ' || yA || ' 01 March ' || yA || ' 28 June ' || yA || ' 26 July ' || yB;
begin
  -- Federation (P1): an approved main calendar with semester 1 on 1 March, semester 2 on 26 July, and a pathway program starting 15 February
  perform public.pr_d1_prov('Federation', 'https://leadership.fixture-prfed.example/key-dates', jsonb_build_array(
    jsonb_build_object('period', 'semester 1', 'y', yA, 'm', 3, 'd', 1), jsonb_build_object('period', 'semester 2', 'y', yB, 'm', 7, 'd', 26),
    jsonb_build_object('period', 'pathway program', 'y', yF, 'm', 2, 'd', 15)), v_fed);
  -- Canberra (P2): the calendar has semester 1 on 22 February (not the page date); the adapter reads international admissions only
  perform public.pr_d1_prov('Canberra', 'https://leadership.fixture-prcan.example/key-dates', jsonb_build_array(jsonb_build_object('period', 'semester 1', 'y', yC, 'm', 2, 'd', 22)), v_can);
  -- R: decided before the switch (month only), the page prints the date: the stock production holds (600 intakes at 5 universities on 10 Nov 2026)
  perform public.pr_d1_course('rF1', 'Federation', 'March', array[fed_a, fed_b], 'filled', make_date(yA, 3, 1));
  perform public.pr_d1_course('rF2', 'Federation', 'July', array[fed_a, fed_b], 'filled', make_date(yB, 7, 26));
  perform public.pr_d1_course('rF3', 'Federation', 'March', array[fed_b], 'filled', make_date(yA, 3, 1));
  perform public.pr_d1_course('rC1', 'Canberra', 'February', array['adapter pattern: 15 February ' || yF || ' | 09 August ' || yG], 'filled', make_date(yF, 2, 15));
  perform public.pr_d1_course('rC2', 'Canberra', 'August', array['adapter pattern: 15 February ' || yF || ' | 09 August ' || yG], 'filled', make_date(yG, 8, 9));
  -- the page prints a date that the route must still refuse (decided before the switch too; looked at once now, then settled)
  perform public.pr_d1_course('nJan', 'Federation', 'January', array[fed_b], 'skipped');                                                   -- 25 January: page only (P3)
  perform public.pr_d1_course('nDom', 'Canberra', 'February', array['Start dates: 15 February ' || yF || ' for domestic students'], 'skipped');   -- audience not shown (P3)
  perform public.pr_d1_course('nClose', 'Federation', 'March', array['Applications close 1 March ' || yA || '. Study with us'], 'skipped');       -- a closing date is not a start
  -- no date in the stored wording: never looked at early, never given a day
  perform public.pr_d1_course('nMonth', 'Federation', 'March', array['Start dates: 1 March at the main campus'], 'skipped');
  perform public.pr_d1_course('nNone', 'Federation', 'July', array['Come and see us at the open day'], 'skipped');
  -- E: dates the page prints in a format or with a history the reader did not handle (looked at again from stored inputs)
  perform public.pr_d1_course('eMDY', 'Federation', 'March', array['Start dates: March 1, ' || yA], 'filled', make_date(yA, 3, 1));                         -- Month D, YYYY
  perform public.pr_d1_course('eMDYo', 'Federation', 'March', array['Start dates: March 1st, ' || yA], 'filled', make_date(yA, 3, 1));
  perform public.pr_d1_course('eHead', 'Federation', 'March', array['Start dates ' || yA || ': 1 Mar, 26 Jul'], 'filled', make_date(yA, 3, 1));                -- a year heading with days and months under it
  perform public.pr_d1_course('ePast', 'Federation', 'March', array['Start dates: 1 March ' || (yA - 1) || ' and 1 March ' || yA], 'filled', make_date(yA, 3, 1));   -- a past date and the next one
  perform public.pr_d1_course('eYear', 'Federation', 'March', array['Start dates: 1 March ' || yA || ' and 1 March ' || (yA + 1)], 'filled', make_date(yA, 3, 1), yA);   -- the intake holds its year
  perform public.pr_d1_course('eMis', 'Federation', 'March', array['Start dates ' || (yA - 1) || ': 5 Jan, 1 Mar ' || yA || ': 11 Jan'], 'skipped');          -- "1 Mar yA:" heads the next list: 1 March belongs to yA - 1, which is past
  perform public.pr_d1_course('eMis2', 'Federation', 'March', array['Start dates ' || yA || ': 1 Mar, 26 Jul ' || (yA + 1) || ': 11 Jan'], 'filled', make_date(yA, 3, 1));   -- the heading of the next list does not hide the first list
  -- D: an intake that already holds its exact date (admitted by the page route), planned again after a new calendar changed its fingerprint
  perform public.pr_d1_course('dRow', 'Federation', 'March', array[fed_b], 'filled', make_date(yA, 3, 1));
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(course_id) from public.pr_d1), true);
  -- the filler: undecided intakes whose page prints no date (production's batch is full of them)
  for i in 1 .. 45 loop perform public.pr_d1_course('u' || i, 'Federation', 'March', array['Come and see us at the open day'], 'skipped'); end loop;
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(course_id) from public.pr_d1 where name like 'u%'), true);
end $$;

-- the decision every row got before the page route was on: month only, a revisit in 14 days (the D3 backfill spread these over 14 days; here all start at 14)
do $$
declare v jsonb;
begin
  v := security.intake_dates_apply_v1(100, (select array_agg(course_id) from public.pr_d1 where name !~ '^u\d'));
  if exists (select 1 from catalogue.course_intakes i join public.pr_d1 k on k.intake_id = i.id where i.start_date is not null) then raise exception 'a case is filled before the page route is on: %', v; end if;
  if (select count(*) from pipeline.course_intake_dates d join public.pr_d1 k on k.intake_id = d.intake_id where k.name !~ '^u\d' and d.outcome = 'skipped' and d.next_revisit_at > now() + interval '13 days') <> (select count(*) from public.pr_d1 where name !~ '^u\d') then
    raise exception 'the pre-switch decisions are not skipped with a 14-day revisit: %', (select string_agg(k.name || ':' || coalesce(d.outcome || '/' || d.reason, '-'), ' | ') from public.pr_d1 k left join pipeline.course_intake_dates d on d.intake_id = k.intake_id where k.name !~ '^u\d'); end if;
  raise notice 'PASS PR setup: % intakes decided "month only" before the page route was on, each with a 14-day revisit (as production''s 9,030 rows are); % undecided filler intakes', (select count(*) from public.pr_d1 where name !~ '^u\d'), (select count(*) from public.pr_d1 where name ~ '^u\d');
end $$;
-- production now: the page route is on (9 Nov 09:30 UTC)
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';

-- the hourly batch on the code as production holds it, with the page route on: the rows that print a date are not looked at (fingerprint unchanged, revisit 14 days away); the filler is
create table public.pr_fp_before as select d.intake_id, d.inputs_fp, d.next_revisit_at, d.outcome, d.reason, d.rule from pipeline.course_intake_dates d join public.pr_d1 k on k.intake_id = d.intake_id;
create table public.pr_gate_before as
select k.name, p.outcome, p.rule from security.intake_dates_plan_v3((select array_agg(course_id) from public.pr_d1), 40) p join public.pr_d1 k on k.intake_id = p.intake_id;
do $$
declare n int;
begin
  select count(*) into n from public.pr_gate_before where name ~ '^(r|n)';
  if n <> 0 then raise exception 'production already looks at % decided rows: %', n, (select string_agg(name, ',') from public.pr_gate_before where name ~ '^(r|n)'); end if;
  if (select count(*) from public.pr_gate_before) = 0 then raise exception 'the batch is empty: the filler should be planned'; end if;
  raise notice 'PASS PR baseline gate: with the page route on, the hourly batch (40) takes % filler intakes and none of the 5 intakes whose page prints their date: the plan skips a row whose fingerprint is unchanged until its revisit time, and the fingerprint holds neither the switch nor the date', (select count(*) from public.pr_gate_before);
end $$;

-- the dated row: admitted by the page route on today's code, then planned again because a new approved calendar changed its fingerprint
update pipeline.course_intake_dates set inputs_fp = 'fixture: look again', next_revisit_at = null where intake_id = (select intake_id from public.pr_d1 where name = 'dRow');
do $$
declare v jsonb; k record;
begin
  select * into k from public.pr_d1 where name = 'dRow';
  v := security.intake_dates_apply_v1(10, array[k.course_id]);
  if (select start_date from catalogue.course_intakes where id = k.intake_id) is distinct from k.new_start then raise exception 'dRow not admitted by the page route on production code: %', v; end if;
  if (select d.rule from pipeline.course_intake_dates d where d.intake_id = k.intake_id) is distinct from 'page-date-v1' then raise exception 'dRow rule'; end if;
  update pipeline.course_intake_dates set inputs_fp = 'fixture: a new approved calendar', next_revisit_at = null where intake_id = k.intake_id;
  raise notice 'PASS PR setup dRow: an intake that holds its exact date from the page route (rule page-date-v1, with its quote) and whose fingerprint then changed';
end $$;

-- the extraction cases are looked at again (their stored inputs changed), then the plan result of today's code is kept
update pipeline.course_intake_dates set inputs_fp = 'fixture: look again', next_revisit_at = null where intake_id in (select intake_id from public.pr_d1 where name ~ '^e');
create table public.pr_ext_before as
select k.name, p.outcome, p.reason, p.new_year, p.new_start, p.new_deadline, p.start_precision, p.deadline_kind, p.start_quote, p.periods, p.next_action, p.rule, p.next_revisit_at
  from public.pr_d1 k left join lateral security.intake_dates_plan_v3(array[k.course_id], 10) p on true where k.name ~ '^(e|d)';
do $$
declare f text := ''; r record;
begin
  for r in select * from public.pr_ext_before order by name loop
    -- the defects, on today's code
    if r.name in ('eMDY', 'eMDYo', 'eHead') and (r.outcome is distinct from 'skipped' or r.reason not like '%names no study period%') then f := f || ' ' || r.name || ' ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
    if r.name = 'ePast' and (r.outcome is distinct from 'skipped' or r.reason not like '%several different%') then f := f || ' ePast ' || coalesce(r.reason, '-'); end if;
    if r.name = 'eYear' and (r.outcome is distinct from 'skipped' or r.reason not like '%several different%') then f := f || ' eYear ' || coalesce(r.reason, '-'); end if;
    if r.name = 'eMis' and (r.outcome is distinct from 'filled' or r.new_start is distinct from make_date(public.pr_dy(3, 1), 3, 1)) then f := f || ' eMis ' || coalesce(r.outcome, '-') || '/' || coalesce(r.reason, '-'); end if;
    if r.name = 'dRow' and (r.outcome is distinct from 'skipped' or r.rule is not distinct from 'page-date-v1') then f := f || ' dRow ' || coalesce(r.outcome, '-') || '/' || coalesce(r.rule, '-'); end if;
  end loop;
  if f <> '' then raise exception 'baseline defects not as measured on production:%', f; end if;
  raise notice 'PASS PR baseline defects on production code: "Month D, YYYY" and a year heading are not read (month only); a past date and the next one, or two years of one intake, are "several different dates"; "1 Mar %: 11 Jan" is read as 1 March % (the heading of the next list taken for a year) and would be admitted with the calendar start on that day; a held exact date is replaced by "skipped: names no study period"', public.pr_dy(3, 1), public.pr_dy(3, 1);
end $$;

-- the plan with the switch off, kept to show the migration changes nothing then
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
create table public.pr_off_before as
select k.name, p.outcome, p.reason, p.new_year, p.new_start, p.new_deadline, p.start_precision, p.deadline_kind, p.start_quote, p.periods, p.next_action, p.rule, p.inputs_fp, p.next_revisit_at
  from security.intake_dates_plan_v3((select array_agg(course_id) from public.pr_d1), 200) p join public.pr_d1 k on k.intake_id = p.intake_id;
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
do $$ begin raise notice 'PASS PR baseline switch off: the plan result of % intakes kept (switch 0) to compare after the migration', (select count(*) from public.pr_off_before); end $$;

-- the calendar settings the Platform Admin decides, as they stand: the migration must leave every central.* setting (and the unique-month path) as it is
create table public.pr_central_before as select toolset_key, key, value from pipeline.platform_toolset_settings where key like 'central.%' or key = 'intake_dates.month_unique_match';
