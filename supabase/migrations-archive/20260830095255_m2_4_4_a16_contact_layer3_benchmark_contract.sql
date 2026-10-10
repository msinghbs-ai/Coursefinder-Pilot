
create or replace function public.layer3_contact_benchmark_profile_service()
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','pipeline'
as $$
declare p pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-international-contact-v1';
  if not found then raise exception 'international-contact profile not found'; end if;
  return jsonb_build_object(
    'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,
    'model_identifier',p.model_identifier,'secret_env_key',p.secret_env_key,
    'prompt_profile_version',p.prompt_profile_version,'prompt_system',p.prompt_system,
    'validators',p.deterministic_validators,'max_input_tokens',p.max_input_tokens,
    'max_output_tokens',p.max_output_tokens,'requests_per_minute',p.requests_per_minute,
    'requests_per_day',p.requests_per_day,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,
    'cost_ceiling_usd',p.cost_ceiling_usd,'enabled',p.enabled,'paused',p.paused
  );
end $$;
revoke all on function public.layer3_contact_benchmark_profile_service() from public,anon,authenticated;
grant execute on function public.layer3_contact_benchmark_profile_service() to service_role;

create or replace function public.layer3_contact_benchmark_evidence_service(p_evidence_ids uuid[])
returns jsonb language sql stable security definer
set search_path='pg_catalog','pipeline'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'storage_path',e.storage_path,'mime_type',e.mime_type,'source_url',e.source_url,
    'content_hash',e.content_hash,'metadata',e.metadata
  ) order by e.id),'[]'::jsonb)
  from pipeline.evidence_artifacts e
  where e.id=any(p_evidence_ids)
    and coalesce(e.metadata->>'operation','')='provider_contact_discovery'
    and e.storage_path is not null
    and e.content_hash is not null
$$;
revoke all on function public.layer3_contact_benchmark_evidence_service(uuid[]) from public,anon,authenticated;
grant execute on function public.layer3_contact_benchmark_evidence_service(uuid[]) to service_role;

create or replace function public.layer3_contact_benchmark_record_service(
  p_pass boolean,p_provider_cases jsonb,p_control_cases jsonb,p_returned_models text[],
  p_external_call_count integer,p_input_tokens integer,p_output_tokens integer,
  p_estimated_cost_usd numeric,p_max_latency_ms integer,p_evidence_ids uuid[],p_summary text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','pipeline'
as $$
declare p pipeline.layer3_model_profiles%rowtype; v_run uuid; v_state text;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into p from pipeline.layer3_model_profiles where code='openrouter-international-contact-v1' for update;
  if not found then raise exception 'international-contact profile not found'; end if;
  v_state:=case when p_pass then 'contact_benchmark_passed' else 'contact_benchmark_failed' end;
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
    'CF-CHG-20260830-048','M2.4.4-A16-contact-qualification',now()
  ) returning id into v_run;
  update pipeline.layer3_model_profiles
  set enabled=p_pass,paused=not p_pass,
      quality_benchmark=jsonb_build_object(
        'run_id',v_run,'pass',p_pass,'completed_at',now(),'configured_model',p.model_identifier,
        'returned_models',coalesce(p_returned_models,'{}'::text[]),
        'external_call_count',coalesce(p_external_call_count,0),
        'input_tokens',coalesce(p_input_tokens,0),'output_tokens',coalesce(p_output_tokens,0),
        'estimated_cost_usd',coalesce(p_estimated_cost_usd,0),'max_latency_ms',coalesce(p_max_latency_ms,0),
        'summary',left(coalesce(p_summary,''),1000),'change_control_ref','CF-CHG-20260830-048',
        'uat_ref','M2.4.4-A16-contact-qualification'
      ),
      last_validation_result=jsonb_build_object(
        'state',v_state,'validated',p_pass,'benchmark_passed',p_pass,'benchmark_run_id',v_run,
        'completed_at',now(),'task_class','international_contact','credential_source','server_runtime',
        'message',left(coalesce(p_summary,''),500),'change_control_ref','CF-CHG-20260830-048',
        'uat_ref','M2.4.4-A16-contact-qualification'
      ),
      change_control_ref='CF-CHG-20260830-048',uat_ref='M2.4.4-A16-contact-qualification',updated_at=now()
  where id=p.id;
  return jsonb_build_object('ok',true,'pass',p_pass,'run_id',v_run,'state',v_state,'profile_id',p.id,'profile_enabled',p_pass,'profile_paused',not p_pass);
end $$;
revoke all on function public.layer3_contact_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) from public,anon,authenticated;
grant execute on function public.layer3_contact_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) to service_role;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer
set search_path='pipeline','net','public','extensions'
as $$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in (
    'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness',
    'coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled',
    'layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled','layer3-source-pattern-benchmark',
    'layer3-contact-benchmark','layer2-screenshot-backfill-scheduled',
    'provider-contact-discover-scheduled','provider-contact-enrich-apollo'
  ) then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at)
  values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end $$;

comment on function public.layer3_contact_benchmark_record_service(boolean,jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text) is
'A16 contact-specific quality gate. Profile becomes executable only when real first-party Evidence cases, anti-hallucination controls, exact-model and cost checks all pass.';
