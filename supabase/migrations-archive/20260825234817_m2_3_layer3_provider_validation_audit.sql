create or replace function security.layer3_provider_validation_record_impl(
  p_actor uuid,
  p_profile_id uuid,
  p_ok boolean,
  p_provider_model text,
  p_message text
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
        'message',left(coalesce(p_message,''),500)
      ),
      updated_at=now()
  where id=p_profile_id;
  insert into pipeline.layer3_provider_credential_audit(profile_id,action,actor_id,reason)
  values(p_profile_id,case when p_ok then 'verified' else 'verification_failed' end,p_actor,left(coalesce(nullif(btrim(p_message),''),'provider credential verification'),500));
  return jsonb_build_object('ok',p_ok,'profile_id',p_profile_id,'state',v_state,'provider_model',p_provider_model);
end $$;
revoke all on function security.layer3_provider_validation_record_impl(uuid,uuid,boolean,text,text) from public, anon, authenticated;
grant execute on function security.layer3_provider_validation_record_impl(uuid,uuid,boolean,text,text) to service_role;

create or replace function public.layer3_provider_validation_record_service(
  p_actor uuid,
  p_profile_id uuid,
  p_ok boolean,
  p_provider_model text,
  p_message text
) returns jsonb
language sql
security invoker
set search_path='pg_catalog','security'
as $$ select security.layer3_provider_validation_record_impl(p_actor,p_profile_id,p_ok,p_provider_model,p_message) $$;
revoke all on function public.layer3_provider_validation_record_service(uuid,uuid,boolean,text,text) from public, anon, authenticated;
grant execute on function public.layer3_provider_validation_record_service(uuid,uuid,boolean,text,text) to service_role;
