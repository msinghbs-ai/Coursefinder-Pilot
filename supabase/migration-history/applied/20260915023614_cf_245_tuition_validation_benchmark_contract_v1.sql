begin;

create or replace function public.layer3_cf245_tuition_benchmark_profile_service()
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','pipeline'
as $$
declare p pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-provider-tuition-validation-v1';
  if not found then raise exception 'CF-245 tuition validation profile not found'; end if;
  return jsonb_build_object(
    'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,'model_identifier',p.model_identifier,
    'secret_env_key',p.secret_env_key,'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,
    'structured_output_schema',p.structured_output_schema,'deterministic_validators',p.deterministic_validators,
    'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,'requests_per_minute',p.requests_per_minute,
    'requests_per_day',p.requests_per_day,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,'cost_ceiling_usd',p.cost_ceiling_usd,
    'enabled',p.enabled,'paused',p.paused,'quality_benchmark',p.quality_benchmark,'change_control_ref',p.change_control_ref
  );
end $$;
revoke all on function public.layer3_cf245_tuition_benchmark_profile_service() from public,anon,authenticated;
grant execute on function public.layer3_cf245_tuition_benchmark_profile_service() to service_role;

create or replace function public.layer3_cf245_tuition_benchmark_cases_service(p_limit integer default 4)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_limit integer:=least(greatest(coalesce(p_limit,4),3),6);v_rows jsonb;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_cricos,x.course_cricos),'[]'::jsonb) into v_rows
  from (
    select b.source_record_id,b.source_id,b.evidence_id,b.course_id,b.provider_cricos,b.course_cricos,b.source_url,b.candidate_payload,
           e.storage_path,e.mime_type,e.content_hash,e.captured_at
    from pipeline.cf245_layer3_fee_validation_backlog_v1 b
    join pipeline.evidence_artifacts e on e.id=b.evidence_id
    where e.storage_path is not null and e.content_hash is not null
    order by b.provider_cricos,b.course_cricos
    limit v_limit
  ) x;
  return v_rows;
end $$;
revoke all on function public.layer3_cf245_tuition_benchmark_cases_service(integer) from public,anon,authenticated;
grant execute on function public.layer3_cf245_tuition_benchmark_cases_service(integer) to service_role;

