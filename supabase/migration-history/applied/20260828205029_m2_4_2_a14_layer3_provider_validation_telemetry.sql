alter table pipeline.layer3_provider_credential_audit
  add column if not exists provider_model text,
  add column if not exists external_call_count integer,
  add column if not exists input_tokens integer,
  add column if not exists output_tokens integer,
  add column if not exists estimated_cost_usd numeric(14,6),
  add column if not exists latency_ms integer;

alter table pipeline.layer3_provider_credential_audit
  drop constraint if exists layer3_provider_credential_audit_external_call_count_check,
  add constraint layer3_provider_credential_audit_external_call_count_check check (external_call_count is null or external_call_count >= 0),
  drop constraint if exists layer3_provider_credential_audit_input_tokens_check,
  add constraint layer3_provider_credential_audit_input_tokens_check check (input_tokens is null or input_tokens >= 0),
  drop constraint if exists layer3_provider_credential_audit_output_tokens_check,
  add constraint layer3_provider_credential_audit_output_tokens_check check (output_tokens is null or output_tokens >= 0),
  drop constraint if exists layer3_provider_credential_audit_estimated_cost_usd_check,
  add constraint layer3_provider_credential_audit_estimated_cost_usd_check check (estimated_cost_usd is null or estimated_cost_usd >= 0),
  drop constraint if exists layer3_provider_credential_audit_latency_ms_check,
  add constraint layer3_provider_credential_audit_latency_ms_check check (latency_ms is null or latency_ms >= 0);

create or replace function security.layer3_provider_validation_record_impl(
  p_actor uuid,
  p_profile_id uuid,
  p_ok boolean,
  p_provider_model text,
  p_message text,
  p_external_call_count integer,
  p_input_tokens integer,
  p_output_tokens integer,
  p_estimated_cost_usd numeric,
  p_latency_ms integer
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','security','pipeline'
as $$
declare v_rank smallint := 0; v_state text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0)::smallint into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 6 then raise exception 'platform admin role required' using errcode='42501'; end if;
  if not exists(select 1 from pipeline.layer3_model_profiles where id=p_profile_id) then raise exception 'layer3 model profile not found' using errcode='22023'; end if;
  if p_external_call_count is not null and p_external_call_count < 0 then raise exception 'invalid external call count' using errcode='22023'; end if;
  if p_input_tokens is not null and p_input_tokens < 0 then raise exception 'invalid input tokens' using errcode='22023'; end if;
  if p_output_tokens is not null and p_output_tokens < 0 then raise exception 'invalid output tokens' using errcode='22023'; end if;
  if p_estimated_cost_usd is not null and p_estimated_cost_usd < 0 then raise exception 'invalid estimated cost' using errcode='22023'; end if;
  if p_latency_ms is not null and p_latency_ms < 0 then raise exception 'invalid latency' using errcode='22023'; end if;

  v_state := case when p_ok then 'credential_verified_pending_benchmark' else 'credential_verification_failed' end;
  update pipeline.layer3_model_profiles
  set paused=true,
      last_validation_result=jsonb_build_object(
        'state',v_state,
        'validated',false,
        'credential_configured',true,
        'credential_verified',p_ok,
        'credential_verified_at',now(),
        'provider_model',p_provider_model,
        'message',left(coalesce(p_message,''),500),
        'external_call_count',p_external_call_count,
        'input_tokens',p_input_tokens,
        'output_tokens',p_output_tokens,
        'estimated_cost_usd',p_estimated_cost_usd,
        'latency_ms',p_latency_ms
      ),
      updated_at=now()
  where id=p_profile_id;

  insert into pipeline.layer3_provider_credential_audit(
    profile_id,action,actor_id,reason,provider_model,external_call_count,input_tokens,output_tokens,estimated_cost_usd,latency_ms
  ) values(
    p_profile_id,
    case when p_ok then 'verified' else 'verification_failed' end,
    p_actor,
    left(coalesce(nullif(btrim(p_message),''),'provider credential verification'),500),
    p_provider_model,p_external_call_count,p_input_tokens,p_output_tokens,p_estimated_cost_usd,p_latency_ms
  );

  return jsonb_build_object(
    'ok',p_ok,'profile_id',p_profile_id,'state',v_state,'provider_model',p_provider_model,
    'external_call_count',p_external_call_count,'input_tokens',p_input_tokens,'output_tokens',p_output_tokens,
    'estimated_cost_usd',p_estimated_cost_usd,'latency_ms',p_latency_ms
  );
end $$;

revoke all on function security.layer3_provider_validation_record_impl(uuid,uuid,boolean,text,text,integer,integer,integer,numeric,integer) from public, anon, authenticated;
grant execute on function security.layer3_provider_validation_record_impl(uuid,uuid,boolean,text,text,integer,integer,integer,numeric,integer) to service_role;

create or replace function public.layer3_provider_validation_record_service(
  p_actor uuid,
  p_profile_id uuid,
  p_ok boolean,
  p_provider_model text,
  p_message text,
  p_external_call_count integer,
  p_input_tokens integer,
  p_output_tokens integer,
  p_estimated_cost_usd numeric,
  p_latency_ms integer
) returns jsonb
language sql
security invoker
set search_path='pg_catalog','security'
as $$ select security.layer3_provider_validation_record_impl(
  p_actor,p_profile_id,p_ok,p_provider_model,p_message,p_external_call_count,p_input_tokens,p_output_tokens,p_estimated_cost_usd,p_latency_ms
) $$;

revoke all on function public.layer3_provider_validation_record_service(uuid,uuid,boolean,text,text,integer,integer,integer,numeric,integer) from public, anon, authenticated;
grant execute on function public.layer3_provider_validation_record_service(uuid,uuid,boolean,text,text,integer,integer,integer,numeric,integer) to service_role;
