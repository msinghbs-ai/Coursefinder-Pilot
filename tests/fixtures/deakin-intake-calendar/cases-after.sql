-- Guards: IQ-00313 (Deakin commencement-date contamination, 8 Nov 2026): migration 20261108050000 on the database cases-before.sql left contaminated.
-- Cross-year resolution (the year of a start comes from the evidence), course-specific eligibility and the unsupported-intake refusal (still in force, unchanged),
-- a far period is not taken, a rejected or withdrawn value is not admitted again, and the stored Website and Zoho items follow a withdrawal.
\set ON_ERROR_STOP on
\set QUIET on

-- 1 cross-year resolution: the year of a start comes from the evidence in the quote ----------------------------------------------------------
do $$
declare y0 int := public.fixture_dk_y0(); v_prop uuid := (select proposal_id from public.dk_cases where name = 'calendar'); r record; f text := '';
begin
  for r in select * from (values
    -- period, month, year, on_date, year_quote like
    ('trimester 1', 3, y0, make_date(y0, 3, 8), null),
    ('trimester 2', 7, y0, make_date(y0, 7, 12), null),
    ('trimester 3', 11, y0, make_date(y0, 11, 1), 'range ending ' || (y0 + 1) || ': the start falls in ' || y0),      -- the P0: starts 1 Nov, ends 28 Jan of the next year
    ('trimester 6', 11, y0 + 2, make_date(y0 + 2, 11, 1), null),                                                       -- the year is printed straight after the start date
    ('trimester 7', 1, y0, make_date(y0, 1, 5), null),                                                                   -- a range inside one year: the printed year
    ('trimester 8', 11, y0, make_date(y0, 11, 1), null),                                                                 -- "1 Nov <y> - 28 Jan <y+1>": the year after its own date
    ('trimester 9', 11, y0, make_date(y0, 11, 1), null),                                                                 -- the year printed before the date in the same quote
    ('research term 4', 10, y0, make_date(y0, 10, 4), 'range ending ' || (y0 + 1) || ': the start falls in ' || y0),     -- weekday before the end date
    ('trimester 10', 11, y0, make_date(y0, 11, 1), null)                                                                 -- calendar-v2.1 shape: its own starts array
  ) t(period, m, y, d, yq) loop
    if not exists (select 1 from security.calendar_proposal_dates_v1(v_prop) x where x.period = r.period and x.kind = 'start' and x.month = r.m and x.year = r.y and x.on_date = r.d
                      and (r.yq is null or x.year_quote = r.yq)) then f := f || ' ' || r.period; end if;
  end loop;
  -- no year is proved: a year printed after SEVERAL dates (a table row) is not the first date's, and a year the reader's own years do not list is dropped
  if exists (select 1 from security.calendar_proposal_dates_v1(v_prop) x where x.period in ('main intake 4', 'trimester 5') and x.kind = 'start' and (x.year is not null or x.on_date is not null)) then f := f || ' unproved-year'; end if;
  if f <> '' then raise exception 'resolver:%', f; end if;
  -- the year is "ok" for the plan only because the evidence for it is kept (year_quote), never because of today's date
  if not exists (select 1 from security.calendar_dated_periods_v2((select provider_id from public.dk_cases where name = 'calendar')) x where x.period = 'trimester 3' and x.kind = 'start' and x.year = y0 and x.year_ok) then
    raise exception 'trimester 3 year not proved by evidence'; end if;
  -- only the intended quotes changed: every other reading of the same calendar is identical to the production resolver's
  select string_agg(coalesce(n.period, o.period), ', ') into f from public.dk_old_dates o
    full join security.calendar_proposal_dates_v1(v_prop) n on n.period = o.period and n.kind = o.kind and n.month is not distinct from o.month
   where (n.year is distinct from o.year or n.on_date is distinct from o.on_date) and coalesce(n.period, o.period) not in ('trimester 3', 'trimester 5', 'research term 4', 'main intake 4');
  if f is not null then raise exception 'readings other than the intended changed: %', f; end if;
  raise notice 'PASS cross-year resolution: "Trimester 3: 1 Nov - 28 Jan %" is 1 November % (year of the end less one, kept as evidence in year_quote); an explicit year, a year before the date, a weekday range and a calendar-v2.1 start resolve as before; a year after several dates, or one the reader did not list, is not taken; no other reading of the calendar changed', y0 + 1, y0;
end $$;

