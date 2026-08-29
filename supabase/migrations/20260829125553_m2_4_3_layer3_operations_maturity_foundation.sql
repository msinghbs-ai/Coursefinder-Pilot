begin;

alter table pipeline.layer3_interpretations
  add column if not exists retry_count integer not null default 0 check (retry_count>=0),
  add column if not exists fallback_profile_id_used uuid references pipeline.layer3_model_profiles(id),
  add column if not exists execution_trace jsonb not null default '[]'::jsonb,
  add column if not exists selected_evidence_reason text;

update pipeline.layer3_model_profiles
set deterministic_validators = coalesce(deterministic_validators,'{}'::jsonb) || jsonb_build_object('review_confidence_min',0.80),updated_at=now()
where code='openrouter-free-router-v1';

update pipeline.layer3_model_profiles
set model_identifier='nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',retry_ceiling=2,max_output_tokens=1200,paused=true,
    last_validation_result=coalesce(last_validation_result,'{}'::jsonb) || jsonb_build_object('state','source_pattern_requalification_required','validated',false,'benchmark_passed',false,'message','M2.4.3 re-pinned to the last known available exact free model with bounded structured-output retries; full benchmark PASS still required before resume','change_control_ref','CF-CHG-20260829-047','completed_at',now()),
    change_control_ref='CF-CHG-20260829-047',uat_ref='M2.4.3-source-pattern-requalification',updated_at=now()
where code='openrouter-source-pattern-v1';

