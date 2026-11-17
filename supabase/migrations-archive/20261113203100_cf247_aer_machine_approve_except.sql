-- CF-247 AER: machine Approve except (Platform Admin 12 Nov 2026 22:25: "Procced with automatic approve", answering the 22:20 offer: "build automatic
-- 'approve except' for these items: it would admit the rows that pass and hold back only the unresolved ones"; with 22:05 "dont limit on data admittance
-- make exceptions for it").
-- Guards: Layer 4 authority and every row rule unchanged (each held-back row fails the same rule that held the whole item before: confidence, quote, level,
--   published minimum, minimum in the quote, applicability never inferred (D1), course not linked, duplicate identity, conflicting active row); the item
--   rules still hold the whole item (lock, earlier rejection, evidence, uploaded copy, stale copy, official host, shared host, D-R3 gate on what is admitted,
--   completeness guard, the 5% audit sample). G2 (switch and cap are settings), G3 (no consumer API object), Decision 260.
-- What:
--   1. security.aer_matrix_machine_exclusions_v1(run): the proposed rows of a read that fail a row rule, by rule.
--   2. security.aer_matrix_machine_check_v1 (md5-guarded): with aer.matrix_machine_except_on, failing rows are held back instead of holding the item; the
--      D-R3 gate is evaluated on the rows admitted; an item whose every row fails stays with a person ('all_rows_held').
--   3. security.aer_matrix_machine_admit_v1 (md5-guarded): applies the same Approve except a person uses (entry_matrix_review_apply_v1 with exclude_row_ids);
--      held-back rows become inactive with the reason "excluded by approve except", as under a person's Approve except, and the decision reason lists them.
--   4. security.entry_matrix_gate_v1 (md5-guarded): an excluded per-course qualification row no longer counts as waiting for a course link (it is not
--      admitted), for a person's Approve except too.
--   5. Settings: aer.matrix_machine_except_on 1; aer.matrix_machine_daily_max 40 -> 1000 (22:05: do not limit admission).
-- Live definitions this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 22:30 AEDT): security.aer_matrix_machine_check_v1 0eadc57e9c42926b545c076d5236b502;
--   security.aer_matrix_machine_admit_v1 004dc22b5bbc7d7da633792ace98be20; security.entry_matrix_gate_v1 39f99e0bb589daea7f57afbc1fe3a41d.
-- Reversal without code: aer.matrix_machine_except_on 0 (an item with a failing row waits for a person again).
-- Replaces: the whole-item hold on a failing row in security.aer_matrix_machine_check_v1 (same function; md5-guarded edit). Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.matrix_machine_except_on', 'Entry tables: machine Approve except',
  '1: a country-table read whose item rules pass is admitted automatically with the rows that fail a row rule held back (Approve except, as a person does); the held-back rows are named in the decision. 0: any failing row holds the whole read for a person.',
  'number', to_jsonb(1), 0, 1, 'switch', 1146, 'Entry requirements', 'security.aer_matrix_machine_check_v1, security.aer_matrix_machine_admit_v1',
  'Platform Admin 12 Nov 2026 22:25: "Procced with automatic approve" (machine Approve except)')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings set value = to_jsonb(1000), updated_at = now(),
       reason = 'Platform Admin 12 Nov 2026 22:05: "dont limit on data admittance make exceptions for it"'
 where toolset_key = 'pipeline' and key = 'aer.matrix_machine_daily_max' and (value #>> '{}')::numeric = 40;

create or replace function security.aer_matrix_machine_exclusions_v1(p_run uuid) returns jsonb
language sql stable security definer set search_path to '' as $f$
  -- the proposed rows of one read that fail a row rule of the machine check, each with its rule (the same rules, in the same order)
  with cfg as materialized (select security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9) conf, security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int qmin,
                                   security.pipeline_num_v1('aer.course_link_on', 1) >= 1 link_on),
  run as materialized (select r.id, r.source_id from pipeline.entry_matrix_runs r where r.id = p_run),
  m as materialized (select m.* from catalogue.provider_entry_matrix m join run on m.run_id = run.id where m.status = 'proposed'),
  q as materialized (select q.* from catalogue.provider_qualification_requirements q join run on q.run_id = run.id where q.status = 'proposed'),
  why as (
    select m.id, case when coalesce(m.confidence, 0) < cfg.conf then 'low_confidence' when length(btrim(coalesce(m.quote, ''))) < cfg.qmin then 'short_quote'
                      when m.study_level_id is null then 'level_unmapped'
                      when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                      when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote'
                      when cfg.link_on and m.course_label is not null and m.course_id is null then 'course_unlinked'
                      when exists (select 1 from m m2 where m2.row_hash = m.row_hash and m2.id <> m.id) then 'duplicate_identity'
                      when exists (select 1 from catalogue.provider_entry_matrix a, run where a.row_hash = m.row_hash and a.status = 'active' and a.id <> m.id
                                      and a.source_id is distinct from run.source_id) then 'conflicting_active' end w
      from m, cfg
    union all
    select q.id, case when q.applicability = 'unresolved' then 'applicability_unresolved' when coalesce(q.confidence, 0) < cfg.conf then 'low_confidence'
                      when length(btrim(coalesce(q.quote, ''))) < cfg.qmin then 'short_quote' when q.study_level_id is null then 'level_unmapped'
                      when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                      when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote'
                      when cfg.link_on and q.course_label is not null and q.course_id is null then 'course_unlinked'
                      when exists (select 1 from q q2 where q2.qualification_code = q.qualification_code and q2.level_label is not distinct from q.level_label
                                      and q2.course_label is not distinct from q.course_label and q2.id <> q.id) then 'duplicate_identity'
                      when exists (select 1 from catalogue.provider_qualification_requirements a, run where a.provider_id = q.provider_id and a.qualification_code = q.qualification_code
                                      and a.level_label is not distinct from q.level_label and a.course_label is not distinct from q.course_label and a.status = 'active'
                                      and a.source_id is distinct from run.source_id) then 'conflicting_active' end
      from q, cfg)
  select jsonb_build_object('ids', coalesce(jsonb_agg(why.id order by why.id) filter (where why.w is not null), '[]'::jsonb),
                            'by_rule', coalesce((select jsonb_object_agg(z.w, z.n) from (select w, count(*) n from why where w is not null group by w) z), '{}'::jsonb))
    from why
