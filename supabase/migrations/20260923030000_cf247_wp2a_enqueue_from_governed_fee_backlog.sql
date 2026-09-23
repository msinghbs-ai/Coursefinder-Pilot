-- CF-CHG-20260915-247 WP2a — enqueue from the governed Layer 3 fee-validation backlog.
-- The previous version selected Layer 2 run items by blocker reason; none of that
-- population carried a governed provider_current_tuition target, and its JSON-null
-- check (->... is not null) never filtered, so candidate-bound validation could not
-- succeed. This version reads pipeline.cf245_layer3_fee_validation_backlog_v1 (identity
-- confirmed, regulatory code seen, international, basis requiring validation) and
-- requires the target to be a JSON object.
CREATE OR REPLACE FUNCTION public.layer3_enqueue_eligible_layer2_service(p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_caller text; v_result jsonb;
begin
  v_caller:=coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  with profile as (
    select id from pipeline.layer3_model_profiles
    where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused
      and coalesce((quality_benchmark->>'pass')::boolean,false)
    order by updated_at desc,id limit 1
  ), backlog as (
    select distinct on (b.source_record_id) i.id layer2_run_item_id, b.evidence_id, i.entity_type, i.entity_id,
      jsonb_build_object('provider_current_tuition', b.candidate_payload,
        'fee_candidates', coalesce(r.parsed_payload->'fee_candidates','[]'::jsonb),
        'fee_ambiguous', coalesce((r.parsed_payload->>'fee_ambiguous')::boolean,false),
        'identity_match', coalesce((r.parsed_payload->>'identity_match')::boolean,false),
        'expected_course_code', r.parsed_payload->'expected_course_code',
        'extraction_worker', r.parsed_payload->'extraction_worker',
        'source_record_id', r.source_record_id) candidate_context,
      i.completed_at
    from pipeline.cf245_layer3_fee_validation_backlog_v1 b
    join pipeline.course_fact_source_records r on r.id = b.source_record_id
    join pipeline.layer2_provider_attempts pa on coalesce(nullif(pa.metrics->>'normalised_evidence_id','')::uuid,pa.html_evidence_id,pa.raw_evidence_id) = b.evidence_id
    join pipeline.layer2_run_items i on i.job_id = pa.job_id and i.entity_id = b.course_id
    where jsonb_typeof(b.candidate_payload) = 'object'
      and exists(select 1 from pipeline.evidence_artifacts e where e.id=b.evidence_id and e.storage_path is not null and e.content_hash is not null)
    order by b.source_record_id, i.completed_at desc nulls last, i.id
  ), candidates as (
    select c.layer2_run_item_id, c.evidence_id, c.entity_type, c.entity_id, p.id profile_id,
      'requires_layer3_fee_validation'::text reason, c.candidate_context
    from backlog c cross join profile p
    where not exists(select 1 from pipeline.layer3_work_items w where w.layer2_run_item_id=c.layer2_run_item_id and w.evidence_id=c.evidence_id and w.task_class='provider_current_tuition_validation' and w.policy_version='cf247-v1')
    order by c.completed_at nulls last, c.layer2_run_item_id limit least(greatest(coalesce(p_limit,25),1),100)
  ), inserted as (
    insert into pipeline.layer3_work_items(layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,reason,candidate_context)
    select c.layer2_run_item_id,c.evidence_id,lower(c.entity_type),c.entity_id,'provider_current_tuition_validation',c.profile_id,c.reason,c.candidate_context
    from candidates c
    on conflict(layer2_run_item_id,evidence_id,task_class,policy_version) do nothing returning id
  )
  select jsonb_build_object('queued',count(*),'task_class','provider_current_tuition_validation','reason',case when exists(select 1 from profile) then 'eligible_candidate_validation_handoffs_enqueued' else 'no_benchmark_passed_executable_profile' end) into v_result from inserted;
  return v_result;
end $function$;
