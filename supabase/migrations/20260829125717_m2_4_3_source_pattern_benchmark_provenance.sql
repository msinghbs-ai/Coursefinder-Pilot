begin;
CREATE OR REPLACE FUNCTION public.layer3_source_pattern_benchmark_record_service(p_pass boolean, p_provider_cases jsonb, p_control_cases jsonb, p_returned_models text[], p_external_call_count integer, p_input_tokens integer, p_output_tokens integer, p_estimated_cost_usd numeric, p_max_latency_ms integer, p_evidence_ids uuid[], p_summary text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare p pipeline.layer3_model_profiles%rowtype; v_run uuid; v_state text;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-source-pattern-v1' for update;
  if not found then raise exception 'source-pattern profile not found'; end if;
  v_state:=case when p_pass then 'source_pattern_benchmark_passed' else 'source_pattern_benchmark_failed' end;
  insert into pipeline.layer3_quality_benchmark_runs(
    profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,
    returned_models,external_call_count,input_tokens,output_tokens,estimated_cost_usd,
    max_latency_ms,evidence_ids,prompt_profile_version,validator_profile,summary,
    change_control_ref,uat_ref,completed_at
  ) values(
    p.id,'63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid,
    case when p_pass then 'pass' else 'fail' end,
    coalesce(p_provider_cases,'[]'::jsonb),coalesce(p_control_cases,'[]'::jsonb),
    p.model_identifier,coalesce(p_returned_models,'{}'::text[]),
    greatest(coalesce(p_external_call_count,0),0),greatest(coalesce(p_input_tokens,0),0),
    greatest(coalesce(p_output_tokens,0),0),greatest(coalesce(p_estimated_cost_usd,0),0),
    greatest(coalesce(p_max_latency_ms,0),0),coalesce(p_evidence_ids,'{}'::uuid[]),
    p.prompt_profile_version,p.deterministic_validators,left(coalesce(p_summary,''),1000),
    'CF-CHG-20260829-047','M2.4.3-source-pattern-requalification',now()
  ) returning id into v_run;
  update pipeline.layer3_model_profiles
  set paused=not p_pass,
      quality_benchmark=jsonb_build_object(
        'run_id',v_run,'pass',p_pass,'completed_at',now(),'configured_model',p.model_identifier,
        'returned_models',coalesce(p_returned_models,'{}'::text[]),
        'external_call_count',coalesce(p_external_call_count,0),
        'input_tokens',coalesce(p_input_tokens,0),'output_tokens',coalesce(p_output_tokens,0),
        'estimated_cost_usd',coalesce(p_estimated_cost_usd,0),'max_latency_ms',coalesce(p_max_latency_ms,0),
        'summary',left(coalesce(p_summary,''),1000),
        'change_control_ref','CF-CHG-20260829-047',
        'uat_ref','M2.4.3-source-pattern-requalification'
      ),
      last_validation_result=jsonb_build_object(
        'state',v_state,'validated',p_pass,'benchmark_passed',p_pass,'benchmark_run_id',v_run,
        'completed_at',now(),'task_class','source_pattern','credential_source','server_runtime',
        'message',left(coalesce(p_summary,''),500),
        'change_control_ref','CF-CHG-20260829-047',
        'uat_ref','M2.4.3-source-pattern-requalification'
      ),
      change_control_ref='CF-CHG-20260829-047',
      uat_ref='M2.4.3-source-pattern-requalification',
      updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',p_pass,'run_id',v_run,'state',v_state,'profile_id',p.id,'profile_paused',not p_pass);
end $function$

revoke all on function public.layer3_source_pattern_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) from public,anon,authenticated;
grant execute on function public.layer3_source_pattern_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) to service_role;
commit;