CREATE OR REPLACE FUNCTION security.layer3_evidence_candidates_impl(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'auth'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  return coalesce((
    with eligible as (
      select
        ri.entity_type,ri.entity_id,ri.status as layer2_status,ri.outcome_code,
        pa.id as provider_attempt_id,pa.completed_at,
        ev.id as evidence_id,ev.evidence_type,ev.source_url,ev.mime_type,ev.content_hash,
        ev.captured_at,ev.review_state,
        case when ev.id=pa.raw_evidence_id then 1 else 2 end as evidence_rank,
        row_number() over(
          partition by ri.entity_type,ri.entity_id
          order by
            case when ev.id=pa.raw_evidence_id then 1 else 2 end,
            pa.completed_at desc nulls last,
            ev.captured_at desc nulls last,
            ev.id
        ) as rn
      from pipeline.layer2_run_items ri
      join pipeline.layer2_provider_attempts pa on pa.job_id=ri.job_id and pa.status='succeeded'
      join lateral (
        select e.*
        from pipeline.evidence_artifacts e
        where e.id in (pa.raw_evidence_id,pa.html_evidence_id)
          and e.storage_path is not null
          and e.content_hash is not null
          and (e.valid_to is null or e.valid_to>now())
          and coalesce(e.review_state,'') not in ('rejected','invalid')
          and (
            e.mime_type is null
            or e.mime_type like 'text/%'
            or e.mime_type in ('application/json','application/xml','application/xhtml+xml')
          )
        order by case when e.id=pa.raw_evidence_id then 1 else 2 end
      ) ev on true
      where ri.entity_type='course'
        and ri.status='layer3_required'
    ),
    chosen as (
      select e.*,
             coalesce(c.display_title,c.canonical_title,c.course_code,e.entity_id::text) as entity_label
      from eligible e
      left join catalogue.courses c on c.id=e.entity_id
      where e.rn=1
      order by e.completed_at desc nulls last,e.captured_at desc nulls last
      limit least(greatest(coalesce(p_limit,50),1),100)
    )
    select jsonb_agg(jsonb_build_object(
      'entity_type',entity_type,
      'entity_id',entity_id,
      'entity_label',entity_label,
      'layer2_status',layer2_status,
      'outcome_code',outcome_code,
      'provider_attempt_id',provider_attempt_id,
      'evidence_id',evidence_id,
      'evidence_type',evidence_type,
      'source_url',source_url,
      'mime_type',mime_type,
      'content_hash',content_hash,
      'captured_at',captured_at,
      'review_state',review_state,
      'selection_reason',case when evidence_rank=1
        then 'latest_successful_layer2_native_evidence'
        else 'latest_successful_layer2_html_evidence'
      end
    ))
    from chosen
  ),'[]'::jsonb);
end $function$


CREATE OR REPLACE FUNCTION public.layer3_evidence_candidates(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.layer3_evidence_candidates_impl(p_limit) $function$

revoke all on function public.layer3_evidence_candidates(integer) from public,anon;
grant execute on function public.layer3_evidence_candidates(integer) to authenticated;

CREATE OR REPLACE FUNCTION public.layer3_reserve_interpretation_service(p_actor uuid, p_evidence_id uuid, p_entity_type text, p_entity_id uuid, p_task_class text, p_profile_id uuid, p_layer2_state jsonb DEFAULT '{}'::jsonb, p_revalidation_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare
  v_rank int:=0; v_ev pipeline.evidence_artifacts%rowtype; v_p pipeline.layer3_model_profiles%rowtype;
  v_prev pipeline.layer3_interpretations%rowtype; v_reason text; v_id uuid; v_selection text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and r.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  select * into v_ev from pipeline.evidence_artifacts where id=p_evidence_id;
  if not found or v_ev.content_hash is null then raise exception 'governed evidence with content hash required'; end if;

  select * into v_p from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'model profile not found'; end if;
  if not v_p.enabled or v_p.paused then raise exception 'model profile not executable'; end if;
  if coalesce((v_p.quality_benchmark->>'pass')::boolean,false) is not true then
    raise exception 'model profile quality benchmark not passed';
  end if;
  if not (p_task_class=any(v_p.allowed_task_classes)) then raise exception 'task class not allowed by profile'; end if;

  if coalesce(p_layer2_state->>'status','')='resolved_l2' then
    return jsonb_build_object('call_required',false,'reason','layer2_resolved','evidence_hash',v_ev.content_hash);
  end if;

  perform pg_advisory_xact_lock(hashtext(p_evidence_id::text||':'||p_entity_id::text||':'||p_task_class||':'||p_profile_id::text));

  select * into v_prev
  from pipeline.layer3_interpretations
  where entity_type=lower(p_entity_type) and entity_id=p_entity_id and task_class=p_task_class
    and profile_id=p_profile_id and status in ('validated','low_confidence','no_candidate')
  order by created_at desc limit 1;

  if p_revalidation_ref is not null then
    if length(trim(p_revalidation_ref))<5 then raise exception 'governed revalidation reference required'; end if;
    v_reason:='governed_revalidation';
  elsif found and v_prev.evidence_hash=v_ev.content_hash
        and (v_prev.interpretation_expires_at is null or v_prev.interpretation_expires_at>now()) then
    return jsonb_build_object(
      'call_required',false,'reason','unchanged_evidence',
      'prior_interpretation_id',v_prev.id,'evidence_hash',v_ev.content_hash
    );
  elsif found and v_prev.evidence_hash<>v_ev.content_hash then v_reason:='changed_evidence';
  elsif found and v_prev.interpretation_expires_at is not null and v_prev.interpretation_expires_at<=now() then v_reason:='freshness_expired';
  elsif coalesce(p_layer2_state->>'status','') in ('unresolved','blocked','partial','escalated_l3','layer3_required') then v_reason:='layer2_unresolved';
  else v_reason:='new_evidence';
  end if;

  v_selection:=nullif(p_layer2_state->>'evidence_selection_reason','');

  insert into pipeline.layer3_interpretations(
    evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,prompt_profile_version,
    eligibility_reason,revalidation_ref,layer2_state,requested_by,selected_evidence_reason,
    change_control_ref,uat_ref
  ) values(
    p_evidence_id,v_ev.content_hash,lower(p_entity_type),p_entity_id,p_task_class,p_profile_id,
    v_p.prompt_profile_version,v_reason,p_revalidation_ref,coalesce(p_layer2_state,'{}'::jsonb),
    p_actor,v_selection,'CF-CHG-20260829-047','M2.4.3-layer3-operations'
  ) returning id into v_id;

  return jsonb_build_object(
    'call_required',true,'interpretation_id',v_id,'eligibility_reason',v_reason,
    'evidence_hash',v_ev.content_hash,'selected_evidence_reason',v_selection,
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
end $function$


CREATE OR REPLACE FUNCTION public.layer3_fallback_profile_service(p_profile_id uuid, p_task_class text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_f pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  select f.* into v_f
  from pipeline.layer3_model_profiles p
  join pipeline.layer3_model_profiles f on f.id=p.fallback_profile_id
  where p.id=p_profile_id
    and f.enabled and not f.paused
    and p_task_class=any(f.allowed_task_classes)
    and coalesce((f.quality_benchmark->>'pass')::boolean,false) is true;
  if not found then return null; end if;
  return jsonb_build_object(
    'id',v_f.id,'aggregator_provider',v_f.aggregator_provider,'base_url',v_f.base_url,
    'model_identifier',v_f.model_identifier,'secret_env_key',v_f.secret_env_key,
    'prompt_profile_version',v_f.prompt_profile_version,'prompt_system',v_f.prompt_system,
    'validators',v_f.deterministic_validators,'max_output_tokens',v_f.max_output_tokens,
    'retry_ceiling',v_f.retry_ceiling,'timeout_ms',v_f.timeout_ms,'cost_ceiling_usd',v_f.cost_ceiling_usd
  );
end $function$

revoke all on function public.layer3_fallback_profile_service(uuid,text) from public,anon,authenticated;
grant execute on function public.layer3_fallback_profile_service(uuid,text) to service_role;

CREATE OR REPLACE FUNCTION public.layer3_complete_interpretation_service(p_interpretation_id uuid, p_raw_result jsonb, p_candidate_value jsonb, p_confidence numeric, p_rationale text, p_evidence_quotes jsonb, p_validator_result jsonb, p_valid boolean, p_response_model text, p_input_tokens integer, p_output_tokens integer, p_estimated_cost_usd numeric, p_expiry timestamp with time zone, p_external_call_count integer, p_call_latency_ms integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue'
AS $function$
declare
  v_i pipeline.layer3_interpretations%rowtype; v_review uuid; v_before jsonb;
  v_threshold numeric:=0; v_low_confidence boolean:=false; v_status text; v_trace jsonb:='[]'::jsonb;
  v_fallback uuid;
begin
  select * into v_i from pipeline.layer3_interpretations where id=p_interpretation_id for update;
  if not found then raise exception 'interpretation not found'; end if;
  if v_i.status not in ('reserved','calling') then raise exception 'interpretation is not completable'; end if;
  if coalesce(p_estimated_cost_usd,0)<0 then raise exception 'invalid cost'; end if;
  if p_external_call_count is not null and p_external_call_count<0 then raise exception 'invalid external call count'; end if;
  if p_call_latency_ms is not null and p_call_latency_ms<0 then raise exception 'invalid call latency'; end if;

  select coalesce((deterministic_validators->>'review_confidence_min')::numeric,0)
    into v_threshold from pipeline.layer3_model_profiles where id=v_i.profile_id;
  v_low_confidence:=p_valid and p_candidate_value is not null and p_candidate_value<>'null'::jsonb
                    and coalesce(p_confidence,0)<v_threshold;
  v_status:=case
    when not p_valid then 'rejected_validation'
    when p_candidate_value is null or p_candidate_value='null'::jsonb then 'no_candidate'
    when v_low_confidence then 'low_confidence'
    else 'validated'
  end;
  v_trace:=coalesce(p_raw_result->'_coursefinder_trace','[]'::jsonb);
  begin
    v_fallback:=nullif(p_raw_result->'_coursefinder_meta'->>'fallback_profile_id','')::uuid;
  exception when others then v_fallback:=null;
  end;

  update pipeline.layer3_interpretations set
    raw_result=p_raw_result,candidate_value=p_candidate_value,confidence=p_confidence,rationale=p_rationale,
    evidence_quotes=coalesce(p_evidence_quotes,'[]'::jsonb),
    validator_result=coalesce(p_validator_result,'{}'::jsonb)
      || jsonb_build_object('review_confidence_min',v_threshold,'low_confidence',v_low_confidence),
    status=v_status,aggregator_response_model=p_response_model,
    input_tokens=p_input_tokens,output_tokens=p_output_tokens,
    estimated_cost_usd=coalesce(p_estimated_cost_usd,0),
    external_call_count=coalesce(p_external_call_count,0),
    retry_count=greatest(coalesce(p_external_call_count,0)-1,0),
    fallback_profile_id_used=v_fallback,
    execution_trace=v_trace,
    call_latency_ms=p_call_latency_ms,call_completed_at=now(),
    interpretation_expires_at=case when v_status='validated' then p_expiry else null end
  where id=p_interpretation_id;

  if p_valid then
    if v_i.entity_type='course' then
      if v_i.task_class='course_description' then select to_jsonb(description) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='delivery_mode' then select to_jsonb(delivery_mode) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='duration' then select jsonb_build_object('value',duration_value,'unit',duration_unit) into v_before from catalogue.courses where id=v_i.entity_id;
      elsif v_i.task_class='official_course_url' then
        select to_jsonb(url) into v_before from catalogue.course_links
        where course_id=v_i.entity_id and link_type='official_course' and coalesce(status,'active')='active'
        order by last_verified_at desc nulls last,created_at desc limit 1;
      end if;
    end if;

    insert into pipeline.layer4_review_items(
      entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,
      proposed_value,layer2_state,layer3_state,escalation_reason,change_control_ref
    ) values(
      v_i.entity_type,v_i.entity_id,v_i.task_class,v_i.evidence_id,v_i.id,v_before,p_candidate_value,v_i.layer2_state,
      jsonb_build_object(
        'profile_id',v_i.profile_id,'prompt_profile_version',v_i.prompt_profile_version,
        'candidate_value',p_candidate_value,'confidence',p_confidence,'rationale',p_rationale,
        'validator_result',coalesce(p_validator_result,'{}'::jsonb),
        'response_model',p_response_model,'external_call_count',p_external_call_count,
        'retry_count',greatest(coalesce(p_external_call_count,0)-1,0),
        'call_latency_ms',p_call_latency_ms,'input_tokens',p_input_tokens,'output_tokens',p_output_tokens,
        'estimated_cost_usd',p_estimated_cost_usd,'selected_evidence_reason',v_i.selected_evidence_reason,
        'low_confidence',v_low_confidence,'review_confidence_min',v_threshold
      ),
      case
        when p_candidate_value is null or p_candidate_value='null'::jsonb
          then 'Layer 3 produced no candidate; human resolution or more Evidence required'
        when v_low_confidence
          then 'Layer 3 candidate is below the governed confidence threshold'
        else 'validated Layer 3 candidate requires human decision'
      end,
      'CF-CHG-20260829-047'
    ) returning id into v_review;
  end if;

  return jsonb_build_object(
    'ok',true,'interpretation_id',p_interpretation_id,'validated',p_valid,
    'status',v_status,'review_item_id',v_review,'external_call_count',p_external_call_count,
    'retry_count',greatest(coalesce(p_external_call_count,0)-1,0),
    'call_latency_ms',p_call_latency_ms,'review_confidence_min',v_threshold
  );
end $function$


CREATE OR REPLACE FUNCTION security.layer3_recent_interpretations_impl(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
begin
 if auth.uid() is null or security.current_role_rank()<3 then
   raise exception 'curator role required' using errcode='42501';
 end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
   select i.id,i.evidence_id,i.entity_type,i.entity_id,i.task_class,i.eligibility_reason,
          i.selected_evidence_reason,i.status,i.candidate_value,i.confidence,i.rationale,
          i.aggregator_response_model,i.input_tokens,i.output_tokens,i.estimated_cost_usd,
          i.external_call_count,i.retry_count,i.call_latency_ms,i.fallback_profile_id_used,
          i.execution_trace,i.interpretation_expires_at,i.change_control_ref,i.uat_ref,i.created_at,
          p.code as profile_code,p.aggregator_provider,p.model_identifier,p.prompt_profile_version,
          r.id as review_item_id,r.status as review_state,r.escalation_reason
   from pipeline.layer3_interpretations i
   join pipeline.layer3_model_profiles p on p.id=i.profile_id
   left join lateral (
     select rr.id,rr.status,rr.escalation_reason
     from pipeline.layer4_review_items rr
     where rr.layer3_interpretation_id=i.id
     order by rr.created_at desc limit 1
   ) r on true
   order by i.created_at desc limit least(greatest(p_limit,1),250)
 ) x),'[]'::jsonb);
end $function$

commit;
