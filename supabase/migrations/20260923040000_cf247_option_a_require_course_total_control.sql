-- CF-CHG-20260915-247 option A: the ambiguous_basis_course_total control (a page
-- stating a course total where Layer 2 left the basis ambiguous) becomes a required,
-- gating benchmark control. Only the required-controls list changes; the rest of the
-- 12-argument recorder is identical to 20260922050100.
CREATE OR REPLACE FUNCTION public.layer3_cf245_tuition_benchmark_record_service(p_provider_cases jsonb, p_control_cases jsonb, p_returned_models text[], p_external_call_count integer, p_input_tokens integer, p_output_tokens integer, p_estimated_cost_usd numeric, p_max_latency_ms integer, p_evidence_ids uuid[], p_summary text, p_binding_hash text, p_profile_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare p pipeline.layer3_model_profiles%rowtype;v_run uuid;v_provider_ok boolean;v_controls_ok boolean;v_model_ok boolean;v_cost_ok boolean;v_pass boolean;v_required_controls text[]:=array['ambiguous_multiple_equal_rank','low_confidence_missing_basis','loan_cap_or_deposit','unsupported_currency','ambiguous_basis_course_total'];
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  if p_binding_hash is null or p_binding_hash !~ '^[0-9a-f]{64}$' then raise exception 'source-derived binding hash required' using errcode='22023'; end if;
  if p_profile_id is null then raise exception 'profile_id required' using errcode='22023'; end if;
  select * into p from pipeline.layer3_model_profiles where id=p_profile_id for update;
  if not found or not p.enabled then raise exception 'CF-245 tuition validation profile unavailable'; end if;
  select coalesce(jsonb_array_length(coalesce(p_provider_cases,'[]'::jsonb))>=3,false)
     and not exists(select 1 from jsonb_array_elements(coalesce(p_provider_cases,'[]'::jsonb)) c where coalesce((c->>'valid')::boolean,false)=false)
    into v_provider_ok;
  select not exists(select 1 from unnest(v_required_controls) r where not exists(select 1 from jsonb_array_elements(coalesce(p_control_cases,'[]'::jsonb)) c where c->>'case'=r and coalesce((c->>'valid')::boolean,false))) into v_controls_ok;
  v_model_ok:=coalesce(array_length(p_returned_models,1),0)>0 and not exists(select 1 from unnest(coalesce(p_returned_models,'{}'::text[])) m where m<>p.model_identifier);
  v_cost_ok:=greatest(coalesce(p_estimated_cost_usd,0),0)<=greatest(coalesce(p.cost_ceiling_usd,0),0);
  v_pass:=coalesce(v_provider_ok,false) and coalesce(v_controls_ok,false) and coalesce(v_model_ok,false) and coalesce(v_cost_ok,false);
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,estimated_cost_usd,max_latency_ms,evidence_ids,binding_hash,prompt_profile_version,validator_profile,summary,change_control_ref,uat_ref,completed_at)
  values(p.id,'00000000-0000-0000-0000-000000000000'::uuid,case when v_pass then 'pass' else 'fail' end,coalesce(p_provider_cases,'[]'::jsonb),coalesce(p_control_cases,'[]'::jsonb),p.model_identifier,coalesce(p_returned_models,'{}'::text[]),greatest(coalesce(p_external_call_count,0),0),greatest(coalesce(p_input_tokens,0),0),greatest(coalesce(p_output_tokens,0),0),greatest(coalesce(p_estimated_cost_usd,0),0),greatest(coalesce(p_max_latency_ms,0),0),coalesce(p_evidence_ids,'{}'::uuid[]),p_binding_hash,p.prompt_profile_version,coalesce(p.deterministic_validators,'{}'::jsonb),left(coalesce(p_summary,''),1000),'CF-CHG-20260915-245','CF-245-Gate-L3-fee-benchmark',now()) returning id into v_run;
  update pipeline.layer3_model_profiles set paused=true,
    quality_benchmark=jsonb_build_object('run_id',v_run,'pass',v_pass,'binding_hash',p_binding_hash,'completed_at',now(),'configured_model',p.model_identifier,'returned_models',coalesce(p_returned_models,'{}'::text[]),'external_call_count',greatest(coalesce(p_external_call_count,0),0),'input_tokens',greatest(coalesce(p_input_tokens,0),0),'output_tokens',greatest(coalesce(p_output_tokens,0),0),'estimated_cost_usd',greatest(coalesce(p_estimated_cost_usd,0),0),'max_latency_ms',greatest(coalesce(p_max_latency_ms,0),0),'provider_cases_pass',v_provider_ok,'controls_pass',v_controls_ok,'model_exact',v_model_ok,'cost_pass',v_cost_ok,'summary',left(coalesce(p_summary,''),1000),'change_control_ref','CF-CHG-20260915-245','uat_ref','CF-245-Gate-L3-fee-benchmark'),
    last_validation_result=jsonb_build_object('state',case when v_pass then 'fee_specific_benchmark_passed' else 'fee_specific_benchmark_failed' end,'validated',v_pass,'credential_verified',coalesce(array_length(p_returned_models,1),0)>0,'benchmark_passed',v_pass,'benchmark_run_id',v_run,'completed_at',now(),'message',left(coalesce(p_summary,''),500)),updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',v_pass,'run_id',v_run,'profile_paused',true,'provider_cases_pass',v_provider_ok,'controls_pass',v_controls_ok,'model_exact',v_model_ok,'cost_pass',v_cost_ok);
end $function$;

REVOKE ALL ON FUNCTION public.layer3_cf245_tuition_benchmark_record_service(jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text,text,uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.layer3_cf245_tuition_benchmark_record_service(jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text,text,uuid) TO service_role;
