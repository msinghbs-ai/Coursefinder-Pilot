-- Guards: F-INT.01/SRC-01 (Platform Admin data population first delivery mandate, 9 Nov 2026): migration 20261109060000, the calendar qualification route, on the production-shaped
-- fixture (production unique keys, CHECKs, foreign keys, NOT NULL sets and triggers asserted by parity-tables.sql; the one production function it edits loaded verbatim).
-- Mandatory negative fixtures: Adelaide online how-to-apply, WSU International College, UTS six sessions (scope check, stays proposed), Newcastle enrolment dates that repeat an
-- approved calendar (no new value), Macquarie English pathway, Deakin 1 Nov rejected value never reintroduced, UQ and UNSW withdrawn values. Positive: Federation 2027 PDF
-- (Semester 1 = 1 Mar, Semester 2 = 26 Jul), Canberra international-only table, Torrens main intake labelled by course level. The dates are relative to the clock where the
-- test would otherwise age (the Federation dates are the real 2027 ones until 31 Jan 2027, then the next year's).
\set ON_ERROR_STOP on
\set QUIET on

\ir helpers.sql

-- settings as the migration holds them (switch OFF) ------------------------------------------------------------------------------------------------
select public.cq_assert('migration settings: default off, every setting has a label, a range, a unit and a used_by line',
  (select value = to_jsonb(0) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.calendar_qualify_main_teaching')
  and (select count(*) = 11 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and (key like 'central.calendar_qualify%' or key like 'batch.calendar_qualify%')
        and label <> '' and unit is not null and used_by is not null and used_by <> '' and (kind = 'list' or (min_value is not null and max_value is not null))));
create temp table cq_excluded_before as select value::text v from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.calendar_excluded_words';
create temp table cq_autoapprove_before as select value::text v from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.auto_approve_calendar_dates';

-- the world: providers, stored pages, readings -----------------------------------------------------------------------------------------------------
do $$
declare y int := public.cq_y(); y1 int := extract(year from current_date)::int + 1;
        pf uuid; pc uuid; pt uuid; pa uuid; pw uuid; pu uuid; pn uuid; pm uuid; pd uuid; pq uuid; pun uuid; pst uuid; ph uuid; px uuid; pl uuid; pe uuid; pb uuid; ps uuid;
        s uuid; ap uuid; d0 date := current_date + 40;
begin
  -- Federation 2027 PDF: Semester 1 = 1 March, Semester 2 = 26 July (earlier reader shape: months and quotes)
  pf := public.cq_provider('federation', 'Fixture Federation University Australia', 'https://www.fedfix.edu.au');
  s := public.cq_source(pf, 'https://www.fedfix.edu.au/siteassets/files/students/important-dates/standard_important_dates_' || y || '.pdf');
  perform public.cq_case('federation', pf, public.cq_proposal(pf, s, 'provider-policy-v0.2.2', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', make_date(y, 3, 1), 'q', 'Monday 01 March ' || y || ' | Semester One ' || y || ' lectures/teaching period commence'),
     jsonb_build_object('p', 'semester 2', 'd', make_date(y, 7, 26), 'q', 'Monday 26 July ' || y || ' | Lectures/teaching period commence')))), 'qualifies');
  -- Canberra: an international-only table of the provider's own semester starts
  pc := public.cq_provider('canberra', 'Fixture University of Canberra', 'https://www.canfix.edu.au');
  s := public.cq_source(pc, 'https://www.canfix.edu.au/future-students/study-at-uc/international/international-student-experience-at-uc/semester-keydates', 'Key dates for international students');
  perform public.cq_case('canberra', pc, public.cq_proposal(pc, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20, 'q', 'Semester 1 (international students) | ' || to_char(d0 + 20, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'semester 2', 'd', d0 + 200, 'q', 'Semester 2 (international students) | ' || to_char(d0 + 200, 'FMDD FMMonth YYYY'))), true)), 'qualifies');
  -- Torrens: main intakes, accelerated intakes and terms labelled by course level (the production reading's period names)
  pt := public.cq_provider('torrens', 'Fixture Torrens University Australia', 'https://www.torrfix.edu.au');
  s := public.cq_source(pt, 'https://studenthub.torrfix.edu.au/Hub/Key-Dates');
  perform public.cq_case('torrens', pt, public.cq_proposal(pt, s, 'ai:gpt-4.1-mini', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'main intake 1', 'd', d0 + 10, 'q', 'Main intake 1 | ' || to_char(d0 + 10, 'DD Mon YYYY') || ' | ' || to_char(d0 + 30, 'DD Mon YYYY')),
     jsonb_build_object('p', 'main intake 2', 'd', d0 + 110, 'q', 'Main intake 2 | ' || to_char(d0 + 110, 'DD Mon YYYY') || ' | ' || to_char(d0 + 130, 'DD Mon YYYY')),
     jsonb_build_object('p', 'main intake 3', 'd', d0 + 210, 'q', 'Main intake 3 | ' || to_char(d0 + 210, 'DD Mon YYYY') || ' | ' || to_char(d0 + 230, 'DD Mon YYYY')),
     jsonb_build_object('p', 'main intake 4**', 'd', d0 + 300, 'q', 'Main intake 4** | ' || to_char(d0 + 300, 'DD Mon YYYY') || ' | ' || to_char(d0 + 320, 'DD Mon YYYY')),
     jsonb_build_object('p', 'accelerated intake 1', 'd', d0 + 50, 'q', 'Accelerated intake 1* | ' || to_char(d0 + 50, 'DD Mon YYYY') || ' | ' || to_char(d0 + 60, 'DD Mon YYYY')),
     jsonb_build_object('p', 'accelerated intake 2', 'd', d0 + 150, 'q', 'Accelerated intake 2* | ' || to_char(d0 + 150, 'DD Mon YYYY') || ' | ' || to_char(d0 + 160, 'DD Mon YYYY')),
     jsonb_build_object('p', extract(year from d0 + 10)::int || ' - term 1 (bachelor and master of in', 'd', d0 + 10, 'q', extract(year from d0 + 10)::int || ' - Term 1 | ' || to_char(d0 + 10, 'DD Mon YYYY') || ' | ' || to_char(d0 + 30, 'DD Mon YYYY')),
     jsonb_build_object('p', extract(year from d0 + 110)::int || ' - term 2 (bachelor and master of in', 'd', d0 + 110, 'q', extract(year from d0 + 110)::int || ' - Term 2 | ' || to_char(d0 + 110, 'DD Mon YYYY') || ' | ' || to_char(d0 + 130, 'DD Mon YYYY')),
     jsonb_build_object('p', extract(year from d0 + 210)::int || ' - term 3 (bachelor and master of in', 'd', d0 + 210, 'q', extract(year from d0 + 210)::int || ' - Term 3 | ' || to_char(d0 + 210, 'DD Mon YYYY') || ' | ' || to_char(d0 + 230, 'DD Mon YYYY'))))), 'qualifies');

  -- NEGATIVE 1 Adelaide: the online how-to-apply page, read by the dated parser
  pa := public.cq_provider('adelaide', 'Fixture Adelaide University', 'https://adelaidefix.edu.au');
  s := public.cq_source(pa, 'https://adelaidefix.edu.au/study/online/how-to-apply/');
  perform public.cq_case('adelaide_online_how_to_apply', pa, public.cq_proposal(pa, s, 'provider-policy-calendar-dates-v2', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'term 1', 'd', d0 + 20), jsonb_build_object('p', 'term 2', 'd', d0 + 100), jsonb_build_object('p', 'term 3', 'd', d0 + 180)), true)), 'blocked_word');
  -- NEGATIVE 2 Western Sydney: the International College calendar (a different provider's dates on a subdomain of the university)
  pw := public.cq_provider('wsu', 'Fixture Western Sydney University', 'https://www.wsufix.edu.au');
  s := public.cq_source(pw, 'https://internationalcollege.wsufix.edu.au/college/essential-information/important-dates/');
  perform public.cq_case('wsu_international_college', pw, public.cq_proposal(pw, s, 'ai:gpt-4.1-mini', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'trimester 1', 'd', d0 + 20), jsonb_build_object('p', 'trimester 2', 'd', d0 + 140), jsonb_build_object('p', 'trimester 3', 'd', d0 + 250)))), 'blocked_word');
  -- NEGATIVE 3 UTS: a calendar page whose reading is six numbered sessions a year (a scope check is needed)
  pu := public.cq_provider('uts', 'Fixture University of Technology Sydney', 'https://www.utsfix.edu.au');
  s := public.cq_source(pu, 'https://www.utsfix.edu.au/for-students/current-students/managing-your-course/important-dates/academic-year-dates/' || y || '-academic-year-dates');
  perform public.cq_case('uts_six_sessions', pu, public.cq_proposal(pu, s, 'provider-policy-calendar-dates-v2', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'session 1', 'd', d0, 'q', 'Session commences | Monday ' || to_char(d0, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'session 2', 'd', d0 + 56, 'q', 'Session commences | Monday ' || to_char(d0 + 56, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'session 3', 'd', d0 + 112, 'q', 'Session commences | Monday ' || to_char(d0 + 112, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'session 4', 'd', d0 + 168, 'q', 'Session commences | Monday ' || to_char(d0 + 168, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'session 5', 'd', d0 + 224, 'q', 'Session commences | Monday ' || to_char(d0 + 224, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'session 6', 'd', d0 + 280, 'q', 'Session commences | Monday ' || to_char(d0 + 280, 'FMDD FMMonth YYYY'))), true)), 'scope_check_series');
  -- NEGATIVE 4 Newcastle: an enrolment-dates page that repeats the approved calendar (no new value), and one that differs by a day (a contradiction)
  pn := public.cq_provider('newcastle', 'Fixture University of Newcastle', 'https://www.newfix.edu.au');
  s := public.cq_source(pn, 'https://www.newfix.edu.au/__data/assets/pdf_file/0005/1137173/Academic-Calendar-' || y || '.pdf');
  ap := public.cq_proposal(pn, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'trimester 1', 'd', d0 + 15, 'q', 'Start of term | Monday ' || to_char(d0 + 15, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'semester 1', 'd', d0 + 35, 'q', 'Start of term | Monday ' || to_char(d0 + 35, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'trimester 2', 'd', d0 + 105, 'q', 'Start of term | Monday ' || to_char(d0 + 105, 'FMDD FMMonth YYYY'))), true), 'approved');
  s := public.cq_source(pn, 'https://www.newfix.edu.au/current-students/study-essentials/enrolment/enrolment-dates');
  perform public.cq_case('newcastle_enrolment_repeats_calendar', pn, public.cq_proposal(pn, s, 'provider-policy-calendar-dates-v2', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'trimester 1', 'd', d0 + 15, 'q', 'Start of term | Monday ' || to_char(d0 + 15, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'semester 1', 'd', d0 + 35, 'q', 'Start of term | Monday ' || to_char(d0 + 35, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'trimester 2', 'd', d0 + 105, 'q', 'Start of term | Monday ' || to_char(d0 + 105, 'FMDD FMMonth YYYY'))), true)), 'adds_no_new_value');
  s := public.cq_source(pn, 'https://www.newfix.edu.au/current-students/key-dates-differs');
  perform public.cq_case('newcastle_differs_from_calendar', pn, public.cq_proposal(pn, s, 'provider-policy-calendar-dates-v2', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'trimester 1', 'd', d0 + 16, 'q', 'Start of term | Tuesday ' || to_char(d0 + 16, 'FMDD FMMonth YYYY')),
     jsonb_build_object('p', 'semester 1', 'd', d0 + 35, 'q', 'Start of term | Monday ' || to_char(d0 + 35, 'FMDD FMMonth YYYY'))), true)), 'contradicts_approved_calendar');
  -- NEGATIVE 5 Macquarie: the English-language pathway dates page; and the Macquarie English institute (another website) on a page that is not a calendar
  pm := public.cq_provider('macquarie', 'Fixture Macquarie University', 'https://www.mqfix.edu.au');
  s := public.cq_source(pm, 'https://www.mqfix.edu.au/study/find-a-course/pathway-programs/english-language/dates-fees');
  perform public.cq_case('macquarie_english_pathway', pm, public.cq_proposal(pm, s, 'ai:gpt-4.1-mini:calendar-v2', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'term 1', 'd', d0 + 20), jsonb_build_object('p', 'term 2', 'd', d0 + 90)), true)), 'blocked_word');
  pe := public.cq_provider('mega', 'Fixture Macquarie English Institute', 'https://www.megafix.edu.au');
  s := public.cq_source(pe, 'https://www.megafix.edu.au/project-management/');
  perform public.cq_case('mega_course_page', pe, public.cq_proposal(pe, s, 'ai:gpt-4.1-mini', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'term 1', 'd', d0 + 20), jsonb_build_object('p', 'term 2', 'd', d0 + 90)))), 'not_a_calendar_page');
  -- NEGATIVE 6 Deakin: the 1 November value the Platform Admin rejected (P0 IQ-00313) is never reintroduced, by date or by quote and year
  pd := public.cq_provider('deakin', 'Fixture Deakin University', 'https://www.deakfix.edu.au');
  insert into pipeline.intake_date_rejections(provider_id, quote, year, start_date, reason, case_ref, rejected_by)
  values (pd, 'Trimester 3: 1 Nov - 28 Jan ' || (y1 + 2), y1 + 2, make_date(y1 + 2, 11, 1), 'the quote starts 1 November of the year before the year printed', 'IQ-00313', 'Platform Admin');
  s := public.cq_source(pd, 'https://www.deakfix.edu.au/students/enrolment-and-fees/handbooks/' || y || '-handbook/' || y || '-trimester-dates');
  perform public.cq_case('deakin_rejected_value', pd, public.cq_proposal(pd, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'trimester 1', 'd', d0 + 20), jsonb_build_object('p', 'trimester 2', 'd', d0 + 140),
     jsonb_build_object('p', 'trimester 3', 'd', make_date(y1 + 2, 11, 1), 'q', 'Trimester 3: 1 Nov ' || (y1 + 2))), true)), 'rejected_or_withdrawn_value');
  -- NEGATIVE 7 UQ and UNSW: a value withdrawn from an intake (events outcome withdrawn: its before_value is the withdrawn value)
  pq := public.cq_provider('uq', 'Fixture University of Queensland', 'https://www.uqfix.edu.au');
  pun := public.cq_provider('unsw', 'Fixture UNSW Sydney', 'https://www.unswfix.edu.au');
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, outcome, reason, before_value, after_value)
  values (gen_random_uuid(), gen_random_uuid(), pq, 'withdrawn', 'withdrawn: unsupported by the course page (UQ)', jsonb_build_object('start_date', (d0 + 21)::text, 'year', extract(year from d0 + 21)::int), jsonb_build_object('start_date', null)),
         (gen_random_uuid(), gen_random_uuid(), pun, 'withdrawn', 'withdrawn: a pathway diploma timetable (UNSW)', jsonb_build_object('start_date', (d0 + 141)::text, 'year', extract(year from d0 + 141)::int), jsonb_build_object('start_date', null));
  s := public.cq_source(pq, 'https://www.uqfix.edu.au/academic-calendar');
  perform public.cq_case('uq_withdrawn_value', pq, public.cq_proposal(pq, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 21), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'rejected_or_withdrawn_value');
  s := public.cq_source(pun, 'https://www.unswfix.edu.au/student/managing-your-studies/key-dates/academic-calendar');
  perform public.cq_case('unsw_withdrawn_value', pun, public.cq_proposal(pun, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'term 2', 'd', d0 + 141), jsonb_build_object('p', 'term 3', 'd', d0 + 250)), true)), 'rejected_or_withdrawn_value');
  -- NEGATIVE 8 a Platform Admin rejection of the same address is remembered (a later edition of it is not approved by rule)
  pst := public.cq_provider('rejmem', 'Fixture Rejection Memory University', 'https://www.rejfix.edu.au');
  s := public.cq_source(pst, 'https://www.rejfix.edu.au/students/key-dates');
  perform public.cq_proposal(pst, s, 'ai:gpt-4.1-mini', public.cq_periods(jsonb_build_array(jsonb_build_object('p', 'semester 1', 'd', d0 + 20))), 'rejected');
  update pipeline.provider_policy_proposals set decided_by = gen_random_uuid(), decision_note = 'Platform Admin 18 Oct 2026: rejected, an approved calendar is already in force' where provider_id = pst;
  perform public.cq_case('platform_admin_rejection_memory', pst, public.cq_proposal(pst, public.cq_source(pst, 'https://www.rejfix.edu.au/students/key-dates/'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'platform_admin_rejected_address');
  -- NEGATIVE 9 a provider-level lock by hand
  ph := public.cq_provider('locked', 'Fixture Locked University', 'https://www.lockfix.edu.au');
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('provider', ph, 'intakes', 'value', gen_random_uuid());
  perform public.cq_case('provider_lock_by_hand', ph, public.cq_proposal(ph, public.cq_source(ph, 'https://www.lockfix.edu.au/key-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'provider_locked_by_hand');
  -- NEGATIVE 10 the calendar is on another website (a withdrawn extra domain does not count; an approved alias would)
  px := public.cq_provider('foreign', 'Fixture Foreign Host University', 'https://www.foreignfix.edu.au');
  insert into pipeline.provider_extra_domains(provider_id, domain, state, reason) values (px, 'otherhost.edu.au', 'withdrawn', 'fixture');
  perform public.cq_case('host_not_provider_website', px, public.cq_proposal(px, public.cq_source(px, 'https://www.otherhost.edu.au/key-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'host_not_provider_website');
  -- an approved extra domain of the provider IS its own host
  pl := public.cq_provider('extra', 'Fixture Extra Domain University', 'https://www.extrafix.edu.au');
  insert into pipeline.provider_extra_domains(provider_id, domain, state, reason) values (pl, 'extrahost.edu.au', 'approved', 'fixture');
  perform public.cq_case('approved_extra_domain_is_own_host', pl, public.cq_proposal(pl, public.cq_source(pl, 'https://calendar.extrahost.edu.au/calendars-timetables-and-key-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'qualifies');
  -- NEGATIVE 11 a period named online, a single start, a year not printed, a calendar set by hand that names another month
  pb := public.cq_provider('mixed', 'Fixture Mixed Calendar University', 'https://www.mixfix.edu.au');
  perform public.cq_case('online_period_in_calendar', pb, public.cq_proposal(pb, public.cq_source(pb, 'https://www.mixfix.edu.au/key-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200), jsonb_build_object('p', 'online term 1', 'd', d0 + 60)), true)), 'non_main_period');
  ps := public.cq_provider('single', 'Fixture Single Start University', 'https://www.singfix.edu.au');
  perform public.cq_case('single_start', ps, public.cq_proposal(ps, public.cq_source(ps, 'https://www.singfix.edu.au/key-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20)), true)), 'too_few_starts');
  perform public.cq_case('year_not_printed', ps, public.cq_proposal(ps, public.cq_source(ps, 'https://www.singfix.edu.au/term-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
     jsonb_build_object('p', 'semester 1', 'd', d0 + 20, 'q', 'Semester 1 | ' || to_char(d0 + 20, 'FMDD FMMonth')), jsonb_build_object('p', 'semester 2', 'd', d0 + 200, 'q', 'Semester 2 | ' || to_char(d0 + 200, 'FMDD FMMonth'))), true)), 'year_not_proved');
  declare phand uuid := public.cq_provider('byhand', 'Fixture By Hand University', 'https://www.handfix.edu.au');
  begin
    perform public.cq_proposal(phand, public.cq_source(phand, 'https://www.handfix.edu.au/hand-set'), 'set by hand', jsonb_build_object('periods', jsonb_build_array(jsonb_build_object('period', 'semester 1', 'months', jsonb_build_array(extract(month from d0 + 110)::int)))), 'approved', 'by_hand');
    perform public.cq_case('contradicts_hand_set_calendar', phand, public.cq_proposal(phand, public.cq_source(phand, 'https://www.handfix.edu.au/key-dates'), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
       jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'contradicts_hand_set_calendar');
  end;
  -- NEGATIVE 12 a stored copy older than the limit, and an edition that is past: held, and asked to be read again (bounded)
  declare pold uuid := public.cq_provider('stale', 'Fixture Stale Copy University', 'https://www.stalefix.edu.au'); ppast uuid := public.cq_provider('past', 'Fixture Past Edition University', 'https://www.pastfix.edu.au');
  begin
    perform public.cq_case('evidence_stale', pold, public.cq_proposal(pold, public.cq_source(pold, 'https://www.stalefix.edu.au/key-dates', null, 400), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
       jsonb_build_object('p', 'semester 1', 'd', d0 + 20), jsonb_build_object('p', 'semester 2', 'd', d0 + 200)), true)), 'evidence_stale');
    perform public.cq_case('edition_not_current', ppast, public.cq_proposal(ppast, public.cq_source(ppast, 'https://www.pastfix.edu.au/key-dates', null, 30), 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
       jsonb_build_object('p', 'semester 1', 'd', current_date - 300), jsonb_build_object('p', 'semester 2', 'd', current_date - 120)), true)), 'edition_not_current');
  end;
end $$;

-- the verdict of every case (a read-only function; the switch does not matter) -------------------------------------------------------------------
select public.cq_assert('verdict ' || k.name || ' = ' || k.expect || ' (got ' || c.reason || ')', c.reason = k.expect, c.detail::text)
  from public.cq_cases k, lateral security.calendar_qualify_check_v1(k.proposal_id) c order by k.name;
select public.cq_assert('dry run lists every proposed reading with provider and reason, writes nothing',
  (select count(*) from security.calendar_qualify_dry_run_v1()) = (select count(*) from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed')
  and (select count(*) from pipeline.calendar_qualify_decisions) = 0);

-- switch OFF: nothing happens, whatever the readings ------------------------------------------------------------------------------------------------
select public.cq_assert('switch off: the route returns at once and writes nothing', security.calendar_qualify_v1() = jsonb_build_object('off', true)
  and (select count(*) from pipeline.calendar_qualify_decisions) = 0 and (select count(*) from pipeline.calendar_qualify_runs) = 0
  and not exists (select 1 from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'approved' and decision_note like 'Machine decision%'));
select security.policy_auto_approve_v1();
select public.cq_assert('switch off: the job policy-auto-approve (with the route folded in) approves nothing by rule',
  not exists (select 1 from pipeline.provider_policy_proposals where decision_note like 'Machine decision%') and (select count(*) from pipeline.calendar_qualify_runs) = 0);

-- switch ON ---------------------------------------------------------------------------------------------------------------------------------------
select public.cq_set('central.calendar_qualify_main_teaching', 1);
select public.cq_set('batch.calendar_qualify', 5);
select public.cq_set('central.calendar_refresh_credit_budget', 0);   -- no spend authority: the refresh must ask for nothing while the budget is nil

-- the batch bound: five readings a run, never checked ones first, until all are looked at once
do $$
declare r jsonb; n int := 0; runs int := 0; n_cases int := (select count(*) from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed');   -- the cases and the readings the base fixture already holds
begin
  loop
    r := security.calendar_qualify_v1();
    exit when coalesce((r->>'examined')::int, 0) = 0 or runs > 20;
    if (r->>'examined')::int > 5 then raise exception 'batch bound broken: %', r; end if;
    n := n + (r->>'examined')::int; runs := runs + 1;
  end loop;
  perform public.cq_assert('batch bound: ' || n_cases || ' readings checked in ' || runs || ' runs of at most 5, each once', n = n_cases and runs = ceil(n_cases / 5.0)::int, 'checked ' || n || ' in ' || runs || ' runs');
end $$;

select public.cq_assert('verdict held: ' || k.name || ' stays proposed with the exact reason ' || k.expect,
  p.status = 'proposed' and q.verdict = 'held' and q.reason = k.expect and q.next_check_at > now() and q.actor = 'system:calendar-qualify-v1' and q.detail is not null,
  p.status || '/' || coalesce(q.verdict, 'no decision') || '/' || coalesce(q.reason, '-'))
  from public.cq_cases k join pipeline.provider_policy_proposals p on p.id = k.proposal_id left join pipeline.calendar_qualify_decisions q on q.proposal_id = k.proposal_id
 where k.expect <> 'qualifies' order by k.name;
select public.cq_assert('verdict approved: ' || k.name || ' is a machine decision with its evidence, edition and before/after audit',
  p.status = 'approved' and p.decided_by is null and p.decision_note like 'Machine decision (rule calendar-qualify-v1, not a person)%'
  and q.verdict = 'approved' and q.actor = 'system:calendar-qualify-v1' and q.rule = 'calendar-qualify-v1' and q.evidence_id is not null and q.content_hash is not null and q.captured_at is not null
  and q.edition_year >= extract(year from current_date) and q.source_url is not null and jsonb_array_length(q.quotes) >= 2
  and q.before_state->>'status' = 'proposed' and q.after_state->>'status' = 'approved' and q.after_state->'decided_by' = 'null'::jsonb and q.approved_at is not null,
  p.status || '/' || coalesce(q.verdict, 'no decision'))
  from public.cq_cases k join pipeline.provider_policy_proposals p on p.id = k.proposal_id left join pipeline.calendar_qualify_decisions q on q.proposal_id = k.proposal_id
 where k.expect = 'qualifies' order by k.name;
select public.cq_assert('exactly the four positive cases are approved; no other reading was approved by the route',
  (select count(*) from pipeline.provider_policy_proposals where decision_note like 'Machine decision%') = 4
  and (select count(*) from public.cq_cases where expect = 'qualifies') = 4);
select public.cq_assert('audit trail: one approve_machine control event for each approval, with no human actor and the before and after states',
  (select count(*) from pipeline.admin_control_events where action = 'approve_machine') = 4
  and not exists (select 1 from pipeline.admin_control_events where action = 'approve_machine' and (actor is not null or detail->>'actor_kind' <> 'system' or detail->'before' is null or detail->'after' is null
                                                                                                   or detail->>'content_hash' is null or detail->>'captured_at' is null or detail->>'edition_year' is null or detail->'quotes' is null)));
select public.cq_assert('the settings the brief keeps apart are untouched: central.auto_approve_calendar_dates and central.calendar_excluded_words',
  (select v from cq_autoapprove_before) = (select value::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.auto_approve_calendar_dates')
  and (select v from cq_excluded_before) = (select value::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.calendar_excluded_words'));

-- Federation: Semester 1 = 1 March, Semester 2 = 26 July of the edition year, read by the existing deterministic reader
select public.cq_assert('Federation: the approved calendar gives Semester 1 = 1 March and Semester 2 = 26 July through calendar_dated_periods_v2',
  (select count(*) from security.calendar_dated_periods_v2((select provider_id from public.cq_cases where name = 'federation')) c where c.kind = 'start') = 2
  and exists (select 1 from security.calendar_dated_periods_v2((select provider_id from public.cq_cases where name = 'federation')) c where c.kind = 'start' and c.period = 'semester 1' and c.on_date = make_date(public.cq_y(), 3, 1))
  and exists (select 1 from security.calendar_dated_periods_v2((select provider_id from public.cq_cases where name = 'federation')) c where c.kind = 'start' and c.period = 'semester 2' and c.on_date = make_date(public.cq_y(), 7, 26)));
select public.cq_assert('the negatives give the intake process nothing: no dated period of an unapproved reading is read for ' || k.name, not exists (select 1 from security.calendar_dated_periods_v2(k.provider_id) c where c.proposal_id = k.proposal_id), null)
  from public.cq_cases k where k.expect <> 'qualifies' and k.name not in ('newcastle_enrolment_repeats_calendar', 'newcastle_differs_from_calendar') order by k.name;

-- no refresh while the credit budget is nil; then one at a time inside the existing budget ---------------------------------------------------------
select public.cq_assert('refresh: nothing is asked while central.calendar_refresh_credit_budget is 0 (no new spend authority)', (select count(*) from pipeline.calendar_refresh_requests) = 0
  and (select count(*) from pipeline.calendar_qualify_decisions where verdict = 'held' and reason in ('edition_not_current', 'evidence_stale')) = 2);
select public.cq_set('central.calendar_refresh_credit_budget', 40);
select security.calendar_qualify_v1();
select public.cq_assert('refresh: one stale or past edition is asked to be read again through the existing ladder (a calendar_refresh_requests row, the fact source marked found)',
  (select count(*) from pipeline.calendar_refresh_requests) = 1
  and (select count(*) from pipeline.calendar_refresh_requests r join pipeline.provider_fact_sources f on f.id = r.fact_source_id where r.status = 'requested' and f.status = 'found' and r.reason like 'qualification route:%' and r.credit_estimate = 5) = 1);
select security.calendar_qualify_v1();
select public.cq_assert('refresh: a second request waits for the first (one open request at a time)', (select count(*) from pipeline.calendar_refresh_requests) = 1);
update pipeline.calendar_refresh_requests set status = 'unchanged' where status = 'requested';   -- the external worker read the page and found no new edition
select security.calendar_qualify_v1();
select security.calendar_qualify_v1();
select public.cq_assert('refresh: the other held edition is asked next, each address once, and no more', (select count(*) from pipeline.calendar_refresh_requests) = 2
  and (select count(distinct url) from pipeline.calendar_refresh_requests) = 2 and (select count(*) from pipeline.calendar_refresh_requests where credit_estimate > 5) = 0);
update pipeline.calendar_refresh_requests set status = 'unchanged' where status = 'requested';
select security.calendar_qualify_v1();
select public.cq_assert('refresh: no address is asked twice', (select count(*) from pipeline.calendar_refresh_requests) = 2);

-- idempotent: a rerun with nothing changed writes nothing ------------------------------------------------------------------------------------------
select public.cq_set('batch.calendar_qualify', 25);
create temp table cq_snap as select (select md5(string_agg(proposal_id::text || verdict || reason || decided_at::text, ',' order by proposal_id)) from pipeline.calendar_qualify_decisions) d,
  (select md5(string_agg(id::text || status || coalesce(decided_at::text, ''), ',' order by id)) from pipeline.provider_policy_proposals) p,
  (select count(*) from pipeline.admin_control_events) ev, (select count(*) from pipeline.calendar_qualify_runs) runs;
select public.cq_assert('idempotent: a rerun with nothing changed examines nothing and writes nothing', security.calendar_qualify_v1() = jsonb_build_object('examined', 0, 'approved', 0, 'held', 0, 'by_reason', '{}'::jsonb, 'refresh_asked', 0)
  and (select d from cq_snap) = (select md5(string_agg(proposal_id::text || verdict || reason || decided_at::text, ',' order by proposal_id)) from pipeline.calendar_qualify_decisions)
  and (select p from cq_snap) = (select md5(string_agg(id::text || status || coalesce(decided_at::text, ''), ',' order by id)) from pipeline.provider_policy_proposals)
  and (select ev from cq_snap) = (select count(*) from pipeline.admin_control_events) and (select runs from cq_snap) = (select count(*) from pipeline.calendar_qualify_runs));

-- looked at again when something it depends on changed ----------------------------------------------------------------------------------------------
do $$
declare r jsonb; n_held int := (select count(*) from pipeline.calendar_qualify_decisions where verdict = 'held'); pst uuid;
begin
  -- a setting the verdict depends on changes: every held reading is looked at again, once (the stored copy of the stale case is now within the new limit)
  perform public.cq_set('central.calendar_qualify_max_evidence_age_days', 500);
  r := security.calendar_qualify_v1();
  perform public.cq_assert('recheck on a settings change: all ' || n_held || ' held readings are looked at again and the stale copy now qualifies', (r->>'examined')::int = n_held and (r->>'approved')::int = 1
    and (select p.status from public.cq_cases k join pipeline.provider_policy_proposals p on p.id = k.proposal_id where k.name = 'evidence_stale') = 'approved', r::text);
  perform public.cq_set('central.calendar_qualify_max_evidence_age_days', 120);
  r := security.calendar_qualify_v1();
  perform public.cq_assert('recheck again when the setting returns: nothing more is approved (an approval is withdrawn by a person, never by a setting)', (r->>'examined')::int = n_held - 1 and (r->>'approved')::int = 0, r::text);
  r := security.calendar_qualify_v1();
  perform public.cq_assert('and then it is quiet again', (r->>'examined')::int = 0, r::text);
  -- a revisit time falls due
  update pipeline.calendar_qualify_decisions set next_check_at = now() - interval '1 minute' where proposal_id = (select proposal_id from public.cq_cases where name = 'uts_six_sessions');
  r := security.calendar_qualify_v1();
  perform public.cq_assert('recheck when the revisit time falls due: one reading, held again for a further revisit period', (r->>'examined')::int = 1
    and (select next_check_at > now() + interval '13 days' from pipeline.calendar_qualify_decisions where proposal_id = (select proposal_id from public.cq_cases where name = 'uts_six_sessions')), r::text);
end $$;
-- a value is rejected or withdrawn for the provider afterwards: its held readings are looked at again
insert into pipeline.intake_date_rejections(provider_id, quote, year, start_date, reason, case_ref, rejected_by)
select provider_id, 'Semester 1 | later rejection', extract(year from current_date)::int + 1, current_date + 400, 'fixture: a later rejection', 'F-INT', 'Platform Admin' from public.cq_cases where name = 'online_period_in_calendar';
insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, outcome, reason, before_value, after_value)
select gen_random_uuid(), gen_random_uuid(), provider_id, 'withdrawn', 'withdrawn: fixture (later withdrawal)', jsonb_build_object('start_date', (current_date + 410)::text, 'year', extract(year from current_date + 410)::int), jsonb_build_object('start_date', null) from public.cq_cases where name = 'provider_lock_by_hand';
do $$ declare r jsonb := security.calendar_qualify_v1();
begin perform public.cq_assert('recheck when a value is rejected or withdrawn for the provider afterwards: exactly those two readings', (r->>'examined')::int = 2, r::text); end $$;
-- a hand-approved reading arriving later for the provider is looked at too
select public.cq_proposal(provider_id, fact_source_id, 'set by hand', jsonb_build_object('periods', jsonb_build_array(jsonb_build_object('period', 'semester 1', 'months', jsonb_build_array(extract(month from current_date + 60)::int)))), 'approved', 'by_hand')
  from pipeline.provider_policy_proposals where id = (select proposal_id from public.cq_cases where name = 'host_not_provider_website');
do $$ declare r jsonb := security.calendar_qualify_v1();
begin perform public.cq_assert('recheck when an approved calendar arrives for the provider afterwards', (r->>'examined')::int = 1, r::text); end $$;

-- the withdrawal path ------------------------------------------------------------------------------------------------------------------------------
-- two intakes the Federation calendar admitted (a filled event, the catalogue holding the admitted value)
do $$
declare pf uuid := (select provider_id from public.cq_cases where name = 'federation'); pr uuid := (select proposal_id from public.cq_cases where name = 'federation'); y int := public.cq_y(); r record; n int := 0;
begin
  for r in select i.id intake_id, i.course_id, i.application_deadline from catalogue.course_intakes i join pipeline.course_intake_dates d on d.intake_id = i.id
            where i.start_date is null and i.intake_year is null and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = i.course_id) order by i.id limit 2 loop
    update catalogue.course_intakes set intake_year = y, start_date = make_date(y, 3, 1) where id = r.intake_id;
    update pipeline.course_intake_dates set outcome = 'filled', proposal_id = pr, provider_id = pf, applied_at = now() where intake_id = r.intake_id;
    insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, reason, proposal_id, before_value, after_value)
    values (r.intake_id, r.course_id, pf, now(), 'calendar', 'filled', 'fixture: admitted from the Federation calendar', pr,
            jsonb_build_object('year', null, 'start_date', null, 'application_deadline', r.application_deadline), jsonb_build_object('year', y, 'start_date', make_date(y, 3, 1), 'application_deadline', r.application_deadline));
    n := n + 1;
  end loop;
  if n <> 2 then raise exception 'withdrawal fixture needs two intakes, found %', n; end if;
end $$;
do $$
declare pr uuid := (select proposal_id from public.cq_cases where name = 'federation'); pf uuid := (select provider_id from public.cq_cases where name = 'federation'); v jsonb; a uuid := gen_random_uuid(); fs uuid; np uuid; ok boolean;
begin
  -- a calendar that was not approved by the route cannot be withdrawn through it; a reason is required
  begin perform security.calendar_qualify_withdraw_v1((select id from pipeline.provider_policy_proposals where parser = 'set by hand' limit 1), 'F-INT fixture: not ours to withdraw', a); ok := false;
  exception when sqlstate '22023' then ok := true; end;
  perform public.cq_assert('withdrawal: refuses a calendar the route did not approve', ok);
  begin perform security.calendar_qualify_withdraw_v1(pr, 'short', a); ok := false; exception when sqlstate '22023' then ok := true; end;
  perform public.cq_assert('withdrawal: refuses without a reason', ok);
  begin perform public.admin_calendar_qualify_withdraw_v1(pr, 'F-INT fixture: not a Platform Admin'); ok := false; exception when sqlstate '42501' then ok := true; end;
  perform public.cq_assert('withdrawal: the Platform Admin function refuses anyone else (no session, no rank)', ok);

  v := security.calendar_qualify_withdraw_v1(pr, 'F-INT fixture: the calendar page was a wrong page', a, true);
  perform public.cq_assert('withdrawal: the reading is rejected by the named person and the values it admitted are withdrawn',
    (v->>'withdrawn')::boolean and (v->>'values_admitted')::int = 2 and (v->>'values_withdrawn_now')::int = 2 and (v->>'values_remaining')::int = 0
    and (select status = 'rejected' and decided_by = a and decision_note like 'Withdrawn: %' from pipeline.provider_policy_proposals where id = pr)
    and (select verdict = 'withdrawn' and withdrawn_by = a and withdrawn_reason like 'F-INT fixture%' and withdrawn_at is not null and next_check_at is null from pipeline.calendar_qualify_decisions where proposal_id = pr)
    and (select count(*) from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id where d.proposal_id = pr and i.start_date is null and i.intake_year is null and d.outcome = 'skipped') = 2
    and (select count(*) from pipeline.course_intake_date_events where proposal_id = pr and outcome = 'withdrawn') = 2
    and (select count(*) from pipeline.manual_locks l join pipeline.course_intake_dates d on d.course_id = l.entity_id where l.entity = 'course' and l.field = 'intakes' and d.proposal_id = pr and l.set_by = a) = 2
    and (select count(*) from pipeline.admin_control_events where action = 'withdraw_machine_approval' and actor = a and (detail->>'proposal_id')::uuid = pr) = 1, v::text);
  v := security.calendar_qualify_withdraw_v1(pr, 'F-INT fixture: the calendar page was a wrong page', a, true);
  perform public.cq_assert('withdrawal: a second call changes nothing', (v->>'values_admitted')::int = 0 and (select count(*) from pipeline.admin_control_events where action = 'withdraw_machine_approval') = 1
    and (select count(*) from pipeline.course_intake_date_events where proposal_id = pr and outcome = 'withdrawn') = 2);
  -- the address is remembered: a later reading of the same page is never approved by rule
  select id into fs from pipeline.provider_fact_sources where provider_id = pf and kind = 'intake_calendar';
  np := public.cq_proposal(pf, fs, 'ai:gpt-4.1-mini:calendar-v2.1', (select proposal from pipeline.provider_policy_proposals where id = pr));
  perform public.cq_assert('withdrawal: the rejection is remembered, a later reading of the same address is held as a Platform Admin rejection', (select reason from security.calendar_qualify_check_v1(np)) = 'platform_admin_rejected_address');
  perform security.calendar_qualify_v1();
  perform public.cq_assert('withdrawal: and the route, run again, leaves it proposed', (select status from pipeline.provider_policy_proposals where id = np) = 'proposed'
    and (select reason from pipeline.calendar_qualify_decisions where proposal_id = np) = 'platform_admin_rejected_address');
end $$;
select public.cq_assert('the values it admitted are not admitted again: the withdrawn Federation values are in the rejected-and-withdrawn memory the check reads',
  (select count(*) from pipeline.course_intake_date_events e where e.outcome = 'withdrawn' and e.provider_id = (select provider_id from public.cq_cases where name = 'federation')) = 2);

-- switch back OFF: nothing more is approved, whatever is waiting
select public.cq_set('central.calendar_qualify_main_teaching', 0);
insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, proposal, status)
select p.provider_id, p.fact_source_id, 'intake_calendar', 'ai:gpt-4.1-mini:calendar-v2.1', md5(random()::text), p.evidence_id, p.url, p.proposal, 'proposed' from pipeline.provider_policy_proposals p where p.id = (select proposal_id from public.cq_cases where name = 'canberra');
select public.cq_assert('switch back off: the route returns at once', security.calendar_qualify_v1() = jsonb_build_object('off', true));
select public.cq_assert('every verdict above came from the machine rule, never a human actor; no row carries decided_by from the route',
  not exists (select 1 from pipeline.calendar_qualify_decisions q join pipeline.provider_policy_proposals p on p.id = q.proposal_id where q.verdict = 'approved' and p.decided_by is not null));
