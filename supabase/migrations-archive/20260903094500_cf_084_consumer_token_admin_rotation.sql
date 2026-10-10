-- CF-CHG-20260903-084: current-environment Website/Zoho token rotation and status.
begin;

create or replace function public.platform_environment_read_service()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline','catalogue','security','vault','storage','cron','private'
as $$
declare v_settings jsonb;v_integrations jsonb;v_manifest jsonb;v_l2 jsonb;v_l3 jsonb;v_runtime jsonb;v_consumers jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;

 select coalesce(jsonb_agg(to_jsonb(x) order by x.category,x.display_name),'[]'::jsonb) into v_settings
 from(select setting_key,category,display_name,setting_value,management_mode,environment_scope,required_for_production,status,description,updated_at from pipeline.environment_settings)x;

 select coalesce(jsonb_agg(jsonb_build_object(
  'integration_key',r.integration_key,'display_name',r.display_name,'configured',v.id is not null,
  'admin_settable',r.admin_settable,'production_rotation_required',r.production_rotation_required,
  'description',r.description,'updated_at',coalesce(v.updated_at,r.updated_at)
 ) order by r.display_name),'[]'::jsonb) into v_integrations
 from pipeline.integration_secret_registry r left join vault.secrets v on v.name=r.secret_name;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'provider_key',p.provider_key,'display_name',p.display_name,'enabled',p.enabled,
  'base_url',p.base_url,'auth_scheme',p.auth_scheme,'auth_field_name',p.auth_field_name,
  'credential_configured',p.vault_secret_id is not null,'priority',p.priority,
  'rate_limit_per_minute',p.rate_limit_per_minute,'concurrency',p.concurrency,'timeout_seconds',p.timeout_seconds,
  'billing_config',p.billing_config,'capabilities',p.capabilities,'request_template',p.request_template,
  'operational_owner',p.operational_owner,'change_control_ref',p.change_control_ref
 ) order by p.priority,p.display_name),'[]'::jsonb) into v_l2
 from pipeline.layer2_acquisition_providers p;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'model_identifier',p.model_identifier,
  'credential_configured',exists(select 1 from vault.secrets vs where vs.name=security.layer3_provider_credential_name(p.id)),
  'enabled',p.enabled,'paused',p.paused
 ) order by p.code),'[]'::jsonb) into v_l3
 from pipeline.layer3_model_profiles p;

 select jsonb_build_array(
  jsonb_build_object(
   'integration_key','zoho_api','display_name','Zoho API bearer token',
   'configured',exists(select 1 from private.zoho_integration_credentials where enabled),
   'credential_name',(select credential_name from private.zoho_integration_credentials where enabled order by rotated_at desc nulls last limit 1),
   'rotated_at',(select rotated_at from private.zoho_integration_credentials where enabled order by rotated_at desc nulls last limit 1),
   'storage_mode','sha256_only','production_rotation_required',true
  ),
  jsonb_build_object(
   'integration_key','website_api','display_name','Website API bearer token',
   'configured',exists(select 1 from private.website_integration_credentials where enabled),
   'credential_name',(select credential_name from private.website_integration_credentials where enabled order by rotated_at desc nulls last limit 1),
   'rotated_at',(select rotated_at from private.website_integration_credentials where enabled order by rotated_at desc nulls last limit 1),
   'storage_mode','sha256_only','production_rotation_required',true
  )
 ) into v_consumers;

 select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]'::jsonb) into v_manifest
 from(select component_key,component_group,display_name,migration_mode,required,source_status,target_status,production_action,validation_rule,source_summary,notes,sort_order,updated_at from pipeline.production_migration_manifest)x;

 v_runtime:=jsonb_build_object(
  'evidence_rows',(select count(*) from pipeline.evidence_artifacts),
  'evidence_relative_storage_paths',(select count(*) from pipeline.evidence_artifacts where storage_path is not null and storage_path not like 'http%'),
  'evidence_absolute_storage_paths',(select count(*) from pipeline.evidence_artifacts where storage_path like 'http%'),
  'provider_asset_rows',(select count(*) from catalogue.provider_assets),
  'provider_asset_absolute_storage_paths',(select count(*) from catalogue.provider_assets where storage_path like 'http%'),
  'storage_objects',(select count(*) from storage.objects),
  'storage_buckets',(select count(*) from storage.buckets),
  'cron_jobs',(select count(*) from cron.job),
  'vault_secret_count',(select count(*) from vault.secrets),
  'pilot_absolute_evidence_urls',(select count(*) from pipeline.evidence_artifacts where source_url like '%fxcwkweaxjtknorudmwp.supabase.co%' or metadata::text like '%fxcwkweaxjtknorudmwp.supabase.co%')
 );

 return jsonb_build_object('settings',v_settings,'integration_secrets',v_integrations,'consumer_credentials',v_consumers,'layer2_providers',v_l2,'layer3_profiles',v_l3,'migration_manifest',v_manifest,'runtime',v_runtime);
end $$;

create or replace function public.platform_environment_control_service(p_actor uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','pipeline','security','vault','private','extensions'
as $$
declare v_rank int:=0;v_key text;v_secret_name text;v_secret_id uuid;v_status text;v_token text;v_hash text;v_name text;
begin
 select coalesce(max(r.rank),0) into v_rank
 from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<6 then raise exception 'platform_admin role required' using errcode='42501';end if;

 if p_action='set_setting' then
  v_key=trim(p_payload->>'setting_key');
  update pipeline.environment_settings
  set setting_value=case when p_payload?'value' then p_payload->'value' else setting_value end,
      status=case when p_payload?'value' and p_payload->'value' is not null and p_payload->'value'<>'null'::jsonb then 'configured' else 'pending' end,
      updated_by=p_actor,updated_at=now()
  where setting_key=v_key and management_mode='admin_edit';
  if not found then raise exception 'setting not admin-editable' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'setting_key',v_key);

 elsif p_action='set_integration_secret' then
  v_key=trim(p_payload->>'integration_key');
  if coalesce(p_payload->>'secret','')='' then raise exception 'secret required' using errcode='22023';end if;
  select secret_name into v_secret_name from pipeline.integration_secret_registry where integration_key=v_key and admin_settable;
  if v_secret_name is null then raise exception 'integration secret not admin-settable' using errcode='22023';end if;
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
  v_name=coalesce(nullif(trim(p_payload->>'credential_name'),''),case v_key when 'zoho_api' then 'zoho-current' when 'website_api' then 'website-current' else null end);
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
  v_key=trim(p_payload->>'component_key');v_status=trim(p_payload->>'target_status');
  if v_status not in('pending','ready','verified','blocked','not_applicable') then raise exception 'invalid target status' using errcode='22023';end if;
  update pipeline.production_migration_manifest set target_status=v_status,updated_by=p_actor,updated_at=now() where component_key=v_key;
  if not found then raise exception 'manifest component not found' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'component_key',v_key,'target_status',v_status);
 end if;
 raise exception 'unsupported environment action' using errcode='22023';
end $$;

update pipeline.production_migration_manifest
set production_action='Rotate/re-enter Website and Zoho bearer tokens in Production via Admin because only SHA-256 hashes are stored; update consumer base URLs only when their separate cutover gate is authorised.',
    validation_rule='New Production token authenticates successfully; Pilot token is not relied upon; consumer cutover contract remains separately accepted.'
where component_key='consumer_integrations';

commit;