-- CF-CHG-20260915-247
-- Reconcile service-role detection with current PostgREST JWT claim exposure.
-- Access remains restricted to postgres/service_role; anon/authenticated grants stay revoked.
begin;

create or replace function public.layer3_reserve_work_service(p_worker text,p_limit integer default 10)
returns jsonb
language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_result jsonb; v_caller text;
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
  if nullif(trim(p_worker),'') is null then raise exception 'worker required'; end if;

  -- Reclaim abandoned leases. Poison work is parked after five reservations.
  update pipeline.layer3_work_items
  set status=case when attempt_count>=5 then 'parked' else 'pending' end,
      available_at=case when attempt_count>=5 then available_at else now() end,
      completed_at=case when attempt_count>=5 then now() else null end,
      last_error=case when attempt_count>=5 then 'reservation lease expired after maximum attempts' else 'reservation lease expired; requeued' end,
      reserved_at=null,reserved_by=null,updated_at=now()
  where status='reserved' and reserved_at < now()-interval '15 minutes';

  with picked as (
    select w.id
    from pipeline.layer3_work_items w
    left join pipeline.layer3_model_profiles p on p.id=w.profile_id
    where w.status in ('pending','failed') and w.available_at<=now() and w.attempt_count<5
      and (w.profile_id is null or (p.enabled and not p.paused and coalesce((p.quality_benchmark->>'pass')::boolean,false)))
    order by w.created_at,w.id
    for update of w skip locked
    limit least(greatest(coalesce(p_limit,10),1),50)
  ), reserved as (
    update pipeline.layer3_work_items w set status='reserved',reserved_at=now(),reserved_by=trim(p_worker),attempt_count=w.attempt_count+1,updated_at=now()
    from picked where w.id=picked.id
    returning w.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'layer2_run_item_id',layer2_run_item_id,'evidence_id',evidence_id,'entity_type',entity_type,'entity_id',entity_id,
    'task_class',task_class,'profile_id',profile_id,'attempt_count',attempt_count,'reason',reason,'policy_version',policy_version
  ) order by created_at,id),'[]'::jsonb) into v_result from reserved;
  return v_result;
end $$;

create or replace function public.layer3_work_item_transition_service(
  p_work_item_id uuid,p_from_status text,p_to_status text,p_interpretation_id uuid default null,p_error text default null,p_retry_after_seconds integer default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_ok boolean; v_caller text;
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
  if p_to_status not in ('pending','reserved','interpreting','validated','no_candidate','rejected','admission_pending','layer4_required','admitted','parked','failed') then raise exception 'invalid target status'; end if;
  update pipeline.layer3_work_items set
    status=case when p_to_status='failed' and attempt_count>=5 then 'parked' else p_to_status end,
    interpretation_id=coalesce(p_interpretation_id,interpretation_id),
    last_error=case when p_to_status in ('failed','parked','rejected') then nullif(left(coalesce(p_error,''),2000),'') else null end,
    available_at=case when p_to_status='failed' and attempt_count<5 then now()+make_interval(secs=>least(greatest(coalesce(p_retry_after_seconds,60),1),86400)) else available_at end,
    completed_at=case when p_to_status in ('validated','no_candidate','rejected','layer4_required','admitted','parked') or (p_to_status='failed' and attempt_count>=5) then now() else null end,
    reserved_at=case when p_to_status in ('reserved','interpreting') then reserved_at else null end,
    reserved_by=case when p_to_status in ('reserved','interpreting') then reserved_by else null end,
    updated_at=now()
  where id=p_work_item_id and status=p_from_status;
  v_ok:=found;
  return jsonb_build_object('ok',v_ok,'work_item_id',p_work_item_id,'status',case when v_ok then (select status from pipeline.layer3_work_items where id=p_work_item_id) else null end);
end $$;

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
    'entity_type',v_work.entity_type,
    'entity_id',v_work.entity_id,
    'task_class',v_work.task_class,
    'candidate_context',v_work.candidate_context,
    'profile',jsonb_build_object(
      'id',v_p.id,'aggregator_provider',v_p.aggregator_provider,'base_url',v_p.base_url,
      'model_identifier',v_p.model_identifier,'secret_env_key',v_p.secret_env_key,
      'prompt_profile_version',v_p.prompt_profile_version,'prompt_system',v_p.prompt_system,
      'schema',v_p.structured_output_schema,'validators',v_p.deterministic_validators,
      'max_input_tokens',v_p.max_input_tokens,'max_output_tokens',v_p.max_output_tokens,
      'requests_per_minute',v_p.requests_per_minute,'requests_per_day',v_p.requests_per_day,
      'retry_ceiling',v_p.retry_ceiling,'timeout_ms',v_p.timeout_ms,
      'cost_ceiling_usd',v_p.cost_ceiling_usd,'fallback_profile_id',v_p.fallback_profile_id
    )
  );