-- 2 the plan: course-specific eligibility, the unsupported-intake refusal and the horizon (the courses not yet written) --------------------------
do $$
declare y0 int := public.fixture_dk_y0(); r record; f text := '';
begin
  for r in select k.name, p.outcome, p.reason, p.new_year, p.new_start, p.start_quote, p.rule, p.next_action from public.dk_cases k, lateral security.intake_dates_plan_v3(array[k.course_id], 10) p
            where k.name in ('cN', 'c12', 'cNone', 'cRef', 'cFar') loop
    f := f || case
      when r.name = 'cN' and not (r.outcome = 'filled' and r.new_start = make_date(y0, 11, 1) and r.new_year = y0 and r.rule = 'calendar-v3' and r.start_quote like 'Trimester 3: 1 Nov - 28 Jan %') then ' cN ' || row_to_json(r)::text
      when r.name = 'c12' and not (r.outcome = 'skipped' and r.new_start is null and r.reason = 'the named period does not start in this month') then ' c12 ' || row_to_json(r)::text
      when r.name = 'cNone' and not (r.outcome = 'skipped' and r.new_start is null and r.reason like 'the course page names no study period of the calendar%') then ' cNone ' || row_to_json(r)::text
      when r.name = 'cRef' and not (r.outcome = 'skipped' and r.new_start is null and r.reason like 'the course page does not state trimester 3 as its own intake (offering evidence missing%') then ' cRef ' || row_to_json(r)::text
      when r.name = 'cFar' and not (r.outcome = 'skipped' and r.new_start is null and r.reason like 'the year of the named period is not printed for the next cycle: its next dated start is more than 18 months away%'
                                    and r.next_action is not null) then ' cFar ' || row_to_json(r)::text
      else '' end;
  end loop;
  if f <> '' then raise exception 'plan:%', f; end if;
  raise notice 'PASS eligibility: the page that names Trimester 3 is dated 1 November % from the calendar; a page naming Trimesters 1 and 2 only, naming no period, or a personal account (the unsupported-intake refusal) takes no date; a period whose next dated start is more than 18 months away (Trimester 6) is held month-only', y0;
end $$;

-- the horizon is a setting (G2), read by the plan; raised, the far period is taken, at the default it is not
do $$
declare y0 int := public.fixture_dk_y0(); v_far uuid := (select course_id from public.dk_cases where name = 'cFar'); n date;
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.max_months_ahead' and kind = 'number' and unit = 'months'
                    and min_value = 6 and max_value = 36 and value = to_jsonb(18) and nullif(label, '') is not null and nullif(used_by, '') is not null and nullif(section, '') is not null) then
    raise exception 'setting intake_dates.max_months_ahead is not catalogued with label, range, unit and used_by'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(36) where toolset_key = 'pipeline' and key = 'intake_dates.max_months_ahead';
  select p.new_start into n from security.intake_dates_plan_v3(array[v_far], 10) p;
  update pipeline.platform_toolset_settings set value = to_jsonb(18) where toolset_key = 'pipeline' and key = 'intake_dates.max_months_ahead';
  if n is distinct from make_date(y0 + 2, 11, 1) then raise exception 'the horizon setting does not control the plan: %', n; end if;
  if (select p.new_start from security.intake_dates_plan_v3(array[v_far], 10) p) is not null then raise exception 'the default horizon does not hold'; end if;
  raise notice 'PASS horizon setting: intake_dates.max_months_ahead (18 months, range 6 to 36) is read by the plan; at 36 the far period is taken, at the default it is held';
end $$;

