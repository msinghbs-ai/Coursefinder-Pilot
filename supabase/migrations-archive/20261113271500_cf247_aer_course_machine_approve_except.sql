-- CF-247 AER: machine Approve except for course entry reads, the same rule country tables have since 20261113203100 (Platform Admin 12 Nov 2026 22:25
-- "Procced with automatic approve"; 13 Nov 2026 09:30 "If an actual technical bottleneck prevents higher throughput, fix the shared cause through the normal
-- engineering release process").
-- Evidence (13 Nov 2026 10:00 AEDT): of the waiting course reads the completeness gate holds, 68 are held at row level only (rows that name a domestic route but
--   are stored for all, rows that are not a requirement, rows of another programme: "leave them out with Approve except") and 25 have rows without an exact
--   quote, enough confidence or this read's evidence. Each waits for a person although its other rows pass.
-- Guards: every row rule and every item rule unchanged (lock, earlier rejection, duplicate waiting read, active rows, withdrawn admission, bound page, identity
--   proof, evidence, page changed or stale, E13/D-R3 gate on the admitted rows, the 5% audit sample); a gate class other than row level (dropped printed
--   requirement, rows cut at the limit, shared page) still holds the whole read. G2 (switch is a setting), G3 (no consumer API object), Decision 260.
-- What: security.aer_machine_check_v1 (md5-guarded): with aer.machine_except_on, unsupported rows and the rows the gate names at row level are held back and
--   the gate is run again on the rest; security.aer_machine_admit_v1 (md5-guarded): applies the same Approve except a person uses
--   (course_entry_review_apply_v1 with exclude_row_ids) and names the held-back rows in the decision reason.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 13 Nov 2026 10:05 AEDT): security.aer_machine_check_v1 1eb645492dd067e699decef07da6402f;
--   security.aer_machine_admit_v1 3a5de30e542b3fdff123bbe90bda7dda.
-- Reversal without code: aer.machine_except_on 0.
-- Replaces: the whole-read hold on a row-level failure in security.aer_machine_check_v1 (same function; md5-guarded edit). Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.machine_except_on', 'Course entry reads: machine Approve except',
  '1: a course entry read whose item rules pass is admitted automatically with the rows that fail a row rule held back (Approve except, as a person does). 0: any failing row holds the whole read for a person.',
  'number', to_jsonb(1), 0, 1, 'switch', 1148, 'Entry requirements', 'security.aer_machine_check_v1, security.aer_machine_admit_v1',
  'Platform Admin 12 Nov 2026 22:25 ("Procced with automatic approve") and 13 Nov 2026 09:30 (fix the shared cause)')
on conflict (toolset_key, key) do nothing;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.aer_machine_check_v1(uuid)', '1eb645492dd067e699decef07da6402f', array[
  array[$o$v_n int; v_bad int; v_bucket int; v_checks jsonb := '{}'::jsonb;$o$,
        $n$v_n int; v_bad int; v_bucket int; v_checks jsonb := '{}'::jsonb;
        v_ex uuid[] := '{}'::uuid[]; v_exon boolean := security.pipeline_num_v1('aer.machine_except_on', 0) >= 1;$n$],
  array[$o$  if v_bad > 0 then
    return jsonb_build_object('ok', false, 'rule', 'row_unsupported',$o$,
        $n$  if v_bad > 0 and v_exon then
    -- 13 Nov 2026 (machine Approve except): rows without an exact quote, enough confidence or this read's evidence are held back
    select coalesce(array_agg(x.id), '{}'::uuid[]) into v_ex from catalogue.course_entry_requirements x
     where x.provenance->>'review_item_id' = i.id::text and x.status = 'proposed'
       and (coalesce(length(btrim(x.quote)), 0) < v_qmin or coalesce(x.confidence, 0) < v_conf or x.evidence_id is distinct from i.evidence_id);
  elsif v_bad > 0 then
    return jsonb_build_object('ok', false, 'rule', 'row_unsupported',$n$],
  array[$o$  v_gate := security.course_entry_gate_v1(i.id, '{}'::uuid[]);$o$,
        $n$  v_gate := security.course_entry_gate_v1(i.id, v_ex);
  -- 13 Nov 2026 (machine Approve except): rows the gate names at row level (domestic route stored for all, not a requirement, another programme) are held back
  -- and the gate is run again on the rest; any other gate class (dropped printed requirement, rows cut, shared page) still holds the whole read
  if v_exon and v_gate is not null and not coalesce((v_gate->>'complete')::boolean, false) and security.aer_e13_class_v1(v_gate) = 'row_level' then
    v_ex := v_ex || coalesce(array(select (e->>'id')::uuid
                                     from jsonb_array_elements(coalesce(v_gate->'audience', '[]'::jsonb) || coalesce(v_gate->'not_requirement', '[]'::jsonb) || coalesce(v_gate->'other_programme', '[]'::jsonb)) e
                                    where jsonb_typeof(e) = 'object' and e ? 'id'), '{}'::uuid[]);
    v_gate := security.course_entry_gate_v1(i.id, v_ex);
  end if;
  if cardinality(v_ex) > 0 and v_n - cardinality(v_ex) <= 0 then
    return jsonb_build_object('ok', false, 'rule', 'all_rows_held', 'reason', 'Every waiting row fails a row rule, so nothing can be admitted automatically.', 'next_action', function_fail, 'checks', v_checks);
  end if;$n$],
  array[$o$'min_confidence', v_conf, 'min_quote_chars', v_qmin);$o$,
        $n$'min_confidence', v_conf, 'min_quote_chars', v_qmin)
              || case when cardinality(v_ex) > 0 then jsonb_build_object('exclude_row_ids', to_jsonb(v_ex), 'held_back', cardinality(v_ex)) else '{}'::jsonb end;$n$],
  array[$o$  return jsonb_build_object('ok', true, 'rule', 'aer-machine-v1', 'course_id'$o$,
        $n$  return jsonb_build_object('ok', true, 'rule', case when cardinality(v_ex) > 0 then 'aer-machine-v1-except' else 'aer-machine-v1' end, 'course_id'$n$]
], array[1, 1, 1, 1, 1]);

select pg_temp.edit_n('security.aer_machine_admit_v1(uuid,text)', '3a5de30e542b3fdff123bbe90bda7dda', array[
  array[$o$  v_res := security.course_entry_review_apply_v1(p_item, 'approve', i.proposed_value - 'exclude_row_ids', v_reason);$o$,
        $n$  -- 13 Nov 2026: machine Approve except, the same apply a person's Approve except uses
  if coalesce((v->'checks'->>'held_back')::int, 0) > 0 then
    v_reason := v_reason || format(' Approve except (Platform Admin 12 Nov 2026 22:25): %s row(s) held back, each failing a row rule; they are not admitted.', v->'checks'->>'held_back');
  end if;
  v_res := security.course_entry_review_apply_v1(p_item, 'approve', (i.proposed_value - 'exclude_row_ids')
             || case when coalesce((v->'checks'->>'held_back')::int, 0) > 0 then jsonb_build_object('exclude_row_ids', v->'checks'->'exclude_row_ids') else '{}'::jsonb end, v_reason);$n$]
], array[1]);
