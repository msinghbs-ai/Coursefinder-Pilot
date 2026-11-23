-- CF-247 s988 (session S2-INT; Platform Admin 23 Nov 2026 15:38 AEDT, decision on Rule B listing, part 3 of 3): Rule B (Decision 271) for Federation University Australia,
-- University of Canterbury and University of Waikato, where the official calendar gives an exact date; Southern Cross is NOT listed.
-- Decision text: "Approve and list Federation, Canterbury, and Waikato where the official calendar provides an exact date. Do NOT admit Southern Cross's June -> 5 July
-- month-to-day inference: keep that row held so we never publish inferred calendar days."
-- Read before building (rolled back, 23 Nov 2026): the qualification trial dates, by stated month: Federation March 1 Mar 2027 (26), July 26 Jul 2027 (15); Canterbury
-- February 22 Feb 2027 (20), July 19 Jul 2027 (15); Waikato March 1 Mar 2027 (27), July 12 Jul 2027 (28) and FEBRUARY -> 1 MARCH 2027 (2). Those two Waikato rows are the same
-- month-to-day step as Southern Cross's June -> 5 July (the page names one month, the calendar start falls in the next), so they are held, not admitted, by a recorded
-- "withdrawn" decision for that day (the planner never admits a value withdrawn before: a person decides). Every other date is a start in the stated month.
-- Southern Cross (status "qualified", 133 rows incl. June -> 5 July 34) is left as it is; "Approve all qualified" must be used with Southern Cross excluded until the
-- Platform Admin decides otherwise.
-- What this part does: applies Rule B and the planner for Canterbury
-- Dates come only from the planner (security.intake_dates_apply_v1: same planner, locks, provenance and fingerprints as the hourly job). No function, setting definition or
-- schedule changes; the list setting intake_dates.nearest_start_providers changes by the three ids, with reason and an admin_control_events row, as the approve function does.
-- G1: no job. G2: no number in code (row limits are counts of the selected courses' intakes). G3 stays 75/48. Manual locks unchanged (checked). Spend $0.
-- Replaces: nothing.
-- Retires: nothing. Nothing dropped, deleted or renamed. Reversal: remove the three ids from the list (Settings, chips) and withdraw days with security.intake_date_day_withdraw_v1.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: one planner run over the part's courses

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s988_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $r$
declare v_ids uuid[]; v_lim int; v_res jsonb; v_before int; v_after int;
begin
  if not (select s.value ? '9cc8ef21-52ec-4c18-849a-598ba1072459' and s.value ? 'db910e88-67d1-4d2b-a65c-cea290aa0692' and s.value ? '00e5f26c-446e-453c-a3fb-bc5239a4feec'
            from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers') then
    raise exception 's988: the three universities are not listed yet (part 1 not applied)';
  end if;
  select array_agg(distinct i.course_id) into v_ids from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where c.provider_id = any (array['db910e88-67d1-4d2b-a65c-cea290aa0692']::uuid[]) and i.status = 'active' and i.start_date is null;
  if v_ids is null then raise notice 's988: Canterbury: no course to apply'; return; end if;
  select count(*) into v_lim from catalogue.course_intakes where course_id = any (v_ids);
  select count(*) into v_before from catalogue.course_intakes where course_id = any (v_ids) and start_date is not null;
  v_res := security.intake_dates_apply_v1(v_lim, v_ids);
  select count(*) into v_after from catalogue.course_intakes where course_id = any (v_ids) and start_date is not null;
  raise notice 's988: Canterbury: % courses, apply %, intakes with an exact start % -> % (+%)', cardinality(v_ids), v_res, v_before, v_after, v_after - v_before;
  -- a Rule B date is a start in a month the page names, with its quote and calendar; a cross-month day is never admitted
  if exists (select 1 from catalogue.course_intakes i join pipeline.course_intake_dates d on d.intake_id = i.id
              where i.course_id = any (v_ids) and d.applied_at = now() and d.outcome = 'filled' and d.rule = 'calendar-v3-nearest-start'
                and (i.start_date is null or i.intake_label !~* to_char(i.start_date, 'Mon') or d.start_quote is null or d.calendar_url is null)) then
    raise exception 's988: a Rule B fill is outside the stated month or lacks its quote or calendar';
  end if;
end $r$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API drifted: %', v;
  end if;
  if (select n from s988_locks) <> (select count(*) from pipeline.manual_locks) then raise exception 'post-check: manual locks changed'; end if;
end $p$;
