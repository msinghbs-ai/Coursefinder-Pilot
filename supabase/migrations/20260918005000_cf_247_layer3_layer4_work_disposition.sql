-- CF-CHG-20260915-247
-- Route service-owned Layer 3 unresolved outcomes to durable Layer 4 review.
-- Forward-only: preserves existing interpretation/admission/security contracts.
begin;

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

  if v_i.status not in ('no_candidate','low_confidence','rejected_validation') then
    raise exception 'interpretation is not a Layer 4 exception outcome';
  end if;

  v_reason:=coalesce(nullif(trim(p_reason),''),
    case v_i.status
      when 'no_candidate' then 'Layer 3 safely abstained; human resolution or more Evidence required'
      when 'low_confidence' then 'Layer 3 result is below the governed confidence threshold'
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
        'selected_evidence_reason',v_i.selected_evidence_reason
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
    and status in ('interpreting','no_candidate','rejected','validated','layer4_required');

  return jsonb_build_object(
    'ok',true,
    'work_item_id',v_w.id,
    'interpretation_id',v_i.id,
    'status','layer4_required',
    'review_item_id',v_review,
    'interpretation_status',v_i.status
  );
end $$;

revoke all on function public.layer3_route_work_item_layer4_service(uuid,uuid,text)
from public,anon,authenticated;
grant execute on function public.layer3_route_work_item_layer4_service(uuid,uuid,text)
to service_role;

commit;
