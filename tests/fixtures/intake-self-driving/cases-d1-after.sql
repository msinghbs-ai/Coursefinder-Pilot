-- Guards: F-INT D1 (a start date printed on the course page is admitted only when corroborated; default off; Platform Admin data population mandate, 9 Nov 2026),
--   AFTER migration 20261109042000. Proves: the switch (intake_dates.page_date_admit) is off by default and the plan is then identical to before; with it on, a date is
--   admitted only with P1 (an approved main-calendar start on that day) or P2 (the audience is evidenced) and every other rule of the instruction holds; page-only (P3),
--   a how-to-apply page, a rejected or withdrawn value, a lock, a hold and a date outside the horizon are never admitted; the fill is recorded as every fill is (events
--   by rule: gross, withdrawn, net) and reaches the consumer path; the helper reads only and spends nothing; the hourly plan stays fast with the route on.
\set ON_ERROR_STOP on
\set QUIET on

-- 0 the setting (G2) and the read-only helper -------------------------------------------------------------------------------------------------------
do $$
declare s record; f text := '';
begin
  select * into s from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  if s.key is null then raise exception 'setting missing'; end if;
  if s.value <> to_jsonb(0) or s.kind <> 'number' or s.min_value <> 0 or s.max_value <> 1 then f := f || ' default/range ' || row_to_json(s)::text; end if;
  if coalesce(s.label, '') = '' or coalesce(s.unit, '') = '' or coalesce(s.section, '') = '' or coalesce(s.used_by, '') = '' or coalesce(s.help, '') = '' or coalesce(s.reason, '') = '' then f := f || ' metadata ' || row_to_json(s)::text; end if;
  if exists (select 1 from pg_proc p where p.oid = 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'::regprocedure and (p.provolatile <> 's' or pg_get_functiondef(p.oid) ~* '(net\.http|http_post|crawl\(|firecrawl|openrouter|pg_net)')) then f := f || ' helper not read-only'; end if;
  if has_function_privilege('anon', 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)', 'execute') or has_function_privilege('authenticated', 'security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)', 'execute') then f := f || ' helper executable by anon/authenticated'; end if;
  if exists (select 1 from (select toolset_key, key, value from pipeline.platform_toolset_settings where key like 'central.%') a full join public.sd_d1_central_before b using (toolset_key, key)
              where a.value is distinct from b.value) then f := f || ' a central.* setting changed'; end if;
  if f <> '' then raise exception 'setting:%', f; end if;
  raise notice 'PASS D1 setting: intake_dates.page_date_admit is 0 (off) by default, number 0 to 1, with label, help, unit, section, used_by and reason; the helper is stable, calls nothing outside the database and is closed to anon and authenticated; no central.* setting (central.auto_approve_calendar_dates, central.calendar_excluded_words) is touched';
end $$;

-- 1 default off: the plan result of every case is identical to the result before the migration ----------------------------------------------------------
do $$
declare n int; f text;
begin
  select count(*), string_agg(a.name, ',') into n, f from public.sd_d1_before b join public.sd_d1 k on k.name = b.name
    join lateral security.intake_dates_plan_v3(array[k.course_id], 10) a2 on true
    cross join lateral (select k.name) a
   where (a2.outcome, a2.reason, a2.new_year, a2.new_start, a2.new_deadline, a2.start_precision, a2.deadline_kind, a2.start_quote, a2.periods, a2.next_action, a2.rule)
         is distinct from (b.outcome, b.reason, b.new_year, b.new_start, b.new_deadline, b.start_precision, b.deadline_kind, b.start_quote, b.periods, b.next_action, b.rule);
  if (select count(*) from public.sd_d1 k join lateral security.intake_dates_plan_v3(array[k.course_id], 10) a2 on true) <> (select count(*) from public.sd_d1_before) then raise exception 'with the switch off the plan returned another number of rows'; end if;
  if n <> 0 then raise exception 'with the switch off the plan differs from before the migration for: %', f; end if;
  raise notice 'PASS D1 default off: with intake_dates.page_date_admit = 0 the plan result (outcome, reason, dates, precision, quote, periods, next action, rule) of all % cases is identical to the result before the migration', (select count(*) from public.sd_d1_before);
end $$;

-- 2 the switch on: what is admitted, what is not, and why ----------------------------------------------------------------------------------------------
insert into pipeline.manual_locks(entity, entity_id, field, mode, set_at) select 'course', course_id, 'intakes', 'value', now() from public.sd_d1 where name = 'fLock';
insert into pipeline.course_remediation_holds(course_id, lifted_at) select course_id, null from public.sd_d1 where name = 'fHold';
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
do $$
declare r record; f text := ''; want text[]; n_fill int := 0; n_rows int := 0;
begin
  for r in select k.name, k.expect, k.new_start, p.outcome, p.reason, p.new_start ns, p.rule, p.start_quote, p.proposal_id, p.calendar_url, p.start_precision, p.deadline_kind, p.new_year, b.reason breason
             from public.sd_d1 k join lateral security.intake_dates_plan_v3(array[k.course_id], 10) p on true join public.sd_d1_before b on b.name = k.name order by k.name loop
    n_rows := n_rows + 1;
    if r.outcome is distinct from r.expect or r.ns is distinct from r.new_start then f := f || ' ' || r.name || ': ' || r.outcome || ' ' || coalesce(r.ns::text, '-') || ' (' || coalesce(r.reason, '') || ')'; continue; end if;
    if r.outcome = 'filled' then
      n_fill := n_fill + 1;
      if r.rule <> 'page-date-v1' or r.start_precision <> 'day' or r.deadline_kind <> 'not_stated' or r.start_quote is null or r.start_quote !~* '(start dates?|adapter pattern)' or r.new_year is distinct from extract(year from r.ns)::int then
        f := f || ' ' || r.name || ' shape ' || row_to_json(r)::text; end if;
    else
      if r.name in ('fNoYear', 'fClose') then
        if r.reason is distinct from r.breason then f := f || ' ' || r.name || ' changed: ' || r.reason; end if;   -- no full date in the month: the calendar route decides, as before
      else
        want := case r.name
          when 'fJan' then array['%no approved main calendar start is on that day%'] when 'fPath' then array['%no approved main calendar start is on that day%']
          when 'cDom' then array['%page does not show the audience%'] when 'cMix' then array['%page does not show the audience%']
          when 'mFeb' then array['%page does not show the audience%'] when 'wFeb' then array['%page does not show the audience%']
          when 'fNoLabel' then array['%without a section label%'] when 'fRange' then array['%range of days%'] when 'fTwo' then array['%several different%']
          when 'fPast' then array['%which is past%'] when 'fFar' then array['%months away%'] when 'dFar' then array['%months away%'] when 'dRej' then array['%months away%'] when 'dWd' then array['%months away%'] when 'fYear' then array['%intake is for%']
          when 'fLock' then array['intakes locked by hand'] when 'fHold' then array['course held'] when 'aHow' then array['page not proved to be the course''s own%', 'page refused for this course']
          when 'xMar' then array['no valid academic calendar%'] end;
        if want is null or not exists (select 1 from unnest(want) w where r.reason like w) then f := f || ' ' || r.name || ' reason ' || coalesce(r.reason, '-'); end if;
      end if;
    end if;
  end loop;
  if n_rows <> (select count(*) from public.sd_d1) then raise exception 'the plan returned % of % cases', n_rows, (select count(*) from public.sd_d1); end if;
  if f <> '' then raise exception 'page-date plan:%', f; end if;
  raise notice 'PASS D1 admit: with the switch on, % cases are admitted (rule page-date-v1, day precision, no deadline, the stored snippet as the quote, the year of the date): Federation 1 March and 26 July (P1), Canberra 15 February and 9 August (P2, adapter and page), Adelaide''s own page (P1)', n_fill;
  raise notice 'PASS D1 refuse: not admitted, each with its reason: page only (P3: a date no approved main calendar start shares and the page does not attribute to an audience: Federation 25 January, Macquarie, Western Sydney-like, a domestic or mixed audience), a pathway start (excluded), a closing date, a range, two dates, no label, past, beyond 18 months, another year than the intake''s, a lock, a hold, a how-to-apply page (E16), and a university with no valid calendar; a month with no full date is decided by the calendar route as before';
end $$;

-- the unique-month path (intake_dates.month_unique_match, off in production) is not pre-empted by a page that is not admitted: it decides as before
begin;
do $$
declare p record; b record;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  select * into p from security.intake_dates_plan_v3(array[(select course_id from public.sd_d1 where name = 'fTwo')], 10);
  if p.intake_id is null or p.reason like '%page date not admitted%' or p.rule = 'page-date-v1' then raise exception 'the page route pre-empted the unique-month path: %', row_to_json(p); end if;
  raise notice 'PASS D1 order: with intake_dates.month_unique_match on, a page that is not admitted (two dates in the month) falls through to the unique-month path (rule %, outcome %)', p.rule, p.outcome;
end $$;
rollback;

-- the quote and the corroboration that are stored for a fill
do $$
declare p record; f text := '';
begin
  select * into p from security.intake_dates_plan_v3(array[(select course_id from public.sd_d1 where name = 'fMar')], 10);
  if p.start_quote not like 'Start dates 25 January %01 March %' or p.proposal_id is distinct from (select proposal_id from public.sd_d1_prov where name = 'Federation') or p.calendar_url <> 'https://leadership.fixture-d1fed.example/key-dates'
     or p.periods is distinct from array['semester 1'] then f := f || ' P1 ' || row_to_json(p)::text; end if;
  select * into p from security.intake_dates_plan_v3(array[(select course_id from public.sd_d1 where name = 'cFeb')], 10);
  if p.start_quote not like 'adapter pattern: 15 February % | 09 August %[section label read by the university''s page adapter: Open for international admissions]' or p.proposal_id is not null
     or p.calendar_url not like '%/master-of-calendar-case-%' then f := f || ' P2 ' || row_to_json(p)::text; end if;
  select * into p from security.intake_dates_plan_v3(array[(select course_id from public.sd_d1 where name = 'cPage')], 10);
  if p.start_quote <> 'International students: start dates 15 February ' || public.sd_dy(2, 15) then f := f || ' P2 page ' || p.start_quote; end if;
  if f <> '' then raise exception 'quotes:%', f; end if;
  raise notice 'PASS D1 evidence stored: P1 keeps the page snippet that holds the section label as the quote (Start dates ...), the approved calendar''s proposal, URL and period; P2 keeps the adapter snippet with the section label the adapter reads, and no calendar proposal; a page that names its audience is quoted as printed';
end $$;

-- 3 the production job writes the fills as every fill is written; gross, withdrawn and net can be measured by rule ----------------------------------------------
do $$
declare v jsonb; r record; f text := ''; n int; g int; w int;
begin
  v := security.intake_dates_apply_v1(100, (select array_agg(course_id) from public.sd_d1));
  for r in select k.name, k.expect, k.new_start, i.start_date, i.intake_year from public.sd_d1 k join catalogue.course_intakes i on i.id = k.intake_id loop
    if r.expect = 'filled' and (r.start_date is distinct from r.new_start or r.intake_year is distinct from extract(year from r.new_start)::int) then f := f || ' ' || r.name || ' not written ' || coalesce(r.start_date::text, '-'); end if;
    if r.expect = 'skipped' and r.start_date is not null then f := f || ' ' || r.name || ' written ' || r.start_date; end if;
  end loop;
  select count(*) into n from pipeline.course_intake_date_events e join public.sd_d1 k on k.intake_id = e.intake_id where e.rule = 'page-date-v1' and e.outcome = 'filled'
     and e.start_precision = 'day' and e.start_quote is not null and (e.after_value->>'start_date')::date = k.new_start and e.before_value->>'start_date' is null;
  if n <> (select count(*) from public.sd_d1 where expect = 'filled') then f := f || ' filled events ' || n; end if;
  if exists (select 1 from pipeline.course_intake_dates d join public.sd_d1 k on k.intake_id = d.intake_id where k.expect = 'filled' and (d.outcome <> 'filled' or d.rule is distinct from 'page-date-v1' or d.start_quote is null)) then f := f || ' decision rows'; end if;
  if f <> '' then raise exception 'job:%', f; end if;
  -- gross, withdrawn and net by rule: one fill is withdrawn by a person (the governed path)
  v := security.intake_date_withdraw_v1((select intake_id from public.sd_d1 where name = 'fJul'), 'D1 fixture: a person withdraws the page date', 'fixture', true);
  if not (v->>'withdrawn')::boolean then raise exception 'withdraw: %', v; end if;
  select count(*) filter (where e.outcome = 'filled' and e.rule = 'page-date-v1'), count(*) filter (where e.outcome = 'withdrawn') into g, w
    from pipeline.course_intake_date_events e where e.intake_id in (select intake_id from public.sd_d1) and (e.rule = 'page-date-v1' or e.outcome = 'withdrawn');
  if g <> 6 or w <> 1 then raise exception 'gross % withdrawn % (expected 6 and 1)', g, w; end if;
  raise notice 'PASS D1 job and events: the production job wrote the 6 admitted dates (start date and year) and none of the others; each fill is one event (rule page-date-v1, day, quote, before null, after the date) and one decision row; after a governed withdrawal the rule''s gross is %, withdrawn %, net %', g, w, g - w;
end $$;

-- 4 the consumer path follows: the stored website and Zoho items carry the admitted date (no change to any consumer function) ---------------------------------------------
do $$
declare s jsonb; k record; f text := '';
begin
  s := public.fixture_dk_scan();
  for k in select * from public.sd_d1 where name in ('fMar', 'cFeb', 'aOwn') loop
    if not exists (select 1 from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = k.course_id and e->>'start_date' = k.new_start::text)
       or not exists (select 1 from pipeline.zoho_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = k.course_id and e->>'start_date' = k.new_start::text) then f := f || ' ' || k.name; end if;
  end loop;
  if f <> '' then raise exception 'consumer items do not carry the admitted date:%', f; end if;
  raise notice 'PASS D1 consumer path: the production scans carry the admitted dates (Federation, Canberra, Adelaide cases) into the stored Website and Zoho items by the existing change check (nothing consumer-facing was edited)';
end $$;

-- 5 a withdrawn value and a rejected value are never admitted again; Deakin 1 November 2028 ------------------------------------------------------------------
begin;
do $$
declare p record; k record; v jsonb; n int;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(36) where toolset_key = 'pipeline' and key = 'intake_dates.max_months_ahead';   -- so only the guard under test is in play
  update pipeline.course_intake_dates set inputs_fp = 'fixture: input changed' where intake_id in (select intake_id from public.sd_d1 where name in ('dRej', 'dWd', 'dFar'));   -- the plan looks again
  -- without the guard the calendar corroborates the page: 1 November 2028 would be admitted (this is what the guards stop)
  select * into p from security.intake_dates_plan_v3(array[(select course_id from public.sd_d1 where name = 'dRej')], 10);
  if p.intake_id is null or p.outcome is distinct from 'filled' or p.new_start is distinct from date '2028-11-01' then raise exception 'the guards are not what stops 1 November 2028 (plan: %)', row_to_json(p); end if;
  -- a rejected value
  select * into k from public.sd_d1 where name = 'dRej';
  insert into pipeline.intake_date_rejections(provider_id, proposal_id, quote, year, start_date, reason, case_ref, rejected_by)
  select k.provider_id, c.proposal_id, c.quote, c.year, c.on_date, 'fixture: a person rejected 1 November 2028', 'IQ-00313', 'fixture' from security.calendar_dated_periods_v2(k.provider_id) c where c.period = 'trimester 3' and c.kind = 'start';
  select * into p from security.intake_dates_plan_v3(array[k.course_id], 10);
  if p.intake_id is null or p.outcome is distinct from 'skipped' or p.new_start is not null or p.reason not like '%recorded as rejected%' then raise exception 'rejected value admitted or not held: %', row_to_json(p); end if;
  select * into p from security.intake_dates_plan_v3(array[(select course_id from public.sd_d1 where name = 'dFar')], 10);
  if p.intake_id is null or p.new_start is not null or p.reason not like '%recorded as rejected%' then raise exception 'the rejection of the value does not hold for the university''s other course: %', row_to_json(p); end if;
  delete from pipeline.intake_date_rejections;
  -- a withdrawn value: filled by the page route, withdrawn by a person, the hold lifted, the page and the calendar still print it
  select * into k from public.sd_d1 where name = 'dWd';
  v := security.intake_dates_apply_v1(100, array[k.course_id]);
  if (select start_date from catalogue.course_intakes where id = k.intake_id) is distinct from date '2028-11-01' then raise exception 'dWd not filled for the withdrawal case'; end if;
  v := security.intake_date_withdraw_v1(k.intake_id, 'IQ-00313 fixture: 1 November 2028 withdrawn', 'fixture', true);
  if not (v->>'withdrawn')::boolean then raise exception 'withdraw: %', v; end if;
  delete from pipeline.manual_locks where entity = 'course' and entity_id = k.course_id and field = 'intakes';
  update pipeline.course_intake_dates set inputs_fp = 'fixture: input changed' where intake_id = k.intake_id;
  select * into p from security.intake_dates_plan_v3(array[k.course_id], 10);
  if p.intake_id is null or p.outcome is distinct from 'skipped' or p.new_start is not null or p.reason not like 'withdrawn:%' or p.next_action is distinct from 'human_decision_required' or p.next_revisit_at is not null then raise exception 'withdrawn value admitted or not held for a person: %', row_to_json(p); end if;
  raise notice 'PASS D1 Deakin: 1 November 2028 is admitted by the page route only when nothing guards it (calendar and page agree, horizon 36); it is not admitted when rejected, and not admitted again after a withdrawal even with the hold lifted (held for a person, no revisit); at the default horizon it is beyond 18 months';
end $$;
rollback;

-- 6 the hourly plan with the route on stays cheap ----------------------------------------------------------------------------------------------------------
do $$
declare yA int := public.sd_dy(3, 1); ids uuid[]; t0 timestamptz; t_off numeric; t_on numeric; n_on int; n_off int; helper_ms numeric; c uuid; k record; j jsonb;
begin
  for i in 1 .. 300 loop
    perform public.sd_d1_course('perf' || i, 'Federation', 'March', array['adapter pattern: 01 March ' || yA || ' 26 July ' || public.sd_dy(7, 26), 'Start dates 25 January ' || yA || ' 01 March ' || yA || ' 28 June ' || yA || ' 26 July ' || public.sd_dy(7, 26)], 'filled', make_date(yA, 3, 1));
  end loop;
  select array_agg(course_id) into ids from public.sd_d1 where name like 'perf%';
  analyze pipeline.coverage_course_pages; analyze catalogue.course_intakes; analyze pipeline.evidence_artifacts;
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  perform count(*) from security.intake_dates_plan_v3(ids, 200);   -- warm
  t0 := clock_timestamp(); select count(*) filter (where new_start is not null) into n_off from security.intake_dates_plan_v3(ids, 200); t_off := extract(milliseconds from clock_timestamp() - t0);
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  t0 := clock_timestamp(); select count(*) filter (where new_start is not null) into n_on from security.intake_dates_plan_v3(ids, 200); t_on := extract(milliseconds from clock_timestamp() - t0);
  select * into k from public.sd_d1 where name = 'perf1' ;
  t0 := clock_timestamp();
  perform security.intake_page_date_v1(k.provider_id, k.intake_id, k.course_id, (select evidence_id from catalogue.course_intakes where id = k.intake_id), (select source_url from pipeline.evidence_artifacts where id = (select evidence_id from catalogue.course_intakes where id = k.intake_id)),
          3, null, (select jsonb_agg(to_jsonb(s)) from security.calendar_dated_periods_v2(k.provider_id) s), (now() at time zone 'Australia/Melbourne')::date, 18) from generate_series(1, 2000);
  helper_ms := extract(milliseconds from clock_timestamp() - t0) / 2000;
  if n_off <> 0 or n_on <> 200 then raise exception 'perf cases: off fills %, on fills % (expected 0 and 200)', n_off, n_on; end if;
  if t_on > t_off * 4 + 3000 then raise exception 'the plan with the route on is too slow: % ms against % ms with it off (200 rows)', t_on, t_off; end if;   -- fixed: a gross regression bound, not a setting
  raise notice 'PASS D1 performance: the hourly plan of 200 rows takes % ms with the route off and % ms with it on (200 admitted); one check of a page (two stored snippets, a 3-start calendar) takes % ms', round(t_off), round(t_on), round(helper_ms, 2);
end $$;
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
