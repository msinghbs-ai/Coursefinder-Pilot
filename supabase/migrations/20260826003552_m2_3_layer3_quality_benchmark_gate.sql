create table if not exists pipeline.layer3_quality_benchmark_runs (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer3_model_profiles(id) on delete cascade,
  actor_id uuid not null,
  status text not null check (status in ('running','pass','fail','error')),
  provider_case_results jsonb not null default '[]'::jsonb,
  control_case_results jsonb not null default '[]'::jsonb,
  configured_model text,
  returned_models text[] not null default '{}'::text[],
  external_call_count integer not null default 0 check (external_call_count>=0),
  input_tokens integer not null default 0 check (input_tokens>=0),
  output_tokens integer not null default 0 check (output_tokens>=0),
  estimated_cost_usd numeric(12,6) not null default 0 check (estimated_cost_usd>=0),
  max_latency_ms integer not null default 0 check (max_latency_ms>=0),
  evidence_ids uuid[] not null default '{}'::uuid[],
  prompt_profile_version text,
  validator_profile jsonb not null default '{}'::jsonb,
  summary text,
  change_control_ref text not null default 'CF-CHG-20260825-038',
  uat_ref text not null default 'M2.3-Go5-real-provider-benchmark',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table pipeline.layer3_quality_benchmark_runs enable row level security;
revoke all on pipeline.layer3_quality_benchmark_runs from public, anon, authenticated;
create index if not exists layer3_quality_benchmark_profile_created_idx on pipeline.layer3_quality_benchmark_runs(profile_id,created_at desc);

create table if not exists pipeline.layer3_benchmark_jobs (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer3_model_profiles(id) on delete cascade,
  actor_id uuid not null,
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending','claimed','completed','failed','expired')),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table pipeline.layer3_benchmark_jobs enable row level security;
revoke all on pipeline.layer3_benchmark_jobs from public, anon, authenticated;
create index if not exists layer3_benchmark_jobs_status_expiry_idx on pipeline.layer3_benchmark_jobs(status,expires_at);

create or replace function security.layer3_benchmark_claim_impl(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_job pipeline.layer3_benchmark_jobs%rowtype;
begin
  update pipeline.layer3_benchmark_jobs set status='expired' where status='pending' and expires_at<=now();
  select * into v_job from pipeline.layer3_benchmark_jobs where token_hash=p_token_hash and status='pending' and expires_at>now() for update skip locked;
  if not found then raise exception 'benchmark job not available' using errcode='42501'; end if;
  update pipeline.layer3_benchmark_jobs set status='claimed',claimed_at=now() where id=v_job.id;
  return jsonb_build_object('job_id',v_job.id,'profile_id',v_job.profile_id,'actor_id',v_job.actor_id);
end $$;
revoke all on function security.layer3_benchmark_claim_impl(text) from public,anon,authenticated;
grant execute on function security.layer3_benchmark_claim_impl(text) to service_role;

create or replace function public.layer3_benchmark_claim_service(p_token_hash text)
returns jsonb language sql security invoker set search_path='pg_catalog','security'
as $$ select security.layer3_benchmark_claim_impl(p_token_hash) $$;
revoke all on function public.layer3_benchmark_claim_service(text) from public,anon,authenticated;
grant execute on function public.layer3_benchmark_claim_service(text) to service_role;

create or replace function security.layer3_benchmark_profile_impl(p_profile_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','pipeline','security'
as $$
declare p pipeline.layer3_model_profiles%rowtype;
begin
  select * into p from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'profile not found'; end if;
  return jsonb_build_object(
    'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,'model_identifier',p.model_identifier,
    'allowed_task_classes',p.allowed_task_classes,'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,
    'structured_output_schema',p.structured_output_schema,'deterministic_validators',p.deterministic_validators,
    'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,'requests_per_minute',p.requests_per_minute,
    'requests_per_day',p.requests_per_day,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,'cost_ceiling_usd',p.cost_ceiling_usd,
    'fallback_profile_id',p.fallback_profile_id,'enabled',p.enabled,'paused',p.paused,'last_validation_result',p.last_validation_result
  );
end $$;
revoke all on function security.layer3_benchmark_profile_impl(uuid) from public,anon,authenticated;
grant execute on function security.layer3_benchmark_profile_impl(uuid) to service_role;

create or replace function public.layer3_benchmark_profile_service(p_profile_id uuid)
returns jsonb language sql stable security invoker set search_path='pg_catalog','security'
as $$ select security.layer3_benchmark_profile_impl(p_profile_id) $$;
revoke all on function public.layer3_benchmark_profile_service(uuid) from public,anon,authenticated;
grant execute on function public.layer3_benchmark_profile_service(uuid) to service_role;

create or replace function security.layer3_benchmark_record_impl(
  p_job_id uuid,
  p_profile_id uuid,
  p_actor uuid,
  p_pass boolean,
  p_provider_cases jsonb,
  p_control_cases jsonb,
  p_configured_model text,
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
set search_path='pg_catalog','pipeline','security'
as $$
declare v_rank int:=0; v_run_id uuid; v_profile pipeline.layer3_model_profiles%rowtype; v_state text;
begin
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and r.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<6 then raise exception 'platform admin role required' using errcode='42501'; end if;
  select * into v_profile from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'profile not found'; end if;
  if coalesce(v_profile.last_validation_result->>'state','')<>'credential_verified_pending_benchmark' then raise exception 'credential verification required before benchmark'; end if;
  v_state:=case when p_pass then 'benchmark_passed' else 'benchmark_failed' end;
  insert into pipeline.layer3_quality_benchmark_runs(profile_id,actor_id,status,provider_case_results,control_case_results,configured_model,returned_models,external_call_count,input_tokens,output_tokens,estimated_cost_usd,max_latency_ms,evidence_ids,prompt_profile_version,validator_profile,summary,completed_at)
  values(p_profile_id,p_actor,case when p_pass then 'pass' else 'fail' end,coalesce(p_provider_cases,'[]'::jsonb),coalesce(p_control_cases,'[]'::jsonb),p_configured_model,coalesce(p_returned_models,'{}'::text[]),greatest(coalesce(p_external_call_count,0),0),greatest(coalesce(p_input_tokens,0),0),greatest(coalesce(p_output_tokens,0),0),greatest(coalesce(p_estimated_cost_usd,0),0),greatest(coalesce(p_max_latency_ms,0),0),coalesce(p_evidence_ids,'{}'::uuid[]),v_profile.prompt_profile_version,coalesce(v_profile.deterministic_validators,'{}'::jsonb),left(coalesce(p_summary,''),1000),now()) returning id into v_run_id;
  update pipeline.layer3_model_profiles set
    paused=not p_pass,
    quality_benchmark=jsonb_build_object('run_id',v_run_id,'pass',p_pass,'completed_at',now(),'configured_model',p_configured_model,'returned_models',coalesce(p_returned_models,'{}'::text[]),'external_call_count',p_external_call_count,'input_tokens',p_input_tokens,'output_tokens',p_output_tokens,'estimated_cost_usd',p_estimated_cost_usd,'max_latency_ms',p_max_latency_ms,'summary',left(coalesce(p_summary,''),1000),'change_control_ref','CF-CHG-20260825-038','uat_ref','M2.3-Go5-real-provider-benchmark'),
    last_validation_result=jsonb_build_object('state',v_state,'validated',p_pass,'credential_configured',true,'credential_verified',true,'benchmark_passed',p_pass,'benchmark_run_id',v_run_id,'completed_at',now(),'message',left(coalesce(p_summary,''),500)),
    updated_at=now()
  where id=p_profile_id;
  update pipeline.layer3_benchmark_jobs set status=case when p_pass then 'completed' else 'failed' end,completed_at=now() where id=p_job_id and profile_id=p_profile_id and actor_id=p_actor;
  return jsonb_build_object('ok',true,'pass',p_pass,'run_id',v_run_id,'state',v_state,'profile_paused',not p_pass);
end $$;
revoke all on function security.layer3_benchmark_record_impl(uuid,uuid,uuid,boolean,jsonb,jsonb,text,text[],integer,integer,integer,numeric,integer,uuid[],text) from public,anon,authenticated;
grant execute on function security.layer3_benchmark_record_impl(uuid,uuid,uuid,boolean,jsonb,jsonb,text,text[],integer,integer,integer,numeric,integer,uuid[],text) to service_role;

create or replace function public.layer3_benchmark_record_service(
  p_job_id uuid,p_profile_id uuid,p_actor uuid,p_pass boolean,p_provider_cases jsonb,p_control_cases jsonb,p_configured_model text,p_returned_models text[],p_external_call_count integer,p_input_tokens integer,p_output_tokens integer,p_estimated_cost_usd numeric,p_max_latency_ms integer,p_evidence_ids uuid[],p_summary text
) returns jsonb language sql security invoker set search_path='pg_catalog','security'
as $$ select security.layer3_benchmark_record_impl(p_job_id,p_profile_id,p_actor,p_pass,p_provider_cases,p_control_cases,p_configured_model,p_returned_models,p_external_call_count,p_input_tokens,p_output_tokens,p_estimated_cost_usd,p_max_latency_ms,p_evidence_ids,p_summary) $$;
revoke all on function public.layer3_benchmark_record_service(uuid,uuid,uuid,boolean,jsonb,jsonb,text,text[],integer,integer,integer,numeric,integer,uuid[],text) from public,anon,authenticated;
grant execute on function public.layer3_benchmark_record_service(uuid,uuid,uuid,boolean,jsonb,jsonb,text,text[],integer,integer,integer,numeric,integer,uuid[],text) to service_role;