-- 3 the job: only the eligible, uncontaminated course is written; the contaminated four are not touched by the code fix (a correction is a person's) ----
do $$
declare y0 int := public.fixture_dk_y0(); v jsonb; r record; f text := '';
begin
  v := security.intake_dates_apply_v1(100, (select array_agg(course_id) from public.dk_cases where name in ('cN', 'c12', 'cNone', 'cRef', 'cFar', 'cA', 'cB', 'cC', 'cD')));
  for r in select k.name, i.start_date, i.intake_year from public.dk_cases k join catalogue.course_intakes i on i.id = k.intake_id where k.name in ('cN', 'c12', 'cNone', 'cRef', 'cFar', 'cA', 'cB', 'cC', 'cD') loop
    f := f || case
      when r.name = 'cN' and not (r.start_date = make_date(y0, 11, 1) and r.intake_year = y0) then ' cN ' || row_to_json(r)::text
      when r.name in ('c12', 'cNone', 'cRef', 'cFar') and (r.start_date is not null or r.intake_year is not null) then ' ' || r.name || ' ' || row_to_json(r)::text
      when r.name in ('cA', 'cB', 'cC', 'cD') and not (r.start_date = make_date(y0 + 1, 11, 1) and r.intake_year = y0 + 1) then ' ' || r.name || ' changed by the job ' || row_to_json(r)::text
      else '' end;
  end loop;
  if f <> '' then raise exception 'job:%', f; end if;
  perform public.fixture_dk_scan();   -- the stored items of the course the job wrote follow it, as the scans do within the hour
  raise notice 'PASS job: the fixed job wrote 1 November % to the eligible course only; the four contaminated intakes are left as they were (the code fix repairs no existing value: the governed withdrawal does)', y0;
end $$;

-- 4 a rejected calendar value is not used again -------------------------------------------------------------------------------------------
do $$
declare y0 int := public.fixture_dk_y0(); v_c record; p record; v_before date;
begin
  select * into v_c from public.dk_cases where name = 'cRej';
  select p2.new_start into v_before from security.intake_dates_plan_v3(array[v_c.course_id], 10) p2;
  if v_before is distinct from make_date(y0, 11, 1) then raise exception 'cRej is not eligible before the rejection: %', v_before; end if;
  insert into pipeline.intake_date_rejections(provider_id, proposal_id, quote, year, start_date, reason, case_ref, rejected_by)
  select v_c.provider_id, c.proposal_id, c.quote, c.year, c.on_date, 'fixture: a person rejected this reading of the calendar', 'IQ-00313', 'fixture'
    from security.calendar_dated_periods_v2(v_c.provider_id) c where c.period = 'trimester 3' and c.kind = 'start';
  if (select count(*) from pipeline.intake_date_rejections) <> 1 then raise exception 'rejection not recorded'; end if;
  select * into p from security.intake_dates_plan_v3(array[v_c.course_id], 10) x;
  if p.outcome <> 'skipped' or p.new_start is not null then raise exception 'a rejected calendar value was used again: %', row_to_json(p); end if;
  -- the table is kept for the process only
  if has_table_privilege('anon', 'pipeline.intake_date_rejections', 'select') or has_table_privilege('authenticated', 'pipeline.intake_date_rejections', 'select') then raise exception 'rejections readable by anon or authenticated'; end if;
  delete from pipeline.intake_date_rejections;   -- the fixture sets the rejection aside so the other cases see the whole calendar
  raise notice 'PASS rejection: a calendar value recorded in pipeline.intake_date_rejections is not used by the plan (the intake is held month-only); the table is closed to anon and authenticated';
end $$;

-- 5 the governed withdrawal, then no re-admission ------------------------------------------------------------------------------------------
do $$
declare y0 int := public.fixture_dk_y0(); a record; v jsonb; n_ev int; n_ev_after int;
begin
  select * into a from public.dk_cases where name = 'cA';
  select count(*) into n_ev from pipeline.course_intake_date_events where intake_id = a.intake_id;
  v := security.intake_date_withdraw_v1(a.intake_id, 'IQ-00313 fixture: Trimester 3 start dated a year late', 'fixture', true);
  if not (v->>'withdrawn')::boolean then raise exception 'withdraw: %', v; end if;
  if (select start_date from catalogue.course_intakes where id = a.intake_id) is not null or (select intake_year from catalogue.course_intakes where id = a.intake_id) is not null then raise exception 'date not reverted'; end if;
  select count(*) into n_ev_after from pipeline.course_intake_date_events where intake_id = a.intake_id;
  -- the original reading and event are kept; a withdrawn event is appended whose before_value is the rejected value
  if n_ev_after <> n_ev + 1 or not exists (select 1 from pipeline.course_intake_date_events where intake_id = a.intake_id and outcome = 'filled' and (after_value->>'start_date')::date = make_date(y0 + 1, 11, 1))
     or not exists (select 1 from pipeline.course_intake_date_events where intake_id = a.intake_id and outcome = 'withdrawn' and (before_value->>'start_date')::date = make_date(y0 + 1, 11, 1) and (before_value->>'year')::int = y0 + 1) then
    raise exception 'history: % / %', n_ev, n_ev_after; end if;
  if not exists (select 1 from pipeline.manual_locks where entity = 'course' and entity_id = a.course_id and field = 'intakes' and mode = 'value' and set_at is not null) then raise exception 'no hold'; end if;
  -- (a) the hold keeps every automated lane out: a changed input makes the plan look again, and it finds the hold
  update pipeline.course_intake_dates set inputs_fp = 'fixture: input changed' where intake_id = a.intake_id;
  if (select p.reason from security.intake_dates_plan_v3(array[a.course_id], 10) p) <> 'intakes locked by hand' then raise exception 'hold not respected: %', (select p.reason from security.intake_dates_plan_v3(array[a.course_id], 10) p); end if;
  raise notice 'PASS withdrawal: the 1 November % value is reverted (start date and year), the filled event and reading are kept, a withdrawn event holds the rejected value, the course is held (no automated lane writes it again)', y0 + 1;
end $$;

-- (b) with the hold lifted by a person, a calendar that still yields the withdrawn value cannot admit it again (rolled back: the calendar and hold are the fixture's)
begin;
do $$
declare y0 int := public.fixture_dk_y0(); a record; p record; v_reading uuid; v_orig uuid := (select proposal_id from public.dk_cases where name = 'calendar');
begin
  select * into a from public.dk_cases where name = 'cA';
  -- a person lifts the hold; a new approved reading of the calendar states the withdrawn year outright (a reader error, as in IQ-00313)
  delete from pipeline.manual_locks where entity = 'course' and entity_id = a.course_id and field = 'intakes';
  update pipeline.provider_policy_proposals set status = 'superseded' where id = v_orig;
  v_reading := public.fixture_calendar_for(a.provider_id, 'https://leadership.fixture-deakin.example/academic-calendars-2', 'ai:gpt-4.1-mini:calendar-v2.1', jsonb_build_object('scope', 'main_teaching', 'periods', jsonb_build_array(
    jsonb_build_object('period', 'trimester 3', 'months', jsonb_build_array(11), 'years', jsonb_build_array(y0 + 1), 'quotes', jsonb_build_array('Trimester 3: 1 Nov ' || (y0 + 1)),
       'starts', jsonb_build_array(jsonb_build_object('year', y0 + 1, 'month', 11, 'day', 1, 'date', null, 'quote', 'Trimester 3: 1 Nov ' || (y0 + 1), 'meaning', 'teaching_start')), 'deadlines', '[]'::jsonb))));
  update pipeline.platform_toolset_settings set value = to_jsonb(36) where toolset_key = 'pipeline' and key = 'intake_dates.max_months_ahead';   -- so only the withdrawn-value guard is in play
  update pipeline.course_intake_dates set inputs_fp = 'fixture: calendar changed' where intake_id = a.intake_id;
  select * into p from security.intake_dates_plan_v3(array[a.course_id], 10) x;
  if p.outcome <> 'skipped' or p.new_start is not null or p.reason not like 'withdrawn: %' or p.next_action <> 'human_decision_required' or p.next_revisit_at is not null then
    raise exception 'the withdrawn value was admitted again or not held for a person: %', row_to_json(p); end if;
  -- a different value (the true start) is not blocked: only the rejected value is
  update pipeline.provider_policy_proposals set status = 'superseded' where id = v_reading;
  update pipeline.provider_policy_proposals set status = 'approved' where id = v_orig;
  select * into p from security.intake_dates_plan_v3(array[a.course_id], 10) x;
  if p.outcome <> 'filled' or p.new_start <> make_date(y0, 11, 1) then raise exception 'the true start is blocked: %', row_to_json(p); end if;
  raise notice 'PASS no re-admission: with the hold lifted, a reading that states the withdrawn value outright is held for a person (human_decision_required, no revisit); only that value is refused: the true start, 1 November %, is not blocked', y0;
end $$;
rollback;

-- 6 the stored Website and Zoho items follow a withdrawal -----------------------------------------------------------------------------------
do $$
declare y0 int := public.fixture_dk_y0(); a record; b record; c record; v jsonb; w_seq0 bigint; z_seq0 bigint; w_seq1 bigint; z_seq1 bigint; s jsonb; wa jsonb; wb jsonb; za jsonb; zb jsonb;
begin
  select * into a from public.dk_cases where name = 'cA'; select * into b from public.dk_cases where name = 'cB'; select * into c from public.dk_cases where name = 'cC';
  -- cB is withdrawn too; cA's stored items are still the wrong ones (the withdrawal alone changed the catalogue and the projection document, not the stored items)
  v := security.intake_date_withdraw_v1(b.intake_id, 'IQ-00313 fixture: Trimester 3 start dated a year late', 'fixture', true);
  if not (v->>'withdrawn')::boolean then raise exception 'withdraw cB: %', v; end if;
  if not exists (select 1 from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = a.course_id and e->>'start_date' = make_date(y0 + 1, 11, 1)::text)
     or not exists (select 1 from pipeline.zoho_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = a.course_id and e->>'start_date' = make_date(y0 + 1, 11, 1)::text) then
    raise exception 'the stored items already followed (nothing to reconcile)'; end if;
  select w.seq, z.seq into w_seq0, z_seq0 from pipeline.website_sync_items w, pipeline.zoho_sync_items z where w.entity = 'course' and w.ref_id = a.course_id and z.entity = 'course' and z.ref_id = a.course_id;
  -- reconcile cA now; cB is left to the scheduled scans; cC (not withdrawn) is not named
  v := security.intake_projection_reconcile_v1(array[a.course_id]);
  if jsonb_array_length(v) <> 1 or (v->0->'website'->0->>'start_date') is not null or (v->0->'zoho'->0->>'start_date') is not null or (v->0->'website'->0->>'label') <> 'November' then
    raise exception 'reconcile result: %', v; end if;
  select w.seq, z.seq into w_seq1, z_seq1 from pipeline.website_sync_items w, pipeline.zoho_sync_items z where w.entity = 'course' and w.ref_id = a.course_id and z.entity = 'course' and z.ref_id = a.course_id;
  if w_seq1 <= w_seq0 or z_seq1 <= z_seq0 then raise exception 'the change was not announced to the sync (seq %->%, %->%)', w_seq0, w_seq1, z_seq0, z_seq1; end if;
  -- cC was not named: it still carries the old value (the correction is only for the courses a person withdrew)
  if not exists (select 1 from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and w.ref_id = c.course_id and e->>'start_date' = make_date(y0 + 1, 11, 1)::text) then
    raise exception 'reconcile touched a course it was not given'; end if;
  -- the production scans reach the same result: cA is already as they would leave it (no further change), cB is changed by them to the same shape
  s := public.fixture_dk_scan();
  select w.seq, z.seq into w_seq1, z_seq1 from pipeline.website_sync_items w, pipeline.zoho_sync_items z where w.entity = 'course' and w.ref_id = a.course_id and z.entity = 'course' and z.ref_id = a.course_id;
  if (s->'website'->>'changed')::int <> 1 or (s->'zoho'->>'changed')::int <> 1 then raise exception 'the scans changed % / % items (expected only cB)', s->'website'->>'changed', s->'zoho'->>'changed'; end if;
  if (select w.seq from pipeline.website_sync_items w where w.entity = 'course' and w.ref_id = a.course_id) <> w_seq1 then raise exception 'unreachable'; end if;
  select w.item->'intakes' into wa from pipeline.website_sync_items w where w.entity = 'course' and w.ref_id = a.course_id;
  select w.item->'intakes' into wb from pipeline.website_sync_items w where w.entity = 'course' and w.ref_id = b.course_id;
  select w.item->'intakes' into za from pipeline.zoho_sync_items w where w.entity = 'course' and w.ref_id = a.course_id;
  select w.item->'intakes' into zb from pipeline.zoho_sync_items w where w.entity = 'course' and w.ref_id = b.course_id;
  if wa is distinct from wb or za is distinct from zb or wa is distinct from za or wa::text like '%' || (y0 + 1) || '-11-01%' then raise exception 'reconciled and scanned items differ: % / % / % / %', wa, wb, za, zb; end if;
  if wa <> jsonb_build_array(jsonb_build_object('label', 'November', 'month', 11, 'year', null, 'start_date', null, 'application_deadline', null)) then raise exception 'item shape: %', wa; end if;
  raise notice 'PASS projections: after the withdrawal the stored Website item and the stored Zoho item of the course hold the intake month only (November, no year, no date) at once, announced to the sync (seq advanced); the production scans then change nothing for it, and bring the other withdrawn course to the identical item; a course not named is not touched';
end $$;

-- 7 the withdrawn decisions ------------------------------------------------------
do $$
begin
  if exists (select 1 from pipeline.course_intake_dates d join public.dk_cases k on k.intake_id = d.intake_id where k.name in ('cA', 'cB') and (d.outcome <> 'skipped' or d.next_action <> 'human_decision_required')) then
    raise exception 'withdrawn decisions are not held for a person'; end if;
  raise notice 'PASS decisions: the withdrawn intakes are skipped and held for a person (human_decision_required)';
end $$;