$f$;
comment on function security.aer_matrix_machine_exclusions_v1(uuid) is 'CF-247 machine Approve except (Platform Admin 12 Nov 2026 22:25): the proposed rows of a read that fail a row rule, held back while the rest are admitted.';

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

select pg_temp.edit_n('security.aer_matrix_machine_check_v1(uuid)', '0eadc57e9c42926b545c076d5236b502', array[
  array[$o$v_nm int; v_nq int; v_bad text; v_checks jsonb;$o$, $n$v_nm int; v_nq int; v_bad text; v_checks jsonb; v_ex jsonb; v_exids uuid[] := '{}'::uuid[];$n$],
  array[$o$  g := security.entry_matrix_gate_v1(r.id, '{}'::uuid[]);$o$,
        $n$  -- 12 Nov 2026 (Platform Admin 22:25, machine Approve except): rows that fail a row rule are held back; the gate is judged on the rows admitted
  if security.pipeline_num_v1('aer.matrix_machine_except_on', 0) >= 1 then
    v_ex := security.aer_matrix_machine_exclusions_v1(r.id);
    v_exids := coalesce(array(select jsonb_array_elements_text(v_ex->'ids')::uuid), '{}'::uuid[]);
  end if;
  g := security.entry_matrix_gate_v1(r.id, v_exids);$n$],
  array[$o$  if v_nm + v_nq = 0 then return jsonb_build_object('ok', false, 'rule', 'no_rows',$o$,
        $n$  if v_ex is not null and v_nm + v_nq > 0 and v_nm + v_nq - cardinality(v_exids) <= 0 then
    return jsonb_build_object('ok', false, 'rule', 'all_rows_held', 'reason', 'Every proposed row fails a row rule, so nothing can be admitted automatically.', 'next_action', decline,
                              'checks', v_checks || jsonb_build_object('held_back_by_rule', v_ex->'by_rule')); end if;
  if v_nm + v_nq = 0 then return jsonb_build_object('ok', false, 'rule', 'no_rows',$n$],
  array[$o$  if v_bad is not null then return$o$, $n$  if v_bad is not null and v_ex is null then return$n$],
  array[$o$  if exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' group by m.row_hash having count(*) > 1)$o$,
        $n$  if v_ex is null and (exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' group by m.row_hash having count(*) > 1)$n$],
  array[$o$group by q.qualification_code, q.level_label having count(*) > 1) then$o$, $n$group by q.qualification_code, q.level_label having count(*) > 1)) then$n$],
  array[$o$  if exists (select 1 from catalogue.provider_entry_matrix p join catalogue.provider_entry_matrix a on a.row_hash = p.row_hash$o$,
        $n$  if v_ex is null and (exists (select 1 from catalogue.provider_entry_matrix p join catalogue.provider_entry_matrix a on a.row_hash = p.row_hash$n$],
  array[$o$a.source_id is distinct from r.source_id) then$o$, $n$a.source_id is distinct from r.source_id)) then$n$],
  array[$o$'host', v_sh, 'min_confidence', v_conf);$o$,
        $n$'host', v_sh, 'min_confidence', v_conf)
              || case when v_ex is not null then jsonb_build_object('exclude_row_ids', coalesce(v_ex->'ids', '[]'::jsonb), 'held_back', cardinality(v_exids),
                                                                    'held_back_by_rule', coalesce(v_ex->'by_rule', '{}'::jsonb)) else '{}'::jsonb end;$n$],
  array[$o$  return jsonb_build_object('ok', true, 'rule', 'aer-matrix-machine-v1', 'checks', v_checks);$o$,
        $n$  return jsonb_build_object('ok', true, 'rule', case when cardinality(v_exids) > 0 then 'aer-matrix-machine-v1-except' else 'aer-matrix-machine-v1' end, 'checks', v_checks);$n$]
], array[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);

select pg_temp.edit_n('security.aer_matrix_machine_admit_v1(uuid,text)', '004dc22b5bbc7d7da633792ace98be20', array[
  array[$o$  v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1'), v_reason);$o$,
        $n$  -- 12 Nov 2026 (Platform Admin 22:25): machine Approve except, the same apply a person's Approve except uses
  if coalesce((v->'checks'->>'held_back')::int, 0) > 0 then
    v_reason := v_reason || format(' Approve except (Platform Admin 12 Nov 2026 22:25): %s row(s) held back, each failing a row rule (%s); they are not admitted.',
                                   v->'checks'->>'held_back', v->'checks'->'held_back_by_rule');
  end if;
  v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1',
             'exclude_row_ids', coalesce(v->'checks'->'exclude_row_ids', '[]'::jsonb)), v_reason);$n$]
], array[1]);

select pg_temp.edit_n('security.entry_matrix_gate_v1(uuid,uuid[])', '39f99e0bb589daea7f57afbc1fe3a41d', array[
  array[$o$where q.run_id = r.id and q.status = 'proposed' and q.course_label is not null and q.course_id is null;$o$,
        $n$where q.run_id = r.id and q.status = 'proposed' and q.course_label is not null and q.course_id is null and not (q.id = any (v_ex));$n$]
], array[1]);
