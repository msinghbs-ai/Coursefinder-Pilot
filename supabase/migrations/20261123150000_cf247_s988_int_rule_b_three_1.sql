-- CF-247 s988 (session S2-INT; Platform Admin 23 Nov 2026 15:38 AEDT, decision on Rule B listing, part 1 of 3): Rule B (Decision 271) for Federation University Australia,
-- University of Canterbury and University of Waikato, where the official calendar gives an exact date; Southern Cross is NOT listed.
-- Decision text: "Approve and list Federation, Canterbury, and Waikato where the official calendar provides an exact date. Do NOT admit Southern Cross's June -> 5 July
-- month-to-day inference: keep that row held so we never publish inferred calendar days."
-- Read before building (rolled back, 23 Nov 2026): the qualification trial dates, by stated month: Federation March 1 Mar 2027 (26), July 26 Jul 2027 (15); Canterbury
-- February 22 Feb 2027 (20), July 19 Jul 2027 (15); Waikato March 1 Mar 2027 (27), July 12 Jul 2027 (28) and FEBRUARY -> 1 MARCH 2027 (2). Those two Waikato rows are the same
-- month-to-day step as Southern Cross's June -> 5 July (the page names one month, the calendar start falls in the next), so they are held, not admitted, by a recorded
-- "withdrawn" decision for that day (the planner never admits a value withdrawn before: a person decides). Every other date is a start in the stated month.
-- Southern Cross (status "qualified", 133 rows incl. June -> 5 July 34) is left as it is; "Approve all qualified" must be used with Southern Cross excluded until the
-- Platform Admin decides otherwise.
-- What this part does: lists the three universities (setting, control event, qualification status) and records the hold on cross-month Waikato days; applies nothing
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

do $a$
declare v_ids uuid[] := array['9cc8ef21-52ec-4c18-849a-598ba1072459', 'db910e88-67d1-4d2b-a65c-cea290aa0692', '00e5f26c-446e-453c-a3fb-bc5239a4feec']::uuid[];  -- Federation, Canterbury, Waikato
        v_wk uuid := '00e5f26c-446e-453c-a3fb-bc5239a4feec'; v_before jsonb; v_after jsonb; v_reason text; v_cs uuid := 'f30cd2cd-01fc-458e-a061-b7aa5faa8a00'; v_n int; v_course uuid[]; v_lim int;
begin
  v_reason := 'Decision 271 (Rule B), Platform Admin 23 Nov 2026 15:38: list Federation, Canterbury and Waikato where the official calendar gives an exact date; Southern Cross not listed; cross-month days held';
  if (select count(*) from pipeline.intake_rule_b_qualifications q where q.provider_id = any (v_ids) and q.status in ('qualified', 'listed')) <> 3 then
    raise exception 's988: the three universities are not all qualified';
  end if;
  select s.value into v_before from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers' for update;
  v_after := coalesce(v_before, '[]'::jsonb) || coalesce((select jsonb_agg(x::text) from unnest(v_ids) x where not (coalesce(v_before, '[]'::jsonb) ? x::text)), '[]'::jsonb);
  update pipeline.platform_toolset_settings set value = v_after, reason = v_reason, updated_at = now() where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers';
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('toolsets', 'setting', 'pipeline.intake_dates.nearest_start_providers',
          jsonb_build_object('before', v_before, 'after', v_after, 'reason', v_reason, 'approved', to_jsonb(v_ids), 'via', 'cf247 s988 (Platform Admin decision 23 Nov 2026 15:38)'));
  update pipeline.intake_rule_b_qualifications q set status = 'listed', approved_at = now(), updated_at = now() where q.provider_id = any (v_ids) and q.status = 'qualified';
  if v_after ? v_cs::text then raise exception 's988: Southern Cross must not be listed'; end if;
  -- hold: Waikato intakes whose Rule B start falls in a month the page does not name (the planner's own output, not yet applied)
  select array_agg(distinct i.course_id) into v_course from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where c.provider_id = v_wk and i.status = 'active' and i.start_date is null;
  if v_course is not null then
    select count(*) into v_lim from catalogue.course_intakes where course_id = any (v_course);
    insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, reason, next_action, calendar_set, proposal_id, periods, start_precision,
                                                   deadline_kind, before_value, after_value, page_quote, start_quote, deadline_quote, calendar_url, calendar_evidence_id, bounded, related_case)
    select p.intake_id, p.course_id, p.provider_id, now(), 'withdrawal', 'withdrawn',
           left('cross-month day not admitted (Platform Admin decision 23 Nov 2026 15:38): the page names ' || i.intake_label || ' and the calendar start is ' || p.new_start::text, 500),
           null, p.calendar_set, p.proposal_id, p.periods, 'year', p.deadline_kind,
           jsonb_build_object('year', i.intake_year, 'start_date', p.new_start, 'application_deadline', i.application_deadline),
           jsonb_build_object('year', i.intake_year, 'start_date', null, 'application_deadline', i.application_deadline),
           p.page_quote, p.start_quote, null, p.calendar_url, p.calendar_evidence_id, false, 'F-INT Rule B'
      from security.intake_dates_plan_v3(v_course, v_lim) p join catalogue.course_intakes i on i.id = p.intake_id
     where p.rule = 'calendar-v3-nearest-start' and p.outcome = 'filled' and i.intake_label !~* to_char(p.new_start, 'Mon');
    get diagnostics v_n = row_count;
    raise notice 's988: % cross-month Waikato day(s) held', v_n;
  end if;
end $a$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API drifted: %', v;
  end if;
  if (select n from s988_locks) <> (select count(*) from pipeline.manual_locks) then raise exception 'post-check: manual locks changed'; end if;
end $p$;
