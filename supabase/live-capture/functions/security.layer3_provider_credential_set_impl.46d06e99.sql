CREATE OR REPLACE FUNCTION security.layer3_provider_credential_set_impl(p_actor uuid, p_profile_id uuid, p_secret text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'vault'
AS $function$
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
end $function$
