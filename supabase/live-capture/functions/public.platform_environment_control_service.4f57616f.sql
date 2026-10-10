CREATE OR REPLACE FUNCTION public.platform_environment_control_service(p_actor uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security', 'vault', 'private', 'extensions'
AS $function$
declare
  v_rank int:=0;
  v_key text;
  v_secret_name text;
  v_secret_id uuid;
  v_status text;
  v_token text;
  v_hash text;
  v_name text;
begin
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;

  if p_action='set_setting' then
    v_key=trim(p_payload->>'setting_key');
    update pipeline.environment_settings
      set setting_value=case when p_payload?'value' then p_payload->'value' else setting_value end,
          status=case when p_payload?'value' and p_payload->'value' is not null and p_payload->'value'<>'null'::jsonb then 'configured' else 'pending' end,
          updated_by=p_actor,updated_at=now()
    where setting_key=v_key and management_mode='admin_edit';
    if not found then raise exception 'setting not admin-editable' using errcode='22023'; end if;
    return jsonb_build_object('ok',true,'setting_key',v_key);

  elsif p_action='set_integration_secret' then
    v_key=trim(p_payload->>'integration_key');
    if coalesce(p_payload->>'secret','')='' then raise exception 'secret required' using errcode='22023'; end if;
    select secret_name into v_secret_name
    from pipeline.integration_secret_registry
    where integration_key=v_key and admin_settable;
    if v_secret_name is null then raise exception 'integration secret not admin-settable' using errcode='22023'; end if;

    select id into v_secret_id from vault.secrets where name=v_secret_name;
    if v_secret_id is null then
      select vault.create_secret(p_payload->>'secret',v_secret_name,'CourseFinder integration credential: '||v_key,null) into v_secret_id;
    else
      perform vault.update_secret(v_secret_id,p_payload->>'secret',null,null,null);
    end if;
    update pipeline.integration_secret_registry set updated_at=now() where integration_key=v_key;
    return jsonb_build_object('ok',true,'integration_key',v_key,'configured',true);

  elsif p_action='set_consumer_token' then
    v_key=trim(p_payload->>'integration_key');
    v_token=trim(p_payload->>'token');
    v_name=coalesce(nullif(trim(p_payload->>'credential_name'),''),case v_key when 'zoho_api' then 'zoho-production' when 'website_api' then 'website-production' else null end);
    if v_key not in('zoho_api','website_api') then raise exception 'unsupported consumer integration' using errcode='22023';end if;
    if length(v_token)<24 then raise exception 'consumer token must be at least 24 characters' using errcode='22023';end if;
    v_hash=encode(extensions.digest(v_token,'sha256'),'hex');

    if v_key='zoho_api' then
      update private.zoho_integration_credentials set enabled=false where enabled;
      insert into private.zoho_integration_credentials(credential_name,token_sha256,enabled,created_at,rotated_at)
      values(v_name,v_hash,true,now(),now())
      on conflict(credential_name) do update set token_sha256=excluded.token_sha256,enabled=true,rotated_at=now();
    else
      update private.website_integration_credentials set enabled=false where enabled;
      insert into private.website_integration_credentials(credential_name,token_sha256,enabled,created_at,rotated_at)
      values(v_name,v_hash,true,now(),now())
      on conflict(credential_name) do update set token_sha256=excluded.token_sha256,enabled=true,rotated_at=now();
    end if;

    return jsonb_build_object('ok',true,'integration_key',v_key,'credential_name',v_name,'configured',true,'storage_mode','sha256_only');

  elsif p_action='set_manifest_status' then
    v_key=trim(p_payload->>'component_key');
    v_status=trim(p_payload->>'target_status');
    if v_status not in('pending','ready','verified','blocked','not_applicable') then raise exception 'invalid target status' using errcode='22023'; end if;
    update pipeline.production_migration_manifest
    set target_status=v_status,updated_by=p_actor,updated_at=now()
    where component_key=v_key;
    if not found then raise exception 'manifest component not found' using errcode='22023'; end if;
    return jsonb_build_object('ok',true,'component_key',v_key,'target_status',v_status);
  end if;

  raise exception 'unsupported environment action' using errcode='22023';
end $function$
