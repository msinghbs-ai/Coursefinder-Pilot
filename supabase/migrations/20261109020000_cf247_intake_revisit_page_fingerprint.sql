-- CF-247 F-INT (valid course intake dates; Platform Admin data population first delivery mandate, 9 Nov 2026): the intake pipeline looks again at the rows
-- that wait for evidence, and at a course whose page was read again, without a person starting it.
-- Why (measured read-only on production, 9 Nov 2026 07:20 AEDT):
--   * 14,959 undated active intake rows hold a decision in pipeline.course_intake_dates. 8,793 of them are held for a reason that stored evidence can
--     change (next_action evidence_ambiguous 7,733, reader_correction_needed 867, calendar_needs_correction 193) and none has a revisit time:
--     security.intake_failure_class_trg_v1 sets next_revisit_at to null for every deterministic failure class (mandate 5 Nov 2026 section 9: an unchanged
--     deterministic failure is never repeated on a timer). The plan skips a row whose inputs fingerprint is unchanged and whose revisit time is null, so
--     these rows wait for a change of the calendar set, the evidence id, the course URL or a setting, and nothing else.
--   * The fingerprint (security.intake_inputs_fp_v1) holds the calendar set, the evidence id, the course URL and the settings, but not the wording of the
--     course page (security.intake_page_wording_v1), which is what the plan reads. A page read again (pipeline.coverage_course_pages.read_at) with the same
--     evidence id and new intake wording changes nothing the plan looks at, so the row is not re-queued. 81 decided rows have a page read after their decision.
-- What (existing architecture; no new job, scheduler, engine, table or screen):
--   D3  a row held as evidence_ambiguous, reader_correction_needed, calendar_needs_correction or human_decision_required is looked at again after
--       intake_dates.revisit_days (14) from the STORED inputs only (the plan and the apply function call no crawler, reader or AI: a revisit re-reads the
--       stored page wording, calendar and settings). Switch: setting intake_dates.revisit_stored_inputs (1 on, 0 off).
--         1 security.intake_revisit_stored_inputs_v1 (new): the one place that names the four next actions and reads the switch.
--         2 security.intake_revisit_at_v1 (md5-guarded edit, 30790a1c): the revisit time also for those four.
--         3 security.intake_failure_class_trg_v1 (md5-guarded edit, 1ce780aa): a deterministic failure of those four gets the revisit time; every other
--           deterministic failure still has none. A revisit changes nothing else: the rejected-value memory (pipeline.intake_date_rejections), the
--           withdrawn-value guard, locks and the page checks are in the plan and run on every look.
--         4 security.intake_progress_repeats_v1 (md5-guarded edit, 4f3d0930): a deterministic refusal that repeats because its own revisit time passed
--           is classified excluded_scheduled_revisit (shown, never raised), so the by-design look does not raise intake-progress:repeated-deterministic.
--         5 rows already waiting: a spread revisit time over the next intake_dates.revisit_days days (no storm), for the undated active rows only.
--   D2  the fingerprint also holds the page wording: security.intake_wording_fp_v1 (new, order-insensitive md5 of the stored wording) is added to the
--       fingerprint in security.intake_dates_plan_v3 (md5-guarded edit, 27f5b2a6; the stored fingerprint and the skip test change together).
--         Storm guard: rows already settled get their stored fingerprint rewritten to the new form in this migration, so only a row whose page was read
--         after its decision (or whose inputs differ) is looked at again. The wording is read only for rows that already hold a decision.
-- Course-specific proof is unchanged: no gate, rule, calendar reading or date is edited, and no date is written by this migration.
-- Setting (G2): intake_dates.revisit_stored_inputs with label, range, unit and used_by; the days are the existing intake_dates.revisit_days.
-- Consumer API: unchanged (G3). Only security.* functions, a setting and pipeline.course_intake_dates rows (timer and fingerprint) are touched.
-- Replaces: md5-guarded edits of security.intake_revisit_at_v1, security.intake_failure_class_trg_v1, security.intake_progress_repeats_v1 and security.intake_dates_plan_v3
-- Retires: nothing (the rule "a deterministic failure has no timer" stays for every class except the four named; the old fingerprint form is replaced in place)
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

