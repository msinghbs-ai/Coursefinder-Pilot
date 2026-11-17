-- CF-247 AER technical holds, part 2: a read cut at the row limit is eligible again only when the university's row limit now fits it
-- (Platform Admin mandate 7 Nov 2026 21:57; branch cf247-aer-technical-holds). Edits one live function (md5-guarded). Reads and spends nothing.
-- Live evidence (7 Nov 2026 about 22:00 AEDT): 162 waiting reads are cut at the row limit; security.aer_recovery_rule_v1 (md5 b194475a46186bc674a3364816a8b06b)
-- classes 115 of them changed_conditions, "eligible for a corrected read", because it compares the newest entry.% setting time (all touched 3 Nov 20:07 or
-- later, values unchanged) with the item's creation. RMIT (limit 6, reads of 7 to 19 requirements) is 93 of the 115. None can be read again usefully
-- while the limit is unchanged: a corrected read is cut at the same limit and refused (27 such refusals; Diploma of Commerce twice). The authority line
-- also did not say how many rows the read needs.
-- What: the rule treats a row-limit cut as changed_conditions only when the university's row limit (security.course_entry_max_rows_v1: its own entry in
-- entry.max_rows_by_provider, else entry.max_rows_per_course) is now at least the number of requirements the read saw (rows kept + rows cut, or the
-- rows a stored read kept, whichever is more) and above the limit the read was cut under (the limit recorded on the read; a cut read keeps exactly that many rows). The authority line names that number. The result carries
-- rows_needed and row_limit_read_under.
-- Overlap with PR #875 (open, not merged, not depended on): #875 edits the same clause (its test: a university limit set after the last read). That is
-- not enough: a limit raised from 6 to 7 satisfies it for a 12-row read. Both edit md5 b194475a and cannot both be applied; choose one. This file does
-- not touch security.aer_schedule_held_v1 (#875's held-step order) or security.progress_measure_v1 (#875's measure).
-- Before -> after (live, 7 Nov 2026 22:10 AEDT):
--   security.aer_recovery_rule_v1(uuid) b194475a46186bc674a3364816a8b06b -> 35281a190b1465699ef3cc7eccaf6d41
-- Replaces: security.aer_recovery_rule_v1 (same name; md5-guarded edit)
-- Retires: nothing

do $g$
begin
  if to_regprocedure('security.course_entry_max_rows_v1(uuid)') is null or to_regprocedure('security.aer_recovery_rule_v1(uuid)') is null then
    raise exception 'needs E13 (security.course_entry_max_rows_v1) and the AER recovery rule (20261104580000)'; end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
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

select pg_temp.edit_once('security.aer_recovery_rule_v1(uuid)', 'b194475a46186bc674a3364816a8b06b', '35281a190b1465699ef3cc7eccaf6d41', array[
  [$e$        v_auth text; v_why text; v_last record; v_moved boolean := false; v_active boolean := true; v_tick timestamptz;$e$,
   $e$        v_auth text; v_why text; v_last record; v_moved boolean := false; v_active boolean := true; v_tick timestamptz; v_need int := 0; v_rlim int; v_now int;$e$],
  [$e$    v_rep := security.layer4_reread_repeat_v1(p_item);$e$,
   $e$    v_rep := security.layer4_reread_repeat_v1(p_item);
    -- 7 Nov 2026 (AER technical holds): what a row-limit cut needs to be read whole, and the limit it was cut under
    v_need := greatest(coalesce((r.proposed_value->>'rows')::int, 0) + coalesce((x.gate->>'rows_cut')::int, 0),
                       coalesce((select max(jsonb_array_length(e.value->'rows_read')) from pipeline.field_enrich_items e
                                  where e.course_id = r.entity_id and e.field = 'entry_requirements' and e.value ? 'rows_read'), 0));
    v_rlim := greatest(coalesce((r.proposed_value->>'limit')::int, 0),
                       coalesce((select max((e.value->>'limit')::int) from pipeline.field_enrich_items e
                                  where e.course_id = r.entity_id and e.field = 'entry_requirements' and e.value ? 'limit'), 0));
    v_now := security.course_entry_max_rows_v1(v_pid);$e$],
  [$e$    when v_cls = 'row_limit' and v_set_at > r.created_at then 'changed_conditions'$e$,
   $e$    -- 7 Nov 2026 (AER technical holds): only a row limit that now fits the read, above the limit it was cut under, makes a cut read eligible
    when v_cls = 'row_limit' and v_now >= v_need and v_now > coalesce(nullif(v_rlim, 0), (r.proposed_value->>'rows')::int, 0) then 'changed_conditions'$e$],
  [$e$  v_auth := case when v_class = 'row_limit' then 'a row limit for this university (entry.max_rows_by_provider, Platform Admin)' end;$e$,
   $e$  v_auth := case when v_class = 'row_limit' then 'a row limit of at least ' || greatest(v_need, 1) || ' for this university (entry.max_rows_by_provider, Platform Admin)' end;$e$],
  [$e$    'intervention', v_iv.id,$e$,
   $e$    'intervention', v_iv.id, 'rows_needed', case when v_need > 0 then v_need end, 'row_limit_read_under', nullif(v_rlim, 0), 'row_limit_now', v_now,$e$]],
  array[1, 1, 1, 1, 1]);
