CREATE OR REPLACE FUNCTION security.layer4_readiness_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 P0 Layer 4 readiness (job layer4-readiness). One run:
--   1 Classify waiting items (layer4.readiness_batch; never classified first, then the oldest): resolvable / technical_blocked / judgement_ready,
--     with blockers, route and the kind's measured reviewer minutes; entry-requirement gates for at most layer4.gate_batch items. Items no
--     longer waiting are closed.
--   2 Settle (supersede) what the platform can settle, only while layer4.reconcile_supersede_on is 1 (security.layer4_reconcile_v1).
--   3 Check approvals (layer4.verify_batch): new decisions first, then those not yet passed after layer4.verify_recheck_hours.
--   4 One integration issue per kind and reason of approvals that did not reach the catalogue or the projection (l4_not_admitted:<kind>:<reason>,
--     l4_not_published:<kind>:<reason>); an issue no longer seen is marked condition-cleared (the controller closes it after verification).
declare v_t0 timestamptz := clock_timestamp(); r record; v_res jsonb; v_blk jsonb; v_pace jsonb := security.layer4_pace_v1(); v_kinds text[] := security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb);
        v_gates int := security.pipeline_num_v1('layer4.gate_batch', 20)::int; v_g int := 0; v_cls int := 0; v_closed int := 0; v_chk int := 0; v_iss int := 0;
        v_rec jsonb; v_gate jsonb; v_gate_at timestamptz; v_ready text; v_reasons text[]; v_route text; v_seen text[] := '{}'; v_fp text; v_out jsonb; v_use_gate boolean;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:layer4-readiness')) then return jsonb_build_object('busy', true); end if;  -- fixed: one run at a time
  if security.pipeline_num_v1('layer4.readiness_on', 1) >= 1 then
    -- items that stopped waiting
    update pipeline.layer4_item_readiness x set readiness = 'closed', item_status = i.status, classified_at = now()
      from pipeline.layer4_review_items i where i.id = x.item_id and x.readiness <> 'closed' and i.status <> 'pending';
    get diagnostics v_closed = row_count;
    for r in select i.id, i.entity_type, i.entity_id, i.field_code, i.created_at, x.gate, x.gate_checked_at
               from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
              where i.status = 'pending'
                and (x.item_id is null or x.classified_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int))
              order by x.classified_at nulls first, i.created_at
              limit security.pipeline_num_v1('layer4.readiness_batch', 1000)::int loop
      v_res := security.layer4_resolution_v1(r.id);
      v_use_gate := r.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') and v_g < v_gates
                    and (r.gate_checked_at is null or r.gate_checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int));
      v_blk := security.layer4_blockers_v1(r.id, v_use_gate);
      if v_use_gate then v_g := v_g + 1; v_gate := v_blk->'gate'; v_gate_at := now();
      else
        v_gate := r.gate; v_gate_at := r.gate_checked_at;
        -- an earlier gate result that held the read still holds it until it is evaluated again
        if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
          v_blk := jsonb_set(v_blk, '{blockers}', (v_blk->'blockers') || jsonb_build_object('code', 'completeness_gate', 'why', coalesce(v_gate->'reasons'->>0, 'the completeness gate holds this read'),
                             'repair', 'the reader of this kind (D-R2 replacement read)', 'rule', v_gate->>'rule', 'as_at', r.gate_checked_at));
          v_blk := jsonb_set(v_blk, '{route}', to_jsonb('repair:' || (v_blk->'blockers'->0->>'code')));
        end if;
      end if;
      if v_res is not null and r.field_code = any (v_kinds) then
        v_ready := 'resolvable'; v_reasons := array[v_res->>'reason']; v_route := 'platform:' || (v_res->>'reason');
      elsif jsonb_array_length(v_blk->'blockers') > 0 then
        v_ready := 'technical_blocked'; v_reasons := (select array_agg(distinct b->>'code') from jsonb_array_elements(v_blk->'blockers') b); v_route := v_blk->>'route';
      else
        v_ready := 'judgement_ready'; v_reasons := '{}'; v_route := v_blk->>'route';
      end if;
      insert into pipeline.layer4_item_readiness as x(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, resolution, blockers,
                                                      est_minutes, gate, gate_checked_at, classified_at)
      values (r.id, r.entity_type, r.entity_id, r.field_code, r.created_at, 'pending', v_ready, v_reasons, v_route, v_res, v_blk->'blockers',
              coalesce((v_pace->r.field_code->>'minutes')::numeric, security.pipeline_num_v1('layer4.pace_default_minutes', 3)), v_gate, v_gate_at, now())
      on conflict (item_id) do update set item_status = 'pending', readiness = excluded.readiness, reasons = excluded.reasons, route = excluded.route,
         resolution = excluded.resolution, blockers = excluded.blockers, est_minutes = excluded.est_minutes, gate = excluded.gate, gate_checked_at = excluded.gate_checked_at,
         classified_at = now();
      v_cls := v_cls + 1;
    end loop;
  end if;
  v_rec := security.layer4_reconcile_v1(null, case when security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1
                                                   then security.pipeline_num_v1('layer4.reconcile_batch', 200)::int else 0 end);
  if security.pipeline_num_v1('layer4.verify_on', 1) >= 1 then
    for r in select x.id from pipeline.layer4_decisions x
               left join pipeline.layer4_admission_checks c on c.decision_id = x.id
              where x.action in ('approve', 'edit_and_approve')
                and x.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.verify_lookback_days', 30)::int)
                and (c.decision_id is null
                     or (c.result in ('not_admitted', 'admitted_not_published', 'waiting')
                         and c.checked_at < now() - make_interval(hours => security.pipeline_num_v1('layer4.verify_recheck_hours', 6)::int))
                     or (c.result = 'waiting' and c.checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.verify_wait_minutes', 90)::int)))
              order by (c.decision_id is null) desc, x.created_at desc
              limit security.pipeline_num_v1('layer4.verify_batch', 300)::int loop
      perform security.layer4_admission_record_v1(r.id);
      v_chk := v_chk + 1;
    end loop;
    -- one issue per kind and reason (the latest result of approvals in the window)
    for r in select c.field_code, c.result, coalesce(c.reason, 'unknown') reason, count(*) n, array_agg(c.entity_id order by c.decided_at desc) ents,
                    array_agg(c.decision_id order by c.decided_at desc) decs, min(c.decided_at) first_at, max(c.decided_at) last_at
               from pipeline.layer4_admission_checks c
              where c.result in ('not_admitted', 'admitted_not_published')
                and c.decided_at > now() - make_interval(days => security.pipeline_num_v1('layer4.verify_lookback_days', 30)::int)
              group by 1, 2, 3 loop
      v_fp := case when r.result = 'not_admitted' then 'l4_not_admitted:' else 'l4_not_published:' end || r.field_code || ':' || r.reason;
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
        'title', case when r.result = 'not_admitted' then 'Layer 4 approvals that did not reach the catalogue (' else 'Layer 4 approvals in the catalogue but not on the website projection (' end
                 || r.field_code || ', ' || r.reason || ')',
        'layer', 'Layer 4', 'subsystem', 'pipeline.layer4_admission_checks',
        'failure', r.n || ' approval(s) saved ' || to_char(r.first_at at time zone 'Australia/Melbourne', 'DD Mon') || ' to ' || to_char(r.last_at at time zone 'Australia/Melbourne', 'DD Mon')
                   || ' are ' || replace(r.result, '_', ' ') || ' (' || r.reason || ')',
        'expected', 'An approved value is in the catalogue and in the search projection the website reads (mandate 15:37 §10, §12)',
        'source', 'layer4-readiness', 'validation_layer', 'V4',
        'course_ids', case when r.field_code not in ('entry_matrix_first_run', 'entry_matrix_change', 'no_page_first_run', 'conjoint_rule_first_run', 'provider_description') then to_jsonb(r.ents[1:500]) else '[]'::jsonb end,
        'provider_ids', case when r.field_code in ('entry_matrix_first_run', 'entry_matrix_change', 'no_page_first_run', 'conjoint_rule_first_run', 'provider_description') then to_jsonb(r.ents[1:500]) else '[]'::jsonb end,
        'evidence', jsonb_build_object('approvals', r.n, 'decisions', to_jsonb(r.decs[1:20]), 'first_decided', r.first_at, 'last_decided', r.last_at, 'result', r.result, 'reason', r.reason),
        'severity', case when r.reason = 'manual_lock_kept' then 'P2' else 'P1' end,
        'root_cause_class', case when r.reason = 'manual_lock_kept' then 'human_decision' else 'code_defect' end, 'workstream', 'A4'), 'layer4-readiness');
      v_seen := v_seen || v_fp; v_iss := v_iss + 1;
    end loop;
    for r in select x.id, x.status from pipeline.integration_issues x
              where (x.fingerprint like 'l4\_not\_admitted:%' or x.fingerprint like 'l4\_not\_published:%') and x.status <> 'closed' and x.condition_cleared_at is null
                and not (x.fingerprint = any (v_seen)) loop
      update pipeline.integration_issues set condition_cleared_at = now() where id = r.id;
      insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
      values (r.id, 'not_observed', r.status, r.status, 'layer4-readiness', 'condition no longer observed; closes after verification');
    end loop;
  end if;
  v_out := jsonb_build_object('classified', v_cls, 'gates', v_g, 'closed', v_closed, 'reconcile', v_rec, 'approvals_checked', v_chk, 'issues', v_iss,
                              'switches', jsonb_build_object('readiness_on', security.pipeline_num_v1('layer4.readiness_on', 1), 'verify_on', security.pipeline_num_v1('layer4.verify_on', 1),
                                                             'arrival_guard_on', security.pipeline_num_v1('layer4.arrival_guard_on', 0), 'reconcile_supersede_on', security.pipeline_num_v1('layer4.reconcile_supersede_on', 0)),
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  insert into pipeline.layer4_readiness_runs(ms, result) values ((v_out->>'ms')::int, v_out);
  return v_out;
end $function$
