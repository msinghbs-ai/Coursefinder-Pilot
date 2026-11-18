CREATE OR REPLACE FUNCTION security.aer_matrix_machine_admit_v1(p_item uuid, p_via text DEFAULT 'run'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; v jsonb; v_mode int := security.aer_matrix_machine_effective_v1(); v_res jsonb; v_dec uuid; v_reason text; v_out text;
        v_sys uuid := security.system_actor_id(); v_run uuid; v_after int;
        v_ref constant text := 'CF-247 F-AER.04; Platform Admin decision D1 11 Nov 2026 (machine admission of source-verified country tables and qualification rows)';
begin
  if v_mode < 1 then return jsonb_build_object('ok', false, 'rule', 'matrix_machine_off'); end if;
  if v_mode >= 2 then
    select * into i from pipeline.layer4_review_items where id = p_item for update skip locked;
    if i.id is null then return jsonb_build_object('ok', false, 'rule', 'item_locked'); end if;
  else
    select * into i from pipeline.layer4_review_items where id = p_item;
  end if;
  v := security.aer_matrix_machine_check_v1(p_item);
  v_run := nullif(v->'checks'->>'run_id', '')::uuid;
  v_out := case when coalesce((v->>'ok')::boolean, false) then (case when v_mode >= 2 then 'admitted' else 'would_admit' end)
                when coalesce((v->>'audit')::boolean, false) then 'audit_sample' else 'declined' end;
  if v_mode < 2 then
    insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, reason_code, reason, checks, actor)
    values (p_item, i.entity_id, v_run, 'shadow', v_out, v->>'rule', v->>'reason', coalesce(v->'checks', '{}'::jsonb), v_sys)
    on conflict (review_item_id) where mode = 'shadow' do update set outcome = excluded.outcome, reason_code = excluded.reason_code, reason = excluded.reason,
           checks = excluded.checks, run_id = excluded.run_id, updated_at = now();
    return jsonb_build_object('ok', true, 'mode', 'shadow', 'outcome', v_out, 'rule', v->>'rule');
  end if;
  if v_out <> 'admitted' then
    if v->>'rule' not in ('item_not_pending', 'not_this_class', 'claimed_by_person', 'decided') then
      update pipeline.layer4_review_items set escalation_reason = left('Machine rule aer-matrix-machine-v1 did not admit this: ' || (v->>'rule') || '. '
               || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule aer-matrix-machine-v1[^:]*: [a-z0-9_]+\. ', ''), 1000)  -- fixed: the column shows 1000 characters
       where id = p_item and status = 'pending' and coalesce(escalation_reason, '') not like 'Machine rule aer-matrix-machine-v1 did not admit this: ' || (v->>'rule') || '.%';
    end if;
    if not exists (select 1 from pipeline.aer_matrix_machine_admissions m where m.review_item_id = p_item and m.mode = 'admit' and m.outcome = v_out and m.reason_code is not distinct from v->>'rule') then
      insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, reason_code, reason, checks, actor)
      values (p_item, i.entity_id, v_run, 'admit', v_out, v->>'rule', v->>'reason', coalesce(v->'checks', '{}'::jsonb), v_sys);
    end if;
    return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule');
  end if;
  -- admit: the same apply a person's approval uses (D-R3, D4 and the completeness guard run again inside it), then the same records
  v_reason := format('Auto (aer-matrix-machine-v1, %s): first read of the provider''s own source %s (host %s, content hash %s), %s country rows and %s qualification rows, each with an exact quote, a published minimum, a mapped level and confidence at least %s; qualification applicability explicit. Not a person''s decision.',
                     coalesce(p_via, 'run'), coalesce(v->'checks'->>'source_url', ''), v->'checks'->>'host', left(coalesce(v->'checks'->>'content_hash', ''), 12),
                     v->'checks'->>'rows', v->'checks'->>'qualification_rows', v->'checks'->>'min_confidence');  -- fixed: a short hash prefix for reading; the full hash is in the ledger
  -- 12 Nov 2026 (Platform Admin 22:25): machine Approve except, the same apply a person's Approve except uses
  if coalesce((v->'checks'->>'held_back')::int, 0) > 0 then
    v_reason := v_reason || format(' Approve except (Platform Admin 12 Nov 2026 22:25): %s row(s) held back, each failing a row rule (%s); they are not admitted.',
                                   v->'checks'->>'held_back', v->'checks'->'held_back_by_rule');
  end if;
  v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1',
             'exclude_row_ids', coalesce(v->'checks'->'exclude_row_ids', '[]'::jsonb)), v_reason);
  select (select count(*) from catalogue.provider_entry_matrix m where m.run_id = v_run and m.status = 'active')
       + (select count(*) from catalogue.provider_qualification_requirements q where q.run_id = v_run and q.status = 'active') into v_after;
  if v_after = 0 or v_after <> coalesce((v_res->>'admitted')::int, 0) + coalesce((v_res->>'qualification_admitted')::int, 0) then
    raise exception 'aer-matrix-machine: read-back found % active rows, apply reported %', v_after, v_res; end if;
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = p_item and status = 'pending';
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', 'aer-matrix-machine-v1', 'actor_kind', 'machine', 'via', coalesce(p_via, 'run')), coalesce(i.layer3_state, '{}'::jsonb), v_ref)
  returning id into v_dec;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'aer_approve', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', i.id, 'decision_id', v_dec, 'kind', i.field_code, 'reason', v_reason,
          'result', v_res, 'auto', true, 'machine_rule', 'aer-matrix-machine-v1', 'actor_kind', 'machine'), v_sys);
  insert into pipeline.search_refresh_signals(entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, reason_code, reason, checks, rows_admitted, decision_id, actor)
  values (i.id, i.entity_id, v_run, 'admit', 'admitted', 'aer-matrix-machine-v1', v_reason, coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('apply', v_res, 'via', coalesce(p_via, 'run')),
          v_after, v_dec, v_sys);
  return jsonb_build_object('ok', true, 'mode', 'admit', 'outcome', 'admitted', 'decision_id', v_dec, 'rows', v_after);
end $function$
