-- Guards: F-INT page-date recovery (a start date the stored course page already prints is admitted on the next hourly run, not at the end of a 14-day revisit; the page reader reads
--   "Month D, YYYY" and year-heading lists and never takes a year heading for the year of the date before it; Platform Admin directive 10 Nov 2026 14:02),
--   AFTER migration 20261110170000. Proves: with the switch off the plan is identical to before (a held exact date aside); with it on, an undecided-for-the-date intake whose stored wording
--   prints a dated candidate is looked at on the next run and taken first, and is admitted only when corroborated (P1 or P2) exactly as before; every refusal still holds; a row is looked
--   at once and then settled; the page reader's new formats and the heading fix; a held exact date keeps its rule and quote; no central.* setting, no consumer function and no other
--   definition changes; the hourly plan stays within a bound.
\set ON_ERROR_STOP on
\set QUIET on

-- 0 the hint (read only) and the settings that must not move ---------------------------------------------------------------------------------------
do $$
declare f text := ''; fn regprocedure := 'security.intake_page_date_hint_v1(uuid,uuid,text)'::regprocedure; c uuid; e uuid;
begin
  if (select p.provolatile from pg_proc p where p.oid = fn) <> 's' or (select prosecdef from pg_proc p where p.oid = fn) is not true or pg_get_functiondef(fn) ~* '(net\.http|http_post|crawl\(|firecrawl|openrouter|pg_net|insert into|update |delete from)' then f := f || ' hint not read-only'; end if;
  if has_function_privilege('anon', fn, 'execute') or has_function_privilege('authenticated', fn, 'execute') or has_function_privilege('public', fn, 'execute') then f := f || ' hint executable by anon/authenticated/public'; end if;
  select k.course_id, i.evidence_id into c, e from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'rF1';
  if not security.intake_page_date_hint_v1(c, e, 'March') then f := f || ' March true'; end if;
  if security.intake_page_date_hint_v1(c, e, 'April') then f := f || ' April false'; end if;
  if security.intake_page_date_hint_v1(c, e, '') or security.intake_page_date_hint_v1(c, e, 'Marchtober') or security.intake_page_date_hint_v1(c, e, null) then f := f || ' bad label'; end if;
  for c, e in select k.course_id, i.evidence_id from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name in ('nMonth', 'nNone', 'u1') loop
    if security.intake_page_date_hint_v1(c, e, 'March') or security.intake_page_date_hint_v1(c, e, 'July') then f := f || ' hint true without a date'; end if;
  end loop;
  select k.course_id, i.evidence_id into c, e from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'eMDY';
  if not security.intake_page_date_hint_v1(c, e, 'March') then f := f || ' Month D, YYYY'; end if;
  select k.course_id, i.evidence_id into c, e from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'eHead';
  if not security.intake_page_date_hint_v1(c, e, 'March') or security.intake_page_date_hint_v1(c, e, 'April') then f := f || ' year heading'; end if;
  if exists (select 1 from (select toolset_key, key, value from pipeline.platform_toolset_settings where key like 'central.%' or key = 'intake_dates.month_unique_match') a full join public.pr_central_before b using (toolset_key, key) where a.value is distinct from b.value) then f := f || ' a central.* setting or the unique-month path changed'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit') <> to_jsonb(1) then f := f || ' switch'; end if;
  if f <> '' then raise exception 'hint/settings:%', f; end if;
  raise notice 'PASS PR hint and settings: the hint is stable, calls nothing outside the database, writes nothing and is closed to anon, authenticated and public; it is true for a month whose stored wording prints a dated candidate (day month year, month day year, year heading) and false for a month-only or empty wording, another month and a bad label; no central.* setting (central.auto_approve_calendar_dates ...) and not intake_dates.month_unique_match changed';
end $$;