end $$;

create or replace function public.layer3_route_work_item_layer4_service(
  p_work_item_id uuid,
  p_interpretation_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare
  v_caller text;
  v_w pipeline.layer3_work_items%rowtype;
  v_i pipeline.layer3_interpretations%rowtype;
  v_review uuid;
  v_reason text;
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

  select * into v_w from pipeline.layer3_work_items
  where id=p_work_item_id
  for update;
  if not found then raise exception 'Layer 3 work item not found'; end if;

  select * into v_i from pipeline.layer3_interpretations
  where id=p_interpretation_id;
  if not found then raise exception 'Layer 3 interpretation not found'; end if;

  if v_i.id is distinct from v_w.interpretation_id
     or v_i.evidence_id is distinct from v_w.evidence_id
     or v_i.entity_type is distinct from v_w.entity_type
     or v_i.entity_id is distinct from v_w.entity_id
     or v_i.task_class is distinct from v_w.task_class then
    raise exception 'work item / interpretation lineage mismatch';
  end if;

  if v_i.status not in ('no_candidate','low_confidence','rejected_validation','provider_error') then
    raise exception 'interpretation is not a Layer 4 exception outcome';
  end if;

  v_reason:=coalesce(nullif(trim(p_reason),''),
    case v_i.status
      when 'no_candidate' then 'Layer 3 safely abstained; human resolution or more Evidence required'
      when 'low_confidence' then 'Layer 3 result is below the governed confidence threshold'
      when 'provider_error' then 'Layer 3 provider/transport retries exhausted; human resolution or later retry required'
      else 'Layer 3 deterministic validation rejected the model result'
    end
  );

  select id into v_review
  from pipeline.layer4_review_items
  where layer3_interpretation_id=v_i.id
  order by created_at desc
  limit 1;

  if v_review is null then
    insert into pipeline.layer4_review_items(
      entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,
      before_value,proposed_value,layer2_state,layer3_state,escalation_reason,change_control_ref
    ) values(
      v_i.entity_type,v_i.entity_id,v_i.task_class,v_i.evidence_id,v_i.id,
      null,v_i.candidate_value,coalesce(v_i.layer2_state,'{}'::jsonb),
      jsonb_build_object(
        'status',v_i.status,
        'profile_id',v_i.profile_id,
        'prompt_profile_version',v_i.prompt_profile_version,
        'candidate_value',v_i.candidate_value,
        'candidate_context',v_w.candidate_context,
        'confidence',v_i.confidence,
        'rationale',v_i.rationale,
        'evidence_quotes',coalesce(v_i.evidence_quotes,'[]'::jsonb),
        'validator_result',coalesce(v_i.validator_result,'{}'::jsonb),
        'response_model',v_i.aggregator_response_model,
        'external_call_count',v_i.external_call_count,
        'retry_count',v_i.retry_count,
        'call_latency_ms',v_i.call_latency_ms,
        'input_tokens',v_i.input_tokens,
        'output_tokens',v_i.output_tokens,
        'estimated_cost_usd',v_i.estimated_cost_usd,
        'selected_evidence_reason',v_i.selected_evidence_reason,
        'work_attempt_count',v_w.attempt_count
      ),
      v_reason,
      'CF-CHG-20260915-247'
    ) returning id into v_review;
  end if;

  update pipeline.layer3_work_items
  set status='layer4_required',
      interpretation_id=v_i.id,
      completed_at=coalesce(completed_at,now()),
      reserved_at=null,
      reserved_by=null,
      last_error=null,
      updated_at=now()
  where id=v_w.id
    and status in ('interpreting','no_candidate','rejected','validated','failed','parked','layer4_required');

  return jsonb_build_object(
    'ok',true,
    'work_item_id',v_w.id,
    'interpretation_id',v_i.id,
    'status','layer4_required',
    'review_item_id',v_review,
    'interpretation_status',v_i.status,
    'attempt_count',v_w.attempt_count
  );
end $$;

revoke all on function public.layer3_reserve_work_service(text,integer) from public,anon,authenticated;
grant execute on function public.layer3_reserve_work_service(text,integer) to service_role;
revoke all on function public.layer3_work_item_transition_service(uuid,text,text,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.layer3_work_item_transition_service(uuid,text,text,uuid,text,integer) to service_role;
revoke all on function public.layer3_reserve_work_interpretation_service(uuid,text) from public,anon,authenticated;
grant execute on function public.layer3_reserve_work_interpretation_service(uuid,text) to service_role;
revoke all on function public.layer3_route_work_item_layer4_service(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.layer3_route_work_item_layer4_service(uuid,uuid,text) to service_role;

commit;