-- 0 setting (G2) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.revisit_stored_inputs', 'Intake dates: look again at a row held for evidence, from stored inputs',
  'When on, an intake row held as evidence ambiguous, reader correction needed, calendar needs correction or human decision required is looked at again after the number of days in "Intake dates: look again at a waiting row after". The look uses only what is already stored (the course page wording, the approved calendar and the settings); it calls no crawler, reader or AI and spends nothing. A date rejected or withdrawn earlier is never admitted again, and the course-specific proof rules are the same. When off, such a row waits for a change of its inputs only.',
  'number', to_jsonb(1), 0, 1, 'on/off', 1013, 'Intake dates',
  'security.intake_revisit_stored_inputs_v1; security.intake_revisit_at_v1; security.intake_failure_class_trg_v1; job intake-dates-apply',
  'F-INT (9 Nov 2026): 8,793 undated intake rows held for evidence had no revisit time and were never looked at again')
on conflict (toolset_key, key) do nothing;

-- 1 D3: the one place that names the four next actions and reads the switch -------------------------------------------------------------------
create or replace function security.intake_revisit_stored_inputs_v1(p_next_action text) returns boolean
language sql stable security definer set search_path to '' as $function$
  select p_next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required')
         and security.pipeline_num_v1('intake_dates.revisit_stored_inputs', 1) = 1
$function$;
comment on function security.intake_revisit_stored_inputs_v1(text) is 'CF-247 F-INT (9 Nov 2026): true when a row held with this next action is looked at again from its stored inputs on the revisit timer (setting intake_dates.revisit_stored_inputs, on by default). The four actions: evidence_ambiguous, reader_correction_needed, calendar_needs_correction, human_decision_required.';
revoke all on function security.intake_revisit_stored_inputs_v1(text) from public, anon, authenticated;

-- 2 D3: the revisit time (md5-guarded edit) -------------------------------------------------------------------------------------------------
select pg_temp.edit('security.intake_revisit_at_v1(text)', '30790a1cdb910a25012d2cc8fa938dbc', 'intake_revisit_stored_inputs_v1',
  array[$o$'ready_for_scheduled_recovery')$o$],
  array[$n$'ready_for_scheduled_recovery')
              or security.intake_revisit_stored_inputs_v1(p_next_action)$n$],
  array[1]);
comment on function security.intake_revisit_at_v1(text) is 'CF-247 (decision 5 Nov 2026 section 8; F-INT 9 Nov 2026): when a waiting row is looked at again without a change (intake_dates.revisit_days after now). The waiting actions awaiting_official_calendar, course_identity_unresolved, waiting_for_next_academic_year, budget_or_operational_limit and ready_for_scheduled_recovery, and, while intake_dates.revisit_stored_inputs is on, evidence_ambiguous, reader_correction_needed, calendar_needs_correction and human_decision_required.';

-- 3 D3: the failure-class trigger no longer removes the revisit time of those four (md5-guarded edit) -------------------------------------------
select pg_temp.edit('security.intake_failure_class_trg_v1()', '1ce780aa6cbde2c9a1d9307c3cd68a53', 'intake_revisit_stored_inputs_v1',
  array[$o$if c.deterministic then new.next_revisit_at := null;$o$],
  array[$n$if c.deterministic then
    -- F-INT 9 Nov 2026: the four actions that stored evidence can change are looked at again on the revisit timer (setting intake_dates.revisit_stored_inputs);
    -- every other deterministic failure still waits for a change of its inputs only
    new.next_revisit_at := case when security.intake_revisit_stored_inputs_v1(new.next_action) then security.intake_revisit_at_v1(new.next_action) end;$n$],
  array[1]);
comment on function security.intake_failure_class_trg_v1() is 'CF-247 (decision 5 Nov 2026 section 9; F-INT 9 Nov 2026): classifies each intake decision. A deterministic failure has no revisit time (an unchanged failure is never repeated on a timer) except evidence_ambiguous, reader_correction_needed, calendar_needs_correction and human_decision_required, which are looked at again from stored inputs after intake_dates.revisit_days while intake_dates.revisit_stored_inputs is on. A held or exception class without a time gets the revisit time as before.';

