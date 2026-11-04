-- Guards: Platform Admin decision 5 Nov 2026 (intake recovery and process accountability) §1-§3, §5-§9: migration 20261105020000 on the
-- production-shaped intake fixture database. Regression cases named in §3: multiple periods, different years, wrong calendars, course-specific
-- exceptions, missing academic-year evidence; and orientation never a commencement, international deadline first, revisit only on change or
-- time, appended history, approval never closing another document, AI notes and findings, the stored re-read hand-off, process results.
\set ON_ERROR_STOP on
\set QUIET on
-- a month intake on a copy of a course whose page is proved (E16 pass), with its own page wording
create or replace function public.fixture_clone_intake(p_src uuid, p_label text, p_wording text, p_year int default null) returns uuid language plpgsql as $f$
declare s catalogue.course_intakes%rowtype; v_course uuid := gen_random_uuid(); v_int uuid := gen_random_uuid(); v_ev uuid := gen_random_uuid();
        v_title text := 'Master of Calendar Case ' || substr(md5(v_int::text), 1, 6); v_url text; v_src_url text;
begin
  select * into s from catalogue.course_intakes where id = p_src;
  select e.source_url into v_src_url from pipeline.evidence_artifacts e where e.id = s.evidence_id;
  v_url := regexp_replace(v_src_url, '/[^/]+$', '/') || lower(replace(v_title, ' ', '-'));
  insert into pipeline.evidence_artifacts select (jsonb_populate_record(null::pipeline.evidence_artifacts, to_jsonb(e) || jsonb_build_object('id', v_ev, 'source_url', v_url, 'entity_id', v_course))).*
    from pipeline.evidence_artifacts e where e.id = s.evidence_id;
  insert into catalogue.courses select (jsonb_populate_record(null::catalogue.courses, to_jsonb(c) || jsonb_build_object('id', v_course, 'canonical_title', v_title, 'display_title', v_title,
           'course_url', v_url))).* from catalogue.courses c where c.id = s.course_id;
  insert into pipeline.coverage_course_pages
  select (jsonb_populate_record(null::pipeline.coverage_course_pages, to_jsonb(g) || jsonb_build_object('course_id', v_course, 'url', v_url, 'evidence_id', v_ev,
           'candidates', coalesce(g.candidates, '{}'::jsonb) || jsonb_build_object('intake_context', jsonb_build_array(p_wording), 'final_url', v_url)))).*
    from pipeline.coverage_course_pages g where g.course_id = s.course_id;
  insert into catalogue.course_intakes(id, course_id, intake_label, intake_year, status, evidence_id, source_id, confidence)
  values (v_int, v_course, p_label, p_year, 'active', v_ev, s.source_id, s.confidence);
  return v_int;
end $f$;
create or replace function public.fixture_calendar(p_url text, p_parser text, p_proposal jsonb, p_status text default 'approved') returns uuid language plpgsql as $f$
declare v_src uuid; v_id uuid; v_prov uuid := '08609bcf-387d-1316-2a52-9fbc0edff508';
begin
  insert into pipeline.provider_fact_sources(provider_id, kind, url, status, content_hash) values (v_prov, 'intake_calendar', p_url, 'parsed', md5(p_url))
  on conflict (provider_id, kind, url) do update set updated_at = now() returning id into v_src;
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, proposal, status, decided_at)
  values (v_prov, v_src, 'intake_calendar', p_parser, md5(p_url), p_url, p_proposal, p_status, case when p_status = 'approved' then now() end) returning id into v_id;
  return v_id;
end $f$;
create temp table k(name text primary key, id uuid);