-- 1 the switch off: the plan result is identical to before the migration (nothing carries the suffix, the order is today''s) ----------------------------------------------------
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
do $$
declare f text; n int;
begin
  select count(*), string_agg(coalesce(a.name, b.name), ',') into n, f from
    (select k.name, p.outcome, p.reason, p.new_year, p.new_start, p.new_deadline, p.start_precision, p.deadline_kind, p.start_quote, p.periods, p.next_action, p.rule, p.inputs_fp, p.next_revisit_at is null nr
       from security.intake_dates_plan_v3((select array_agg(course_id) from public.pr_d1), 200) p join public.pr_d1 k on k.intake_id = p.intake_id where k.name <> 'dRow') a
    full join (select name, outcome, reason, new_year, new_start, new_deadline, start_precision, deadline_kind, start_quote, periods, next_action, rule, inputs_fp, next_revisit_at is null nr from public.pr_off_before where name <> 'dRow') b using (name)
   where (a.outcome, a.reason, a.new_year, a.new_start, a.new_deadline, a.start_precision, a.deadline_kind, a.start_quote, a.periods, a.next_action, a.rule, a.inputs_fp, a.nr)
         is distinct from (b.outcome, b.reason, b.new_year, b.new_start, b.new_deadline, b.start_precision, b.deadline_kind, b.start_quote, b.periods, b.next_action, b.rule, b.inputs_fp, b.nr);
  if n <> 0 then raise exception 'with the switch off the plan differs from before the migration for: %', f; end if;
  raise notice 'PASS PR switch off: with intake_dates.page_date_admit = 0 the plan result (outcome, reason, dates, precision, quote, periods, next action, rule, fingerprint, revisit) of % intakes, the batch they are taken in included, is identical to the result before the migration; the held exact date (dRow) is kept as below', (select count(*) from public.pr_off_before) - 1;
end $$;
update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';

-- 2 the switch on, the hourly batch: the rows that print their date are looked at now and taken first ------------------------------------------------------------------
create table public.pr_gate_after as
select k.name, p.outcome, p.rule, p.reason from security.intake_dates_plan_v3((select array_agg(course_id) from public.pr_d1), 40) p join public.pr_d1 k on k.intake_id = p.intake_id;
do $$
declare f text := ''; n_r int; n_f int;
begin
  select count(*) filter (where name ~ '^r'), count(*) filter (where name ~ '^u') into n_r, n_f from public.pr_gate_after;
  if n_r <> 5 then f := f || ' ready rows planned ' || n_r; end if;
  if exists (select 1 from public.pr_gate_after where name in ('nMonth', 'nNone')) then f := f || ' a row with no date in its wording was looked at early'; end if;
  if not exists (select 1 from public.pr_gate_after where name in ('nJan', 'nDom', 'nClose')) then f := f || ' hint-true refusals not looked at'; end if;
  if exists (select 1 from public.pr_gate_after where name ~ '^r' and (outcome is distinct from 'filled' or rule is distinct from 'page-date-v1')) then f := f || ' ready rows not filled by the page route'; end if;
  if (select count(*) from public.pr_gate_after) > 40 then f := f || ' batch over its size'; end if;
  if n_f >= (select count(*) from public.pr_gate_before) then f := f || ' the filler still takes the whole batch'; end if;
  if f <> '' then raise exception 'gate:%', f; end if;
  raise notice 'PASS PR gate: with the switch on the batch of 40 now takes the 5 intakes whose page prints their date (decided before the switch, revisit 14 days away) and fills them (rule page-date-v1); before the migration it took 40 filler intakes and none of them; the batch size is unchanged (% rows), the filler gives way (% of %), and the intakes whose wording prints no date (nMonth, nNone) are not looked at early', (select count(*) from public.pr_gate_after), n_f, (select count(*) from public.pr_gate_before);
end $$;