create or replace function public.layer3_cf245_tuition_benchmark_record_service(
  p_provider_cases jsonb,
  p_control_cases jsonb,
  p_returned_models text[],
  p_external_call_count integer,
  p_input_tokens integer,
  p_output_tokens integer,
  p_estimated_cost_usd numeric,
  p_max_latency_ms integer,
  p_evidence_ids uuid[],
  p_summary text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare p pipeline.layer3_model_profiles%rowtype;v_run uuid;v_provider_ok boolean;v_controls_ok boolean;v_model_ok boolean;v_cost_ok boolean;v_pass boolean;v_required_controls text[]:=array['ambiguous_multiple_equal_rank','low_confidence_missing_basis','loan_cap_or_deposit','unsupported_currency'];
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-provider-tuition-validation-v1' for update;
  if not found or not p.enabled then raise exception 'CF-245 tuition validation profile unavailable'; end if;
  select coalesce(jsonb_array_length(coalesce(p_provider_cases,'[]'::jsonb))>=3,false)
     and not exists(select 1 from jsonb_array_elements(coalesce(p_provider_cases,'[]'::jsonb)) c where coalesce((c->>'valid')::boolean,false)=false)
    into v_provider_ok;
  select not exists(select 1 from unnest(v_required_controls) r where not exists(select 1 from jsonb_array_elements(coalesce(p_control_cases,'[]'::jsonb)) c where c->>'case'=r and coalesce((c->>'valid')::boolean,false))) into v_controls_ok;
  v_model_ok:=coalesce(array_length(p_returned_models,1),0)>0 and not exists(select 1 from unnest(coalesce(p_returned_models,'{}'::text[])) m where m<>p.model_identifier);
  v_cost_ok:=greatest(coalesce(p_estimated_cost_usd,0),0)<=greatest(coalesce(p.cost_ceiling_usd,0),0);
  v_pass:=coalesce(v_provider_ok,false) and coalesce(v_controls_ok,false) and coalesce(v_model_ok,false) and coalesce(v_cost_ok,false);
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,estimated_cost_usd,max_latency_ms,evidence_ids,prompt_profile_version,validator_profile,summary,change_control_ref,uat_ref,completed_at)
  values(p.id,'00000000-0000-0000-0000-000000000000'::uuid,case when v_pass then 'pass' else 'fail' end,coalesce(p_provider_cases,'[]'::jsonb),coalesce(p_control_cases,'[]'::jsonb),p.model_identifier,coalesce(p_returned_models,'{}'::text[]),greatest(coalesce(p_external_call_count,0),0),greatest(coalesce(p_input_tokens,0),0),greatest(coalesce(p_output_tokens,0),0),greatest(coalesce(p_estimated_cost_usd,0),0),greatest(coalesce(p_max_latency_ms,0),0),coalesce(p_evidence_ids,'{}'::uuid[]),p.prompt_profile_version,coalesce(p.deterministic_validators,'{}'::jsonb),left(coalesce(p_summary,''),1000),'CF-CHG-20260915-245','CF-245-Gate-L3-fee-benchmark',now()) returning id into v_run;
  update pipeline.layer3_model_profiles set paused=not v_pass,
    quality_benchmark=jsonb_build_object('run_id',v_run,'pass',v_pass,'completed_at',now(),'configured_model',p.model_identifier,'returned_models',coalesce(p_returned_models,'{}'::text[]),'external_call_count',greatest(coalesce(p_external_call_count,0),0),'input_tokens',greatest(coalesce(p_input_tokens,0),0),'output_tokens',greatest(coalesce(p_output_tokens,0),0),'estimated_cost_usd',greatest(coalesce(p_estimated_cost_usd,0),0),'max_latency_ms',greatest(coalesce(p_max_latency_ms,0),0),'provider_cases_pass',v_provider_ok,'controls_pass',v_controls_ok,'model_exact',v_model_ok,'cost_pass',v_cost_ok,'summary',left(coalesce(p_summary,''),1000),'change_control_ref','CF-CHG-20260915-245','uat_ref','CF-245-Gate-L3-fee-benchmark'),
    last_validation_result=jsonb_build_object('state',case when v_pass then 'fee_specific_benchmark_passed' else 'fee_specific_benchmark_failed' end,'validated',v_pass,'credential_verified',coalesce(array_length(p_returned_models,1),0)>0,'benchmark_passed',v_pass,'benchmark_run_id',v_run,'completed_at',now(),'message',left(coalesce(p_summary,''),500)),updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',v_pass,'run_id',v_run,'profile_paused',not v_pass,'provider_cases_pass',v_provider_ok,'controls_pass',v_controls_ok,'model_exact',v_model_ok,'cost_pass',v_cost_ok);
end $$;
revoke all on function public.layer3_cf245_tuition_benchmark_record_service(jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) from public,anon,authenticated;
grant execute on function public.layer3_cf245_tuition_benchmark_record_service(jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) to service_role;

create or replace function public.svc_cf245_run_tuition_benchmark(p_case_limit integer default 4)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','net','public','extensions'
as $$
declare v_nonce uuid:=extensions.gen_random_uuid();v_request_id bigint;v_base text;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,'layer3-cf245-tuition-benchmark',now()+interval '5 minutes');
  v_base:=public.coursefinder_runtime_edge_base_url();if v_base is null then raise exception 'runtime Edge base URL missing';end if;
  select net.http_post(url:=rtrim(v_base,'/')||'/layer3-cf245-tuition-benchmark',headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=jsonb_build_object('case_limit',least(greatest(coalesce(p_case_limit,4),3),6)),timeout_milliseconds:=120000) into v_request_id;
  return jsonb_build_object('request_id',v_request_id,'nonce',v_nonce,'case_limit',least(greatest(coalesce(p_case_limit,4),3),6));
end $$;
revoke all on function public.svc_cf245_run_tuition_benchmark(integer) from public,anon,authenticated;
grant execute on function public.svc_cf245_run_tuition_benchmark(integer) to service_role;

comment on function public.svc_cf245_run_tuition_benchmark(integer) is 'CF-245 Pilot-only one-shot fee-specific Layer 3 benchmark dispatcher. Benchmark cannot mutate canonical fees; PASS only unpauses the dedicated validation profile.';

commit;