do $$
declare src uuid := '65db9411-9f96-4b6e-af6e-7fc4547969a8'; v jsonb;
begin
  -- the calendars: a second main teaching calendar (calendar-v2 reading), a residential college calendar and an offshore campus calendar
  insert into k values ('main2', public.fixture_calendar('https://www.harbour.edu.au/key-dates/2027', 'ai:gpt-4.1-mini:calendar-v2', $j${"parser": "ai:gpt-4.1-mini:calendar-v2", "reader": "calendar-v2", "scope": "main_teaching", "scope_quote": "Harbour University key dates 2027", "periods": [
    {"period": "autumn session", "months": [2], "years": [2027], "quotes": ["22 February 2027 | Autumn session teaching begins"],
     "starts": [{"year": 2027, "month": 2, "day": 22, "date": "2027-02-22", "quote": "22 February 2027 | Autumn session teaching begins", "meaning": "teaching_start"}],
     "deadlines": [{"year": 2026, "month": 12, "day": 1, "date": "2026-12-01", "quote": "1 December 2026 | International applications close for Autumn session", "applies_to": "international", "rolling": false},
                   {"year": 2027, "month": 1, "day": 15, "date": "2027-01-15", "quote": "15 January 2027 | Domestic applications close for Autumn session", "applies_to": "domestic", "rolling": false}]},
    {"period": "orientation", "months": [2], "years": [2027], "quotes": ["15 February 2027 | Orientation week"],
     "starts": [{"year": 2027, "month": 2, "day": 15, "date": "2027-02-15", "quote": "15 February 2027 | Orientation week", "meaning": "orientation"}], "deadlines": []},
    {"period": "winter session", "months": [7], "years": [2027], "quotes": ["5 July 2027 | Winter session classes begin"],
     "starts": [{"year": 2027, "month": 7, "day": 5, "date": "2027-07-05", "quote": "5 July 2027 | Winter session classes begin", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "term 4", "months": [10], "years": [2027], "quotes": ["4 October | Term 4 begins"],
     "starts": [{"year": 2027, "month": 10, "day": 4, "date": "2027-10-04", "quote": "4 October | Term 4 begins", "year_quote": "2027 key dates", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "spring session", "months": [9], "years": [2027], "quotes": ["6 September | Spring session begins"],
     "starts": [{"year": 2027, "month": 9, "day": 6, "date": "2027-09-06", "quote": "6 September | Spring session begins", "meaning": "teaching_start"}], "deadlines": []}]}$j$::jsonb));
  insert into k values ('college', public.fixture_calendar('https://www.harbour.edu.au/residential-college/key-dates', 'ai:gpt-4.1-mini:calendar-v2', $j${"parser": "ai:gpt-4.1-mini:calendar-v2", "scope": "main_teaching", "periods": [
    {"period": "term 2", "months": [5], "years": [2027], "quotes": ["3 May 2027 | Term 2 starts"], "starts": [{"year": 2027, "month": 5, "day": 3, "date": "2027-05-03", "quote": "3 May 2027 | Term 2 starts", "meaning": "teaching_start"}], "deadlines": []}]}$j$::jsonb));
  insert into k values ('offshore', public.fixture_calendar('https://www.harbour.edu.au/singapore/dates', 'ai:gpt-4.1-mini:calendar-v2', $j${"parser": "ai:gpt-4.1-mini:calendar-v2", "scope": "offshore_campus", "scope_quote": "Singapore campus dates", "periods": [
    {"period": "trimester 1", "months": [8], "years": [2027], "quotes": ["2 August 2027 | Trimester 1 begins"], "starts": [{"year": 2027, "month": 8, "day": 2, "date": "2027-08-02", "quote": "2 August 2027 | Trimester 1 begins", "meaning": "teaching_start"}], "deadlines": []}]}$j$::jsonb));
  -- wrong calendars are set aside with a reason, never deleted
  select jsonb_object_agg(s.url, jsonb_build_object('used', s.used, 'scope', s.scope, 'why', s.set_aside_reason)) into v from security.calendar_sources_v1('08609bcf-387d-1316-2a52-9fbc0edff508') s;
  if (v->'https://www.harbour.edu.au/residential-college/key-dates'->>'scope') <> 'excluded_by_address' or (v->'https://www.harbour.edu.au/residential-college/key-dates'->>'used')::boolean
     or (v->'https://www.harbour.edu.au/singapore/dates'->>'scope') <> 'offshore_campus' or (v->'https://www.harbour.edu.au/singapore/dates'->>'used')::boolean
     or not (v->'https://www.harbour.edu.au/key-dates/2027'->>'used')::boolean or not (v->'https://www.harbour.edu.au/calendar'->>'used')::boolean then
    raise exception 'calendar scope: %', v; end if;
  if exists (select 1 from security.calendar_dated_periods_v2('08609bcf-387d-1316-2a52-9fbc0edff508') where period = 'orientation') then raise exception 'orientation counted as a commencement'; end if;
  raise notice 'PASS calendars: every main teaching calendar used; residential college (address) and offshore campus (reader scope) set aside with reasons; orientation is not a commencement';
  insert into k values
    ('feb', public.fixture_clone_intake(src, 'February', 'February intake')),
    ('jul', public.fixture_clone_intake(src, 'July', 'July intake')),
    ('may', public.fixture_clone_intake(src, 'May', 'May intake')),
    ('aug', public.fixture_clone_intake(src, 'August', 'August intake')),
    ('feb2028', public.fixture_clone_intake(src, 'February', 'February intake', 2028)),
    ('febown', public.fixture_clone_intake(src, 'February', 'February intake: classes begin 1 February 2027')),
    ('sep', public.fixture_clone_intake(src, 'September', 'September intake')),
    ('oct', public.fixture_clone_intake(src, 'October', 'October intake')),
    ('mar', public.fixture_clone_intake(src, 'March', 'Commencing Semester 1'));
end $$;

create temp table plan as select * from security.intake_dates_plan_v3((select array_agg(course_id) from catalogue.course_intakes where id in (select id from k)), 100);
do $$
declare r record; v_fail text := '';
begin
  for r in select k.name, p.* from k join plan p on p.intake_id = k.id loop
    v_fail := v_fail || case
      when r.name = 'feb' and not (r.outcome = 'filled' and r.new_start = '2027-02-22' and r.new_year = 2027 and r.new_deadline = '2026-12-01' and r.rule = 'calendar-v3-unique-month' and r.deadline_kind = 'date'
                                   and r.calendar_url = 'https://www.harbour.edu.au/key-dates/2027') then ' feb ' || row_to_json(r)::text
      when r.name = 'jul' and not (r.outcome = 'skipped' and r.reason = 'several study periods start in this month (month only)' and r.next_action = 'evidence_ambiguous' and r.next_revisit_at is null and r.new_start is null) then ' jul ' || row_to_json(r)::text
      when r.name = 'may' and not (r.outcome = 'skipped' and r.reason = 'the calendar has no future start in this month (month only)' and r.next_action = 'waiting_for_next_academic_year' and r.next_revisit_at > now()) then ' may ' || row_to_json(r)::text
      when r.name = 'aug' and not (r.outcome = 'skipped' and r.reason = 'the calendar has no future start in this month (month only)') then ' aug ' || row_to_json(r)::text
      when r.name = 'feb2028' and not (r.outcome = 'skipped' and r.reason = 'the calendar prints no start in this month of the intake''s own year (month only)') then ' feb2028 ' || row_to_json(r)::text
      when r.name = 'febown' and not (r.outcome = 'skipped' and r.reason like 'the course page gives its own start date for this intake (2027-02-01)%' and r.next_action = 'human_decision_required') then ' febown ' || row_to_json(r)::text
      when r.name = 'sep' and not (r.outcome = 'skipped' and r.reason = 'the calendar does not print the year of its start in this month (month only)' and r.next_action = 'reader_correction_needed') then ' sep ' || row_to_json(r)::text
      when r.name = 'oct' and not (r.outcome = 'filled' and r.new_start = '2027-10-04' and r.deadline_kind = 'not_stated' and r.next_action = 'awaiting_official_calendar' and r.next_revisit_at > now()) then ' oct ' || row_to_json(r)::text
      when r.name = 'mar' and not (r.outcome = 'filled' and r.new_start = '2027-03-01' and r.rule = 'calendar-v3' and r.new_deadline = '2026-11-30' and r.next_action = 'complete') then ' mar ' || row_to_json(r)::text
      else '' end;
  end loop;
  if (select count(*) from plan where intake_id in (select id from k)) <> 9 then raise exception 'expected 9 planned rows, got %', (select count(*) from plan where intake_id in (select id from k)); end if;
  if v_fail <> '' then raise exception 'plan v3 cases failed:%', v_fail; end if;
  raise notice 'PASS unique month: one commencement fills (international deadline first); two periods in the month, a wrong or offshore calendar, another intake year, a course page date and a start without year evidence keep the month with the exact reason and next action; the named period path is unchanged';
end $$;

-- the setting is the decision: off, a month-only page keeps its month
do $$ declare v text; begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  select reason into v from security.intake_dates_plan_v3((select array[course_id] from catalogue.course_intakes where id = (select id from k where name = 'feb')), 10);
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  if v is distinct from 'the course page names no study period of the calendar (month only)' then raise exception 'unique off: %', v; end if;
  raise notice 'PASS intake_dates.month_unique_match 0 keeps the named-period rule';
end $$;

-- apply: values admitted through the job's own write; every decision appended; looked at again only on a change or when its revisit is due
do $$
declare v jsonb; v_courses uuid[] := (select array_agg(course_id) from catalogue.course_intakes where id in (select id from k)); n_ev int; n_again int;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
  v := security.intake_dates_apply_v1(100, v_courses);
  if (v->>'looked_at')::int <> 9 or (v->>'filled')::int <> 3 then raise exception 'apply: %', v; end if;
  if (select start_date from catalogue.course_intakes where id = (select id from k where name = 'feb')) <> '2027-02-22'
     or (select application_deadline from catalogue.course_intakes where id = (select id from k where name = 'feb')) <> '2026-12-01'
     or (select start_date from catalogue.course_intakes where id = (select id from k where name = 'jul')) is not null then raise exception 'catalogue values wrong'; end if;
  select count(*) into n_ev from pipeline.course_intake_date_events where intake_id in (select id from k);
  if n_ev <> 9 then raise exception 'events after one run: %', n_ev; end if;
  -- nothing changed: nothing is looked at again (ambiguous waits for a change; waiting rows wait for their revisit time)
  v := security.intake_dates_apply_v1(100, v_courses);
  if (v->>'looked_at')::int <> 0 then raise exception 'unchanged inputs looked at again: %', v; end if;
  -- a revisit time that has passed: only that row is looked at again, and its earlier decision is kept in the history
  update pipeline.course_intake_dates set next_revisit_at = now() - interval '1 minute' where intake_id = (select id from k where name = 'may');
  v := security.intake_dates_apply_v1(100, v_courses);
  if (v->>'looked_at')::int <> 1 then raise exception 'revisit due: %', v; end if;
  if (select count(*) from pipeline.course_intake_date_events where intake_id = (select id from k where name = 'may')) <> 2 then raise exception 'history overwritten'; end if;
  -- a new calendar reading (calendar set changes): every row of the university not complete is looked at again
  perform public.fixture_calendar('https://www.harbour.edu.au/key-dates/2027-update', 'ai:gpt-4.1-mini:calendar-v2', '{"parser": "ai:gpt-4.1-mini:calendar-v2", "scope": "main_teaching", "periods": []}'::jsonb);
  select count(*) into n_again from security.intake_dates_plan_v3(v_courses, 100);
  if n_again <> 7 then raise exception 'calendar change should bring back the 7 rows not complete (2 complete: feb, mar), got %', n_again; end if;
  raise notice 'PASS apply: 3 values admitted through the job''s write; 9 decisions appended; unchanged inputs not looked at again; a due revisit looks at one row and keeps its history; a calendar change brings back every row not complete';
end $$;

-- approval: approving one calendar document never closes another document's proposal; deterministic dated readings only when switched on
do $$
declare a uuid; b uuid; d uuid; v jsonb;
begin
  insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, unit, section, used_by, reason)
  values ('pipeline', 'central.auto_approve', 'x', 'boolean', 'true'::jsonb, 'on/off', 'x', 'x', 'fixture') on conflict (toolset_key, key) do update set value = 'true'::jsonb;
  insert into pipeline.enrich_focus_providers(provider_id, rank, gaps, in_focus) values ('08609bcf-387d-1316-2a52-9fbc0edff508', 1, 1, true) on conflict do nothing;
  a := public.fixture_calendar('https://www.harbour.edu.au/doc-a', 'ai:gpt-4.1-mini:calendar-v2', '{"periods": []}'::jsonb, 'proposed');
  b := public.fixture_calendar('https://www.harbour.edu.au/doc-b', 'ai:gpt-4.1-mini:calendar-v2', '{"periods": []}'::jsonb, 'proposed');
  d := public.fixture_calendar('https://www.harbour.edu.au/doc-d', 'provider-policy-calendar-dates-v2', '{"periods": []}'::jsonb, 'proposed');
  v := security.policy_auto_approve_v1();
  if (select string_agg(status, ',' order by url) from pipeline.provider_policy_proposals where id in (a, b, d)) <> 'approved,approved,proposed' then
    raise exception 'auto-approve: % %', v, (select string_agg(url || '=' || status, ',' order by url) from pipeline.provider_policy_proposals where id in (a, b, d)); end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'central.auto_approve_calendar_dates';
  v := security.policy_auto_approve_v1();
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'central.auto_approve_calendar_dates';
  if (select status from pipeline.provider_policy_proposals where id = d) <> 'approved' then raise exception 'deterministic reading not approved when switched on'; end if;
  raise notice 'PASS approval: two calendar documents approved side by side; a deterministic dated reading waits for a person until central.auto_approve_calendar_dates is 1';
end $$;

-- the AI queue: calendar items carry the reader's notes; a calendar-v2 answer records its findings, resolves them when gone, marks the document read
do $$
declare v_src uuid; v_q bigint; v jsonb; n int;
begin
  select fact_source_id into v_src from pipeline.provider_policy_proposals where id = (select id from k where name = 'main2');
  update pipeline.provider_fact_sources set evidence_id = (select evidence_id from catalogue.course_intakes where id = (select id from k where name = 'feb')) where id = v_src;
  insert into pipeline.calendar_reread_state(fact_source_id, provider_id, state) values (v_src, '08609bcf-387d-1316-2a52-9fbc0edff508', 'sent_to_ai') on conflict do nothing;
  insert into pipeline.calendar_reader_findings(provider_id, fact_source_id, code, detail, example) values ('08609bcf-387d-1316-2a52-9fbc0edff508', v_src, 'year_not_printed', 'start of term 4', '4 October | Term 4 begins');
  insert into pipeline.central_ai_queue(fact_source_id, provider_id, kind, content_hash) values (v_src, '08609bcf-387d-1316-2a52-9fbc0edff508', 'intake_calendar', 'h1') returning id into v_q;
  set local role postgres;
  v := public.svc_central_ai_next(5);
  if not exists (select 1 from jsonb_array_elements(v) x where (x->>'queue_id')::bigint = v_q and x->>'notes' like '%year_not_printed: start of term 4%') then raise exception 'notes not given: %', v; end if;
  v := public.svc_central_ai_record(v_q, '{"parser": "ai:gpt-4.1-mini:calendar-v2", "scope": "main_teaching", "periods": [{"period": "term 4", "months": [10], "years": [2027], "quotes": ["4 October 2027 | Term 4 begins"], "starts": [], "deadlines": []}],
                                          "findings": [{"code": "no_deadline", "detail": "no application closing date on this calendar"}]}'::jsonb, 0.0021, null);
  select count(*) into n from pipeline.calendar_reader_findings where fact_source_id = v_src and resolved_at is null;
  if n <> 1 or not exists (select 1 from pipeline.calendar_reader_findings where fact_source_id = v_src and code = 'year_not_printed' and resolved_at is not null)
     or (select state from pipeline.calendar_reread_state where fact_source_id = v_src) <> 'read_by_ai' then raise exception 'findings: % open', n; end if;
  raise notice 'PASS AI reader loop: notes from open findings go with the next read; a new answer opens what it dropped, resolves what is gone, marks the document read';
end $$;

-- the stored re-read: the dated parser's reading becomes its own proposal (an approved one is never changed); not safe goes to the AI queue
do $$
declare v jsonb; v_src uuid; v_appr jsonb; n_q int;
begin
  select f.id into v_src from pipeline.provider_fact_sources f join pipeline.provider_policy_proposals p on p.fact_source_id = f.id where p.id = '24818cee-28f3-8368-8e3f-5454e23dda68';
  update pipeline.provider_fact_sources set evidence_id = (select evidence_id from catalogue.course_intakes where id = (select id from k where name = 'feb')) where id = v_src;
  select proposal into v_appr from pipeline.provider_policy_proposals where id = '24818cee-28f3-8368-8e3f-5454e23dda68';
  v := public.svc_calendar_reread_next(60);
  if not exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = v_src) then raise exception 'not leased: %', v; end if;
  v := public.svc_calendar_reread_record(v_src, '{"parser": "provider-policy-calendar-dates-v2", "periods": [{"period": "semester 1", "months": [3], "years": [2027], "quotes": ["1 March 2027 | Semester 1 starts"], "starts": [{"year": 2027, "month": 3, "day": 1, "date": "2027-03-01", "quote": "1 March 2027 | Semester 1 starts"}], "deadlines": []}]}'::jsonb,
                                        true, 'the address may not be the main teaching calendar', null);
  if (select proposal from pipeline.provider_policy_proposals where id = '24818cee-28f3-8368-8e3f-5454e23dda68') is distinct from v_appr then raise exception 'approved reading changed'; end if;
  if not exists (select 1 from pipeline.provider_policy_proposals where fact_source_id = v_src and parser = 'provider-policy-calendar-dates-v2' and status = 'proposed') then raise exception 'parser reading not proposed'; end if;
  select count(*) into n_q from pipeline.central_ai_queue where fact_source_id = v_src and state = 'queued';
  if n_q <> 1 or (select state from pipeline.calendar_reread_state where fact_source_id = v_src) <> 'sent_to_ai' then raise exception 're-read hand-off: % %', n_q, (select state from pipeline.calendar_reread_state where fact_source_id = v_src); end if;
  -- the same document, unchanged: not leased again
  v := public.svc_calendar_reread_next(60);
  if exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = v_src) then raise exception 'unchanged document leased again'; end if;
  raise notice 'PASS stored re-read: the parser''s reading is its own proposal, the approved one unchanged; not safe goes once to the existing AI queue; an unchanged document is not read again';
end $$;

-- process results: a dated measurement from saved results; a university without a usable calendar is routed to a person; the screen reads it
do $$
declare v jsonb; s jsonb; n_before int;
begin
  select count(*) into n_before from pipeline.process_results;
  v := security.process_results_record_v1();
  s := (select summary from pipeline.process_results where id = (v->>'id')::bigint);
  if (select count(*) from pipeline.process_results) <> n_before + 1 or jsonb_array_length(s->'universities') = 0 then raise exception 'process results: %', v; end if;
  if not exists (select 1 from jsonb_array_elements(s->'universities') x where x->>'university' = 'Harbour University' and (x->>'calendars_valid')::int >= 2
                  and jsonb_array_length(x->'calendars_set_aside') = 2 and (x->'held'->>'start_date')::int >= 3 and (x->'outcomes'->>'evidence_ambiguous')::int >= 1) then
    raise exception 'Harbour measurement: %', (select x from jsonb_array_elements(s->'universities') x where x->>'university' = 'Harbour University'); end if;
  if (select markdown from pipeline.process_results where id = (v->>'id')::bigint) not like '# Process record: intake dates (generated)%Harbour University%' then raise exception 'markdown'; end if;
  perform security.process_results_record_v1();
  if (select count(*) from pipeline.process_results where id > (v->>'id')::bigint) <> 1 then raise exception 'second measurement overwrote the first'; end if;
  raise notice 'PASS process results: dated measurements from saved results, nothing overwritten, markdown for the repository (flags raised: %)', v->>'flags';
end $$;

do $$
declare v jsonb; ok boolean := false;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  begin perform public.admin_process_results_v1('latest', '{}'::jsonb); exception when others then ok := sqlstate = '42501'; end;
  if not ok then raise exception 'anonymous read not refused'; end if;
  perform set_config('request.jwt.claim.sub', md5('admin')::uuid::text, true);
  v := public.admin_process_results_v1('latest', '{}'::jsonb);
  if v->'summary'->'universities' is null then raise exception 'latest: %', v; end if;
  v := public.admin_process_results_v1('university', jsonb_build_object('provider_id', '08609bcf-387d-1316-2a52-9fbc0edff508'));
  if jsonb_array_length(v->'calendars') < 4 or jsonb_array_length(v->'recent') = 0
     or not exists (select 1 from jsonb_array_elements(v->'recent') x where x->>'start_quote' = '22 February 2027 | Autumn session teaching begins' and x->>'calendar_url' = 'https://www.harbour.edu.au/key-dates/2027') then
    raise exception 'university view: %', left(v::text, 600); end if;
  if jsonb_array_length(public.admin_process_results_v1('history', '{}'::jsonb)) < 2 then raise exception 'history'; end if;
  raise notice 'PASS screen read: refused without sign-in; latest, history and one university''s calendars and decisions with their evidence';
end $$;