-- 3 case by case: what is admitted and what is not, and why (each case on its own, so the batch does not decide) ---------------------------------------------------------
do $$
declare r record; f text := ''; n_fill int := 0; yA int := public.pr_dy(3, 1);
begin
  for r in select k.name, k.expect, k.new_start, p.outcome, p.reason, p.new_start ns, p.rule, p.start_quote, p.start_precision, p.deadline_kind, p.new_year, p.proposal_id, p.periods
             from public.pr_d1 k join lateral security.intake_dates_plan_v3(array[k.course_id], 10) p on true where k.name !~ '^u' and k.name <> 'dRow' order by k.name loop
    if r.name in ('nMonth', 'nNone') then continue; end if;      -- decided, wording unchanged, not looked at (section 2); asserted by the gate
    if r.outcome is distinct from r.expect or r.ns is distinct from r.new_start then f := f || ' ' || r.name || ': ' || coalesce(r.outcome, '-') || ' ' || coalesce(r.ns::text, '-') || ' (' || coalesce(r.reason, '') || ')'; continue; end if;
    if r.outcome = 'filled' then
      n_fill := n_fill + 1;
      if r.rule <> 'page-date-v1' or r.start_precision <> 'day' or r.deadline_kind <> 'not_stated' or r.start_quote is null or r.start_quote !~* '(start dates?|adapter pattern)' or (r.new_year is distinct from extract(year from r.ns)::int and not (r.name = 'eYear' and r.new_year is null)) then   -- eYear holds its year already: nothing to set
        f := f || ' ' || r.name || ' shape ' || row_to_json(r)::text; end if;
      if r.name like 'rF%' and (r.proposal_id is distinct from (select proposal_id from public.pr_d1_prov where name = 'Federation') or r.periods is distinct from array['semester 1'] and r.periods is distinct from array['semester 2']) then f := f || ' ' || r.name || ' corroboration ' || coalesce(r.periods::text, '-'); end if;
      if r.name like 'rC%' and (r.proposal_id is not null or r.start_quote not like '%[section label read by the university''s page adapter: Open for international admissions]') then f := f || ' ' || r.name || ' P2 ' || r.start_quote; end if;
    else
      if (case r.name when 'nJan' then r.reason like '%no approved main calendar start is on that day%' when 'nDom' then r.reason like '%page does not show the audience%'
                      when 'nClose' then r.reason like '%names no study period%' when 'eMis' then r.reason like '%which is past%' end) is not true then f := f || ' ' || r.name || ' reason ' || coalesce(r.reason, '-'); end if;
    end if;
  end loop;
  if f <> '' then raise exception 'cases:%', f; end if;
  raise notice 'PASS PR admit: % cases are admitted by the page route (day precision, no deadline, the stored snippet with its section label as the quote, the calendar proposal for Federation, the adapter label for Canberra): the 5 that were waiting for their revisit, "March 1, %", "March 1st, %", a year heading ("Start dates %: 1 Mar, 26 Jul"), the first list when a second year heading follows, a past date and the next one, and an intake that holds its year while the page prints two', n_fill, yA, yA, yA;
  raise notice 'PASS PR refuse, unchanged: page only (P3: 25 January shared with no approved calendar start; 15 February for domestic students), a closing date, and "1 Mar %: 11 Jan" is no longer read as 1 March % (the heading of the next list): 1 March is the date of the list above it, past, and is not admitted', yA, yA;
end $$;

-- 3b a held exact date keeps its rule and quote when its fingerprint changes (before: replaced by "skipped: names no study period") ------------------------------------------------------------
do $$
declare p record; k record; q0 text;
begin
  select * into k from public.pr_d1 where name = 'dRow';
  select d1.start_quote into q0 from pipeline.course_intake_dates d1 where d1.intake_id = k.intake_id;
  select * into p from security.intake_dates_plan_v3(array[k.course_id], 10);
  if p.intake_id is null or p.outcome is distinct from 'nothing_new' or p.rule is distinct from 'page-date-v1' or p.start_quote is distinct from q0 or p.start_precision <> 'day' or p.next_revisit_at is not null or p.new_start is not null then raise exception 'dRow: %', row_to_json(p); end if;
  create table public.pr_drow_quote as select q0 as quote;
  raise notice 'PASS PR held date, plan: an intake that holds its exact date from the page route keeps its rule (page-date-v1), its quote and its source when a new calendar changes its fingerprint (nothing_new, no revisit, no new date); on production code the same row was planned as "skipped: names no study period"';