-- 4 D3: a look on the row's own revisit time is not an unchanged repeat to raise (md5-guarded edit) ----------------------------------------------
select pg_temp.edit('security.intake_progress_repeats_v1()', '4f3d0930df6777edb2a915533e379efb', 'excluded_scheduled_revisit',
  array[$o$p.reader p_reader, p.rule p_rule$o$,
        $o$when exists (select 1 from st where st.at > ev.p_at and st.at < ev.run_at) then 'excluded_setting_change'$o$,
        $o$'excluded_setting_change', (select count(distinct k.intake_id) from k where k.status = 'excluded_setting_change'),$o$],
  array[$n$p.reader p_reader, p.rule p_rule, p.next_revisit_at p_revisit$n$,
        $n$when exists (select 1 from st where st.at > ev.p_at and st.at < ev.run_at) then 'excluded_setting_change'
          -- F-INT 9 Nov 2026: the earlier decision set a revisit time and this look is on or after it: a scheduled look, not an unchanged repeat
          when ev.p_revisit is not null and ev.run_at >= ev.p_revisit then 'excluded_scheduled_revisit'$n$,
        $n$'excluded_setting_change', (select count(distinct k.intake_id) from k where k.status = 'excluded_setting_change'),
    'excluded_scheduled_revisit', (select count(distinct k.intake_id) from k where k.status = 'excluded_scheduled_revisit'),$n$],
  array[1, 1, 1]);

-- 5 D2: the wording of the stored course page, as one fingerprint part ----------------------------------------------------------------------
-- order-insensitive (the wording is a set of stored quotes joined in an unspecified order), so only a change of what the page says changes it
create or replace function security.intake_wording_fp_v1(p_course uuid, p_evidence uuid) returns text
language sql stable security definer set search_path to '' as $function$
  select md5(coalesce((select string_agg(s, '|' order by s)
                         from (select distinct s from unnest(string_to_array(
                                 security.intake_page_wording_v1(p_course, p_evidence, (select e.source_url from pipeline.evidence_artifacts e where e.id = p_evidence)), ' | ')) s) z), ''))
$function$;
comment on function security.intake_wording_fp_v1(uuid, uuid) is 'CF-247 F-INT (9 Nov 2026): md5 of the stored intake wording of a course page (security.intake_page_wording_v1, the same text the plan reads), order-insensitive. Part of the intake inputs fingerprint, so a page read again with new intake wording is looked at again and an unchanged page is not.';
revoke all on function security.intake_wording_fp_v1(uuid, uuid) from public, anon, authenticated;

select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)', '27f5b2a6573aca6c508cd75ab4b3f151', 'intake_wording_fp_v1',
  array[$o$calendar_set := r.cal_set; inputs_fp := r.fp;$o$,
        $o$and d.inputs_fp is not distinct from security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings)$o$],
  array[$n$calendar_set := r.cal_set; inputs_fp := security.intake_inputs_fp_v1(r.cal_set, r.evidence_id, r.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(r.course_id, r.evidence_id));$n$,
        $n$and d.inputs_fp is not distinct from security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(i.course_id, i.evidence_id))$n$],
  array[1, 1]);

-- 6 rows already waiting (D3): a spread revisit time, so the 14-day cycle starts without a storm ------------------------------------------------
do $$
declare n int;
begin
  update pipeline.course_intake_dates d
     set next_revisit_at = now() + make_interval(secs => security.pipeline_num_v1('intake_dates.revisit_days', 14)::float8 * 86400  -- fixed: seconds in a day
                                                          * ((abs(hashtextextended(d.intake_id::text, 0)) % 10000) / 10000.0))
    from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id
   where i.id = d.intake_id and i.status = 'active' and c.lifecycle_status = 'active'
     and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and d.next_revisit_at is null and security.intake_revisit_stored_inputs_v1(d.next_action);
  get diagnostics n = row_count;
  raise notice 'F-INT: % waiting rows given a spread revisit time', n;
end $$;

-- 7 rows already settled (D2): the stored fingerprint takes the new form, except where the page was read after the decision ----------------------------
do $$
declare v_settings text := 'lists=' || (security.pipeline_num_v1('intake_dates.name_period_lists', 0) = 1)::text || ';unique=' || (security.pipeline_num_v1('intake_dates.month_unique_match', 0) = 1)::text || ';rules=fair-evidence-1';
        n int;
begin
  with sets as materialized (select p.provider_id, security.calendar_set_v1(p.provider_id) s from (select distinct x.provider_id from pipeline.course_intake_dates x) p),
  cur as (
    select d.intake_id, security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(c.id, i.evidence_id)) new_fp
      from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = d.provider_id
     where d.inputs_fp = security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings)
       -- a page read after the decision may hold new wording: that row keeps its old fingerprint and is looked at again once
       and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = d.course_id and g.read_at > d.applied_at)
       and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = d.course_id and f.field = 'intakes' and f.state = 'filled' and f.updated_at > d.applied_at))
  update pipeline.course_intake_dates d set inputs_fp = cur.new_fp from cur where cur.intake_id = d.intake_id;
  get diagnostics n = row_count;
  raise notice 'F-INT: % settled rows given the fingerprint form that holds the page wording', n;
end $$;
