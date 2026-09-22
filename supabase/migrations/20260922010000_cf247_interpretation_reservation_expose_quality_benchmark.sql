-- CF-CHG-20260915-247
-- CF-247 3B2B foundation: additively expose the profile's quality_benchmark
-- (including binding_hash, already read internally by this same function for
-- its existing pass-check) in the returned profile object, so the calling
-- interpreter can independently verify the current binding hash still
-- matches the one recorded at qualification time before executing the
-- provider model. No gating/authority logic in this function changes: the
-- existing enabled/paused/quality_benchmark.pass/task_class checks are
-- byte-identical to the prior definition. This migration only adds one field
-- to the returned jsonb object.
begin;

create or replace function public.layer3_reserve_work_interpretation_service(
  p_work_item_id uuid,
  p_worker text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare
  v_caller text;
  v_work pipeline.layer3_work_items%rowtype;
  v_ev pipeline.evidence_artifacts%rowtype;
  v_p pipeline.layer3_model_profiles%rowtype;
  v_interpretation_id uuid;
begin
  v_caller:=coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.role',true),''),
    nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',
    auth.role(),
    session_user
  );
  if v_caller not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_work_item_id is null then raise exception 'work_item_id required'; end if;
  if nullif(trim(p_worker),'') is null then raise exception 'worker required'; end if;

  select * into v_work
  from pipeline.layer3_work_items
  where id=p_work_item_id
  for update;
  if not found then raise exception 'Layer 3 work item not found'; end if;
  if v_work.status<>'reserved' then raise exception 'Layer 3 work item must be reserved'; end if;
  if coalesce(v_work.reserved_by,'')<>trim(p_worker) then raise exception 'Layer 3 work reservation owner mismatch'; end if;
  if v_work.profile_id is null then raise exception 'Layer 3 work item profile required'; end if;
  if coalesce(jsonb_typeof(v_work.candidate_context),'null')<>'object' or v_work.candidate_context='{}'::jsonb then
    raise exception 'persisted candidate_context required';
  end if;

  select * into v_ev from pipeline.evidence_artifacts where id=v_work.evidence_id;
  if not found or v_ev.content_hash is null or v_ev.storage_path is null then
    raise exception 'retained governed Evidence required';
  end if;

  select * into v_p from pipeline.layer3_model_profiles where id=v_work.profile_id;
  if not found then raise exception 'model profile not found'; end if;
  if not v_p.enabled or v_p.paused then raise exception 'model profile not executable'; end if;
  if coalesce((v_p.quality_benchmark->>'pass')::boolean,false) is not true then
    raise exception 'model profile quality benchmark not passed';
  end if;
  if not (v_work.task_class=any(v_p.allowed_task_classes)) then
    raise exception 'task class not allowed by profile';
  end if;

  insert into pipeline.layer3_interpretations(
    evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,
    prompt_profile_version,eligibility_reason,revalidation_ref,layer2_state,
    requested_by,selected_evidence_reason,change_control_ref,uat_ref
  ) values(
    v_work.evidence_id,v_ev.content_hash,v_work.entity_type,v_work.entity_id,
    v_work.task_class,v_work.profile_id,v_p.prompt_profile_version,
    'layer2_unresolved',null,
    jsonb_build_object(
      'status','layer3_required',
      'layer2_run_item_id',v_work.layer2_run_item_id,
      'work_item_id',v_work.id,
      'reason',v_work.reason,
      'candidate_context',v_work.candidate_context,
      'policy_version',v_work.policy_version
    ),
    null,v_work.reason,'CF-CHG-20260915-247','M2.4.7-layer3-work-dispatch'
  ) returning id into v_interpretation_id;

  update pipeline.layer3_work_items
  set status='interpreting',interpretation_id=v_interpretation_id,updated_at=now()
  where id=v_work.id and status='reserved' and reserved_by=trim(p_worker);
  if not found then raise exception 'Layer 3 work transition to interpreting failed'; end if;

  return jsonb_build_object(
    'call_required',true,
    'work_item_id',v_work.id,
    'interpretation_id',v_interpretation_id,
    'evidence_id',v_work.evidence_id,
    'attempt_count',v_work.attempt_count,
    'entity_type',v_work.entity_type,
    'entity_id',v_work.entity_id,
    'task_class',v_work.task_class,
    'candidate_context',v_work.candidate_context,
    'evidence',jsonb_build_object(
      'id',v_ev.id,
      'storage_path',v_ev.storage_path,
      'mime_type',v_ev.mime_type,
      'content_hash',v_ev.content_hash,
      'source_url',v_ev.source_url
    ),
    'profile',jsonb_build_object(
      'id',v_p.id,'aggregator_provider',v_p.aggregator_provider,'base_url',v_p.base_url,
      'model_identifier',v_p.model_identifier,'secret_env_key',v_p.secret_env_key,
      'prompt_profile_version',v_p.prompt_profile_version,'prompt_system',v_p.prompt_system,
      'schema',v_p.structured_output_schema,'validators',v_p.deterministic_validators,
      'max_input_tokens',v_p.max_input_tokens,'max_output_tokens',v_p.max_output_tokens,
      'requests_per_minute',v_p.requests_per_minute,'requests_per_day',v_p.requests_per_day,
      'retry_ceiling',v_p.retry_ceiling,'timeout_ms',v_p.timeout_ms,
      'cost_ceiling_usd',v_p.cost_ceiling_usd,'fallback_profile_id',v_p.fallback_profile_id,
      'quality_benchmark',v_p.quality_benchmark
    )
  );
end $$;

revoke all on function public.layer3_reserve_work_interpretation_service(uuid,text) from public,anon,authenticated;
grant execute on function public.layer3_reserve_work_interpretation_service(uuid,text) to service_role;

commit;