end $$;

-- 4 the production job writes the fills as every fill is written; what was looked at settles (not looked at again every hour) ----------------------------------------------------------
do $$
declare v jsonb; r record; f text := ''; n int; yA int := public.pr_dy(3, 1);
begin
  v := security.intake_dates_apply_v1(40, (select array_agg(course_id) from public.pr_d1));
  for r in select k.name, k.expect, k.new_start, i.start_date, i.intake_year from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name !~ '^u' loop
    if r.name <> 'dRow' and r.expect = 'filled' and (r.start_date is distinct from r.new_start or r.intake_year is distinct from extract(year from r.new_start)::int) then f := f || ' ' || r.name || ' not written ' || coalesce(r.start_date::text, '-'); end if;
    if r.expect = 'skipped' and r.start_date is not null then f := f || ' ' || r.name || ' written ' || r.start_date; end if;
  end loop;
  -- a day never invented: the month-only and the filler rows hold no start date
  if exists (select 1 from public.pr_d1 k join catalogue.course_intakes i on i.id = k.intake_id where k.name ~ '^(nMonth|nNone|u)' and i.start_date is not null) then f := f || ' a day was invented'; end if;
  select count(*) into n from pipeline.course_intake_date_events e join public.pr_d1 k on k.intake_id = e.intake_id where e.rule = 'page-date-v1' and e.outcome = 'filled' and k.name <> 'dRow' and k.name ~ '^(r|e)'
     and e.start_precision = 'day' and e.start_quote is not null and (e.after_value->>'start_date')::date = k.new_start and e.before_value->>'start_date' is null;
  if n <> (select count(*) from public.pr_d1 where name ~ '^(r|e)' and expect = 'filled') then f := f || ' filled events ' || n; end if;
  if f <> '' then raise exception 'job:%', f; end if;
  -- settled: the rows just looked at (fills and refusals) are not planned again until an input changes or their revisit is due
  if exists (select 1 from security.intake_dates_plan_v3((select array_agg(course_id) from public.pr_d1 where name ~ '^(r|n|e)'), 40) p join public.pr_d1 k on k.intake_id = p.intake_id where k.name <> 'dRow') then
    raise exception 'rows looked at are planned again at once: %', (select string_agg(k.name, ',') from security.intake_dates_plan_v3((select array_agg(course_id) from public.pr_d1 where name ~ '^(r|n|e)'), 40) p join public.pr_d1 k on k.intake_id = p.intake_id); end if;
  raise notice 'PASS PR job: the production job wrote the % admitted dates (start date and year) and none of the others, no day for a month-only wording; each fill is one event (rule page-date-v1, day, quote, before null, after the date); the refusals and fills are settled (a second plan takes none of them again until an input changes)', (select count(*) from public.pr_d1 where name ~ '^(r|e)' and expect = 'filled');
end $$;

-- 5 the held exact date after the job ran: the decision keeps the rule and quote, the date does not move, and it is not planned again ------------------------------------------------------------------
do $$
declare k record; d record; q0 text := (select quote from public.pr_drow_quote);
begin
  select * into k from public.pr_d1 where name = 'dRow';
  perform security.intake_dates_apply_v1(10, array[k.course_id]);
  select * into d from pipeline.course_intake_dates x where x.intake_id = k.intake_id;
  if d.outcome <> 'nothing_new' or d.rule <> 'page-date-v1' or d.start_quote is distinct from q0 or d.next_revisit_at is not null then raise exception 'dRow decision: %', row_to_json(d); end if;
  if (select start_date from catalogue.course_intakes where id = k.intake_id) is distinct from k.new_start then raise exception 'dRow date moved'; end if;
  if exists (select 1 from security.intake_dates_plan_v3(array[k.course_id], 10)) then raise exception 'dRow planned again'; end if;
  raise notice 'PASS PR held date, job: the decision of the held exact date keeps rule page-date-v1 and its quote (outcome nothing_new, no revisit), the catalogue date is unchanged, and the row is not planned again';
