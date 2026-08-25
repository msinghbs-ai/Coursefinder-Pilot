create table if not exists pipeline.layer3_provider_credential_audit (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer3_model_profiles(id) on delete cascade,
  action text not null check (action in ('set','replace','verified','verification_failed','cleared')),
  actor_id uuid not null,
  reason text not null,
  created_at timestamptz not null default now()
);
alter table pipeline.layer3_provider_credential_audit enable row level security;
revoke all on pipeline.layer3_provider_credential_audit from public, anon, authenticated;
create index if not exists layer3_provider_credential_audit_profile_created_idx on pipeline.layer3_provider_credential_audit(profile_id, created_at desc);

create or replace function security.layer3_provider_credential_name(p_profile_id uuid)
returns text
language sql
immutable
set search_path='pg_catalog'
as $$ select 'coursefinder_layer3_profile_' || p_profile_id::text $$;
revoke all on function security.layer3_provider_credential_name(uuid) from public, anon, authenticated;
grant execute on function security.layer3_provider_credential_name(uuid) to service_role;

create or replace function security.layer3_provider_credential_set_impl(
  p_actor uuid,
  p_profile_id uuid,
  p_secret text,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','security','pipeline','vault'
as $$
declare
  v_rank smallint := 0;
  v_profile pipeline.layer3_model_profiles%rowtype;
  v_name text;
  v_secret_id uuid;
  v_action text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0)::smallint into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 6 then raise exception 'platform admin role required' using errcode='42501'; end if;
  if p_secret is null or length(btrim(p_secret)) < 20 then raise exception 'provider credential is required' using errcode='22023'; end if;
  if p_reason is null or length(btrim(p_reason)) < 4 then raise exception 'reason is required' using errcode='22023'; end if;
  select * into v_profile from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'layer3 model profile not found' using errcode='22023'; end if;
  v_name := security.layer3_provider_credential_name(p_profile_id);
  select id into v_secret_id from vault.secrets where name=v_name limit 1;
  if v_secret_id is null then
    v_secret_id := vault.create_secret(btrim(p_secret), v_name, 'CourseFinder Layer 3 provider credential for ' || v_profile.code);
    v_action := 'set';
  else
    perform vault.update_secret(v_secret_id, btrim(p_secret), v_name, 'CourseFinder Layer 3 provider credential for ' || v_profile.code);
    v_action := 'replace';
  end if;
  update pipeline.layer3_model_profiles
  set paused=true,
      last_validation_result=jsonb_build_object(
        'state','credential_configured_pending_benchmark',
        'validated',false,
        'credential_configured',true,
        'credential_configured_at',now(),
        'provider',aggregator_provider
      ),
      updated_at=now()
  where id=p_profile_id;
  insert into pipeline.layer3_provider_credential_audit(profile_id,action,actor_id,reason)
  values(p_profile_id,v_action,p_actor,btrim(p_reason));
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'credential_configured',true,'state','credential_configured_pending_benchmark');
end $$;
revoke all on function security.layer3_provider_credential_set_impl(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function security.layer3_provider_credential_set_impl(uuid,uuid,text,text) to service_role;

create or replace function security.layer3_provider_credential_resolve_impl(p_profile_id uuid)
returns text
language plpgsql
stable
security definer
set search_path='pg_catalog','security','vault'
as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name=security.layer3_provider_credential_name(p_profile_id)
  limit 1;
  return v_secret;
end $$;
revoke all on function security.layer3_provider_credential_resolve_impl(uuid) from public, anon, authenticated;
grant execute on function security.layer3_provider_credential_resolve_impl(uuid) to service_role;

create or replace function public.layer3_provider_credential_set_service(
  p_actor uuid,
  p_profile_id uuid,
  p_secret text,
  p_reason text
) returns jsonb
language sql
security invoker
set search_path='pg_catalog','security'
as $$ select security.layer3_provider_credential_set_impl(p_actor,p_profile_id,p_secret,p_reason) $$;
revoke all on function public.layer3_provider_credential_set_service(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.layer3_provider_credential_set_service(uuid,uuid,text,text) to service_role;

create or replace function public.layer3_provider_credential_resolve_service(p_profile_id uuid)
returns text
language sql
stable
security invoker
set search_path='pg_catalog','security'
as $$ select security.layer3_provider_credential_resolve_impl(p_profile_id) $$;
revoke all on function public.layer3_provider_credential_resolve_service(uuid) from public, anon, authenticated;
grant execute on function public.layer3_provider_credential_resolve_service(uuid) to service_role;

create or replace function security.layer3_model_profiles_admin_impl()
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','auth','vault'
as $$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'base_url',p.base_url,'model_identifier',p.model_identifier,
    'allowed_task_classes',p.allowed_task_classes,'prompt_profile_version',p.prompt_profile_version,'structured_output_schema',p.structured_output_schema,
    'deterministic_validators',p.deterministic_validators,'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,
    'requests_per_minute',p.requests_per_minute,'requests_per_day',p.requests_per_day,'retry_ceiling',p.retry_ceiling,'timeout_ms',p.timeout_ms,
    'fallback_profile_id',p.fallback_profile_id,'cost_ceiling_usd',p.cost_ceiling_usd,'enabled',p.enabled,'paused',p.paused,
    'credential_configured',exists(select 1 from vault.secrets s where s.name=security.layer3_provider_credential_name(p.id)),
    'credential_updated_at',(select s.updated_at from vault.secrets s where s.name=security.layer3_provider_credential_name(p.id) limit 1),
    'last_validation_result',p.last_validation_result,'quality_benchmark',p.quality_benchmark,'change_control_ref',p.change_control_ref,'uat_ref',p.uat_ref,
    'updated_at',p.updated_at
  ) order by p.code) from pipeline.layer3_model_profiles p),'[]'::jsonb);
end $$;

revoke all on function security.layer3_model_profiles_admin_impl() from public, anon, authenticated;
grant execute on function security.layer3_model_profiles_admin_impl() to authenticated, service_role;
