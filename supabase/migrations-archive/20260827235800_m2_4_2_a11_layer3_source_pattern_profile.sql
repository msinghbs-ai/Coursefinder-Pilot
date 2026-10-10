-- M2.4.2 A11 — dedicated Layer 3 source-pattern profile and benchmark contract.
-- The profile is paused by default. Credential setup is a governed runtime operation and is not embedded here.
-- No canonical, Search or Publication mutation is authorised.

begin;

insert into pipeline.layer3_model_profiles(
  code,aggregator_provider,base_url,model_identifier,secret_env_key,
  allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,
  max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,
  retry_ceiling,timeout_ms,fallback_profile_id,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,
  change_control_ref,uat_ref
)
select
  'openrouter-source-pattern-v1',
  p.aggregator_provider,p.base_url,p.model_identifier,p.secret_env_key,
  array['source_pattern']::text[],
  'm2.4.2-source-pattern-v1',
  'Interpret only retained first-party Layer 2 Evidence links. Return JSON only. Select a Course/programme catalogue or discovery URL only when it is present in supplied Evidence links and on the exact governed first-party host. Never infer or redefine regulatory identity. Never return a Course identity, fee, intake, admission fact, Search instruction or Publication instruction. If no reliable Course discovery entrypoint is supported, set candidate_value to null.',
  '{"type":"object","required":["candidate_value","confidence","rationale","evidence_quotes"],"candidate_value":{"oneOf":[{"type":"null"},{"type":"string","pattern":"^https://"}]}}'::jsonb,
  '{"confidence_min":0,"confidence_max":1,"max_rationale_chars":1600,"max_quotes":4,"max_quote_chars":600,"candidate_required":false,"candidate_url_must_be_same_host":true,"candidate_url_must_be_evidence_link":true,"https_required":true,"candidate_shape":"https_url_string_or_null"}'::jsonb,
  8000,800,10,30,1,30000,null,0,
  true,true,
  jsonb_build_object(
    'state','pending_source_pattern_benchmark',
    'validated',false,
    'task_class','source_pattern',
    'credential_source','server_runtime',
    'change_control_ref','CF-CHG-20260827-044'
  ),
  null,'CF-CHG-20260827-044','M2.4.2-A11-source-pattern-benchmark'
from pipeline.layer3_model_profiles p
where p.code='openrouter-free-router-v1'
on conflict(code) do nothing;

create or replace function public.layer3_source_pattern_benchmark_profile_service()
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','pipeline'
as $$
declare p pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-source-pattern-v1';
  if not found then raise exception 'source-pattern profile not found'; end if;
  return jsonb_build_object(
    'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,
    'base_url',p.base_url,'model_identifier',p.model_identifier,'secret_env_key',p.secret_env_key,
    'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,
    'validators',p.deterministic_validators,'max_input_tokens',p.max_input_tokens,
    'max_output_tokens',p.max_output_tokens,'requests_per_minute',p.requests_per_minute,
    'requests_per_day',p.requests_per_day,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,
    'cost_ceiling_usd',p.cost_ceiling_usd,'enabled',p.enabled,'paused',p.paused
  );
end $$;

create or replace function public.layer3_source_pattern_benchmark_evidence_service(p_evidence_ids uuid[])
returns jsonb language sql stable security definer
set search_path='pg_catalog','pipeline'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'storage_path',e.storage_path,'mime_type',e.mime_type,
    'source_url',e.source_url,'content_hash',e.content_hash
  ) order by e.id),'[]'::jsonb)
  from pipeline.evidence_artifacts e
  where e.id=any(p_evidence_ids)
$$;

create or replace function public.layer3_source_pattern_benchmark_record_service(
  p_pass boolean,p_provider_cases jsonb,p_control_cases jsonb,p_returned_models text[],
  p_external_call_count integer,p_input_tokens integer,p_output_tokens integer,
  p_estimated_cost_usd numeric,p_max_latency_ms integer,p_evidence_ids uuid[],p_summary text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
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
    'CF-CHG-20260827-044','M2.4.2-A11-source-pattern-benchmark',now()
  ) returning id into v_run;
  update pipeline.layer3_model_profiles
  set paused=not p_pass,
      quality_benchmark=jsonb_build_object(
        'run_id',v_run,'pass',p_pass,'completed_at',now(),'configured_model',p.model_identifier,
        'returned_models',coalesce(p_returned_models,'{}'::text[]),'external_call_count',coalesce(p_external_call_count,0),
        'input_tokens',coalesce(p_input_tokens,0),'output_tokens',coalesce(p_output_tokens,0),
        'estimated_cost_usd',coalesce(p_estimated_cost_usd,0),'max_latency_ms',coalesce(p_max_latency_ms,0),
        'summary',left(coalesce(p_summary,''),1000),'change_control_ref','CF-CHG-20260827-044',
        'uat_ref','M2.4.2-A11-source-pattern-benchmark'
      ),
      last_validation_result=jsonb_build_object(
        'state',v_state,'validated',p_pass,'benchmark_passed',p_pass,'benchmark_run_id',v_run,
        'completed_at',now(),'task_class','source_pattern','credential_source','server_runtime',
        'message',left(coalesce(p_summary,''),500)
      ),updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',p_pass,'run_id',v_run,'state',v_state,'profile_id',p.id,'profile_paused',not p_pass);
end $$;

revoke all on function public.layer3_source_pattern_benchmark_profile_service() from public,anon,authenticated;
revoke all on function public.layer3_source_pattern_benchmark_evidence_service(uuid[]) from public,anon,authenticated;
revoke all on function public.layer3_source_pattern_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) from public,anon,authenticated;
grant execute on function public.layer3_source_pattern_benchmark_profile_service() to service_role;
grant execute on function public.layer3_source_pattern_benchmark_evidence_service(uuid[]) to service_role;
grant execute on function public.layer3_source_pattern_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) to service_role;

do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='pipeline' and p.proname='svc_pilot_submit_nonce' limit 1;
  if v_oid is null then raise exception 'svc_pilot_submit_nonce not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('layer3-source-pattern-benchmark' in v_def)=0 then
    v_def:=replace(v_def,'''layer2-scale-qualify-scheduled''','''layer2-scale-qualify-scheduled'',''layer3-source-pattern-benchmark''');
    execute v_def;
  end if;
end $$;

commit;