end $$;

-- 6 the consumer path follows: the stored website and Zoho items carry the admitted date (no change to any consumer function) -----------------------------------------------------------
do $$
declare s jsonb; k record; f text := '';
begin
  s := public.fixture_dk_scan();
  for k in select * from public.pr_d1 where name in ('rF1', 'rC1', 'eMDY') loop
    if not exists (select 1 from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = k.course_id and e->>'start_date' = k.new_start::text)
       or not exists (select 1 from pipeline.zoho_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = k.course_id and e->>'start_date' = k.new_start::text) then f := f || ' ' || k.name; end if;
  end loop;
  if f <> '' then raise exception 'consumer items do not carry the admitted date:%', f; end if;
  raise notice 'PASS PR consumer path: the production scans carry the admitted dates (Federation, Canberra and "Month D, YYYY" cases) into the stored Website and Zoho items by the existing change check (nothing consumer-facing was edited)';
end $$;

-- 7 the hourly plan with the route on stays within a bound, and 200 waiting intakes are all taken in one run ------------------------------------------------------------------------------
do $$
declare yA int := public.pr_dy(3, 1); ids uuid[]; t0 timestamptz; t_off numeric; t_on numeric; n_on int; n_off int; h0 numeric; k record; v jsonb;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  for i in 1 .. 200 loop
    perform public.pr_d1_course('pf' || i, 'Federation', 'March', array['adapter pattern: 01 March ' || yA || ' 26 July ' || public.pr_dy(7, 26), 'Start dates 25 January ' || yA || ' 01 March ' || yA || ' 28 June ' || yA || ' 26 July ' || public.pr_dy(7, 26)], 'filled', make_date(yA, 3, 1));
  end loop;
  select array_agg(course_id) into ids from public.pr_d1 where name like 'pf%';
  perform search.refresh_course_enrichment_scoped_v1(ids, true);
  v := security.intake_dates_apply_v1(200, ids);                  -- decided month only with the route off: 14-day revisit
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  analyze pipeline.coverage_course_pages; analyze catalogue.course_intakes; analyze pipeline.evidence_artifacts; analyze pipeline.course_intake_dates;
  select count(*) into n_off from security.intake_dates_plan_v3(ids, 200) where false;
  t0 := clock_timestamp(); select count(*) filter (where new_start is not null) into n_on from security.intake_dates_plan_v3(ids, 200); t_on := extract(milliseconds from clock_timestamp() - t0);
  select * into k from public.pr_d1 where name = 'pf1';
  t0 := clock_timestamp();
  perform security.intake_page_date_hint_v1(k.course_id, (select evidence_id from catalogue.course_intakes where id = k.intake_id), 'March') from generate_series(1, 2000);
  h0 := extract(milliseconds from clock_timestamp() - t0) / 2000;
  if n_on <> 200 then raise exception 'perf: % of 200 waiting intakes planned as filled in one run', n_on; end if;
  if t_on > 60000 then raise exception 'the plan of 200 waiting rows is too slow: % ms', t_on; end if;   -- fixed: a gross regression bound for the fixture, not a setting
  if h0 > 5 then raise exception 'the hint is too slow: % ms a call', h0; end if;                       -- fixed: a gross regression bound for the fixture, not a setting
  raise notice 'PASS PR performance: 200 waiting intakes (revisit 14 days away) are all planned as filled in one run of the hourly plan (% ms); one hint costs % ms', round(t_on), round(h0, 3);
end $$;
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
