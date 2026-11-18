CREATE OR REPLACE FUNCTION security.aer_matrix_machine_validate_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_min int := security.pipeline_num_v1('aer.matrix_machine_min_shadow', 20)::int; v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9);
        v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int; v_n int; v_would int; v_regress int := 0; r record; v_c jsonb; v_hist jsonb; v_pass boolean; v_detail jsonb;
begin
  select count(*), count(*) filter (where outcome = 'would_admit') into v_n, v_would from pipeline.aer_matrix_machine_admissions where mode = 'shadow';
  -- independent re-check of every current would-admit item
  for r in select m.review_item_id from pipeline.aer_matrix_machine_admissions m join pipeline.layer4_review_items i on i.id = m.review_item_id and i.status = 'pending'
            where m.mode = 'shadow' and m.outcome = 'would_admit' loop
    v_c := security.aer_matrix_machine_check_v1(r.review_item_id);
    if not coalesce((v_c->>'ok')::boolean, false) and coalesce(v_c->>'rule', '') not in ('audit_sample', 'claimed_by_person', 'item_not_pending') then v_regress := v_regress + 1; end if;
  end loop;
  -- agreement with past human matrix decisions: would the row rules have admitted the read a person decided, and did the person approve it unchanged?
  with h as (select i.id, d.action, emr.id run_id from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
              join pipeline.entry_matrix_runs emr on emr.review_item_id = i.id
             where i.field_code = 'entry_matrix_first_run' and d.actor_id is distinct from security.system_actor_id()),
  x as (select h.id, h.action,
               not exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = h.run_id
                             and (coalesce(m.confidence, 0) < v_conf or length(btrim(coalesce(m.quote, ''))) < v_qmin or m.study_level_id is null
                                  or not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null)
                                  or not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value)))
               and exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = h.run_id) would
          from h)
  select jsonb_build_object('human_decisions', count(*), 'rule_would_admit', count(*) filter (where would),
           'rule_would_admit_and_human_approved', count(*) filter (where would and action = 'approve'),
           'rule_would_admit_but_human_edited_or_refused', count(*) filter (where would and action <> 'approve'),
           'disagreements', coalesce(jsonb_agg(jsonb_build_object('item', id, 'action', action)) filter (where would and action <> 'approve'), '[]'::jsonb)) into v_hist from x;
  v_pass := v_n >= v_min and v_regress = 0
            and coalesce((v_hist->>'rule_would_admit_but_human_edited_or_refused')::int, 1) <= greatest(0, ((v_hist->>'rule_would_admit')::int) / 50);  -- fixed: at most 2% disagreement, none on a small history
  v_detail := jsonb_build_object('shadow_results', v_n, 'shadow_would_admit', v_would, 'shadow_min', v_min, 'regressions_on_recheck', v_regress, 'history', v_hist);
  insert into pipeline.aer_matrix_machine_validations(passed, detail, validated_by) values (v_pass, v_detail, auth.uid());
  return v_detail || jsonb_build_object('passed', v_pass, 'note', 'A pass does not switch admission on. A person (or the Integration Controller under the Platform Admin decision) sets aer.matrix_machine_mode to 2 with a reason.');
end $function$
