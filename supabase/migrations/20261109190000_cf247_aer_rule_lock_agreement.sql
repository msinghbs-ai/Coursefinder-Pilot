-- CF-247 AER rule and D-R2 agree on what a lock blocks (Platform Admin 9 Nov 2026: "Continue fixing ... the AER lock mismatch autonomously."; QA of PR #944 / migration 20261109150000).
--
-- Why (live, read only, 9 Nov 2026, project fxcwkweaxjtknorudmwp):
--   * The held step still asks 0 corrected reads. 98 items are inside the 14-day retry period after a refusal (working as designed; the period is not changed here).
--     The other 9 items the shared rule (security.aer_recovery_rule_v1) classes reread_eligible are all refused by D-R2 (security.course_entry_correction_check_v1) with
--     "the course has a manual lock".
--   * The two functions read different locks. D-R2 refuses a corrected read for a lock on any field of the setting entry.supersede_lock_fields (live value
--     ["entry_requirements", "course_url", "official_url"], Platform Admin 2 Nov 2026 23:24, "locks protected"). The rule tested only a lock on entry_requirements.
--     All 9 items are courses whose official page a person set by hand on 5 Oct 2026 (manual_locks course_url and official_url, mode value, one setter, via the
--     admin function set_official_url; manual_edit_log reasons "Rebind ... on the Platform Admin instruction 5 Oct"). No course has a lock on entry_requirements.
--     So the rule called them eligible, the held step spent a place in its scan of 40 on each (they are scanned first by 20261109150000) and D-R2 refused each one,
--     and the measure counted them as eligible.
--   * The whole class (every waiting course entry read whose lock D-R2 refuses for): 97 items, all with exactly the course_url + official_url lock pair. By class:
--     9 reread_eligible (this change), 26 stale, 22 row_limit, 20 ready, 13 decision, 7 human_assisted. Only the 9 are selected for a corrected read.
--     Nothing else about eligibility disagrees: the other 98 eligible items (changed_conditions) pass every D-R2 check except the retry period.
-- What (one md5-guarded in-place edit of security.aer_recovery_rule_v1; no setting, number, job, table, cap or switch):
--   1 the rule reads the same setting as D-R2 (entry.supersede_lock_fields, through security.toolset_setting, the same expression) and, when a lock on one of those
--     fields exists on a course whose class would be reread_eligible or changed_conditions, the class is human_assisted: the lock is named in why and next_action, the
--     item is not eligible, the held step does not scan it and the measure does not count it. The entry_requirements test is unchanged (it stays a floor even if the
--     setting is edited), so the rule is never less strict than before; if the Platform Admin removes a field from the setting, the rule follows by itself.
--   2 only the two eligible classes are changed. Items in every other class (row_limit, stale, ready, decision, ...) keep their class, so no other count moves; a
--     row-limit item with such a lock becomes human_assisted when a raised row limit would otherwise have made it eligible.
--   3 condition_key gains the locked fields only when they changed the class (concat_ws skips null), so no other item's condition key changes and no other item is
--     reported again by security.aer_technical_recovery_v1.
-- Not changed: no lock is removed, bypassed or edited (a lock keeps protecting the person's value); D-R2 (security.course_entry_correction_check_v1), the held step, the
--   measure, the 14-day retry period (aer.schedule_held_retry_days), the tries, the scan size, entry.supersede_lock_fields and aer.schedule_lock_fields; no read, no
--   AI call, no Layer 4 decision. First reads still read a course with a page lock (aer.schedule_lock_fields is entry_requirements only). A passing test switches nothing on.
-- Effect once applied (rolled-back dry run on live): the 9 items become human_assisted with the lock named; eligible 107 -> 98 (all 98 are in the retry period).
--   The next hourly run of security.aer_technical_recovery_v1 (job layer4-readiness or work-continuity) records the change; the lane item moves from aer_reread_eligible to aer_human_input.
--
-- Live definition this change edits (pg_get_functiondef md5, read 9 Nov 2026; pg_proc.prosrc md5 02aef151414b1fa566efd7987b53a2aa before):
--   security.aer_recovery_rule_v1(uuid) 35281a190b1465699ef3cc7eccaf6d41 -> 25dcc4055de135901826ffcae344a96f
-- Replaces: the lock test of security.aer_recovery_rule_v1 (entry_requirements only) with the lock test of D-R2 (entry.supersede_lock_fields), edited in place
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object is touched (G3).

do $g$
begin
  if to_regprocedure('security.aer_recovery_rule_v1(uuid)') is null or to_regprocedure('security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)') is null then
    raise exception 'needs the AER recovery rule (20261104580000) and D-R2 (20261103070000)'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.supersede_lock_fields') then
    raise exception 'needs the setting entry.supersede_lock_fields (D-R2, 20261103070000)'; end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  -- fixed: the guard is the md5 of the whole definition; the final md5 is also the second-run check (a second run changes nothing)
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.aer_recovery_rule_v1(uuid)', '35281a190b1465699ef3cc7eccaf6d41', '25dcc4055de135901826ffcae344a96f', array[
  -- 1 a variable for the locked fields of the setting D-R2 uses
  [$e$v_iv record; v_lock boolean := false;$e$,
   $e$v_iv record; v_lock boolean := false; v_lockd text;$e$],
  -- 2 the locked fields, by the same test as D-R2 (security.course_entry_correction_check_v1): a lock on a field of entry.supersede_lock_fields
  [$e$and l.field = 'entry_requirements');$e$,
   $e$and l.field = 'entry_requirements');
    -- 9 Nov 2026 (AER lock agreement): the locks D-R2 refuses a corrected read for (setting entry.supersede_lock_fields, read the same way as in D-R2)
    v_lockd := (select string_agg(l.field, ', ' order by l.field) from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.entity_id
                   and l.field in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.supersede_lock_fields'), '[]'::jsonb))));$e$],
  -- 3 a read D-R2 would refuse for a lock is not eligible; every other class keeps its place
  [$e$  v_auth := case when v_class = 'row_limit' then$e$,
   $e$  -- 9 Nov 2026 (AER lock agreement): D-R2 refuses a corrected read while the course has a manual lock on a field of entry.supersede_lock_fields, so the rule does not
  -- make such a read eligible (the lock is not removed or bypassed). Only the two eligible classes change; v_lockd is kept only when it changed the class.
  if v_lockd is not null and v_class in ('reread_eligible', 'changed_conditions') then v_class := 'human_assisted'; else v_lockd := null; end if;
  v_auth := case when v_class = 'row_limit' then$e$],
  -- 4 why
  [$e$case when v_lock then 'the course''s entry requirements are locked by hand'$e$,
   $e$case when v_lock then 'the course''s entry requirements are locked by hand'
                                    when v_lockd is not null then 'a manual lock on the course''s ' || v_lockd || ' stops a corrected read (D-R2, entry.supersede_lock_fields)'$e$],
  -- 5 next action
  [$e$when 'human_assisted' then case when v_lock then 'a Platform Admin lifts the lock, or the read is left'$e$,
   $e$when 'human_assisted' then case when v_lock then 'a Platform Admin lifts the lock, or the read is left'
                                    when v_lockd is not null then 'a person rejects or decides the waiting read in Layer 4, or a Platform Admin lifts the lock (a lock is never bypassed)'$e$],
  -- 6 condition key: the locked fields, only when they changed the class (concat_ws skips null, so no other key changes)
  [$e$coalesce(v_busy, '-'))));$e$,
   $e$coalesce(v_busy, '-'), v_lockd)));$e$]
], array[1, 1, 1, 1, 1, 1]);

comment on function security.aer_recovery_rule_v1(uuid) is 'CF-247 AER recovery rule: the recovery class of one waiting AER item, from existing records. A course with a manual lock on a field of entry.supersede_lock_fields (the locks D-R2 refuses a corrected read for) is human_assisted, never eligible, so the held step does not scan it and the measure does not count it (9 Nov 2026).';
