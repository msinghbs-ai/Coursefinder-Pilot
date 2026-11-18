CREATE OR REPLACE FUNCTION security.cdesc_prompt_supersede_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_max int := security.pipeline_num_v1('layer4.reconcile_batch', 200)::int; v_ver text := security.cdesc_prompt_version_v1(); v_stamp text := security.course_description_machine_policy_stamp_v1();
        r record; v_n int := 0;
begin
  -- a first course description waiting in Layer 4 that an earlier prompt made, and that the machine rule declined for good, waits for nothing a person can usefully decide:
  -- it is superseded (decided_before: the machine decided it) and its reading is read again with the released prompt. A locked course is never touched.
  for r in select q.id, q.entity_id, q.evidence_id, q.layer3_state->>'prompt' pr,
                  case when coalesce(q.proposed_value->>'item_id', '') ~ '^\d+$' then (q.proposed_value->>'item_id')::bigint end item_id
             from pipeline.layer4_review_items q
            where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
              and coalesce(q.layer3_state->>'prompt', '') <> v_ver
              -- declined for good under the CURRENT policy (the same test as security.cdesc_provider_slots_v1): an item the new checks have not looked at yet waits for them
              and exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient
                             and d.policy_stamp = v_stamp)
              and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.entity_id and k.field in ('description', 'course_description', 'all'))
            order by q.created_at limit v_max
            for update of q skip locked loop
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: decided_before (declined for good by cdesc-machine-v2; read again with ' || v_ver || ')', 400)
     where id = r.id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.id, 'course_description_first_read', 'course', r.entity_id, 'decided_before', null,
            jsonb_build_object('by', 'cdesc-prompt-supersede', 'machine_outcome', 'declined', 'prompt_before', r.pr, 'prompt_after', v_ver, 'evidence_id', r.evidence_id), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using r.id;
    end if;
    -- security.course_description_review_trg_v1 has set the reading skipped ("not admitted in Layer 4 (superseded)"); it is marked to be read again
    update pipeline.field_enrich_items e set reason = left('superseded: declined for good under ' || coalesce(r.pr, 'an unrecorded prompt') || '; read again with ' || v_ver, 300), updated_at = now()
     where e.field = 'description' and e.course_id = r.entity_id and e.state = 'skipped' and (e.id = r.item_id or e.value->>'review_item_id' = r.id::text);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('superseded', v_n, 'prompt', v_ver, 'batch', v_max);
end $function$
