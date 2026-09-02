-- CF-CHG-20260903-084
-- Admin Environment & Migration controls.
-- Production portability registry, write-only integration secrets and migration manifest.

begin;

create table if not exists pipeline.environment_settings(
  setting_key text primary key,
  category text not null,
  display_name text not null,
  setting_value jsonb,
  management_mode text not null check(management_mode in('read_only','admin_edit','deployment_managed','project_generated')),
  environment_scope text not null default 'per_environment',
  required_for_production boolean not null default true,
  status text not null default 'pending' check(status in('pending','configured','verified','not_applicable','blocked')),
  description text,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists pipeline.integration_secret_registry(
  integration_key text primary key,
  display_name text not null,
  secret_name text not null unique,
  admin_settable boolean not null default true,
  production_rotation_required boolean not null default true,
  description text,
  updated_at timestamptz not null default now()
);

create table if not exists pipeline.production_migration_manifest(
  component_key text primary key,
  component_group text not null,
  display_name text not null,
  migration_mode text not null,
  required boolean not null default true,
  source_status text not null default 'ready',
  target_status text not null default 'pending' check(target_status in('pending','ready','verified','blocked','not_applicable')),
  production_action text not null,
  validation_rule text,
  source_summary jsonb not null default '{}'::jsonb,
  notes text,
  sort_order integer not null default 100,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

alter table pipeline.environment_settings enable row level security;
alter table pipeline.integration_secret_registry enable row level security;
alter table pipeline.production_migration_manifest enable row level security;
revoke all on pipeline.environment_settings,pipeline.integration_secret_registry,pipeline.production_migration_manifest from public,anon,authenticated;

insert into pipeline.environment_settings(setting_key,category,display_name,setting_value,management_mode,environment_scope,required_for_production,status,description)
values
 ('current_environment','environment','Current environment','"pilot"'::jsonb,'read_only','current',false,'verified','Current runtime role.'),
 ('current_supabase_project_ref','supabase','Current Supabase project ref','"fxcwkweaxjtknorudmwp"'::jsonb,'read_only','current',false,'verified','Pilot source project.'),
 ('production_supabase_organization','supabase','Production Supabase organisation',null,'admin_edit','production',true,'pending','Target organisation/tenancy for clean Production.'),
 ('production_supabase_project_ref','supabase','Production Supabase project ref',null,'admin_edit','production',true,'pending','Target Production project ref after creation.'),
 ('production_supabase_project_url','supabase','Production Supabase URL',null,'admin_edit','production',true,'pending','Target https://<project-ref>.supabase.co URL.'),
 ('production_region','supabase','Production region',null,'admin_edit','production',true,'pending','Target Supabase region.'),
 ('production_admin_origin','deployment','Production Admin origin',null,'admin_edit','production',true,'pending','Cloudflare/Admin application origin used for CORS and links.'),
 ('production_website_origin','deployment','Production Website origin',null,'admin_edit','production',false,'pending','Wix/Website consumer origin when production consumer is admitted.'),
 ('frontend_supabase_url','deployment','Frontend VITE_SUPABASE_URL',null,'deployment_managed','production',true,'pending','Must point the production frontend at the target project.'),
 ('frontend_publishable_key','deployment','Frontend VITE_SUPABASE_PUBLISHABLE_KEY',null,'project_generated','production',true,'pending','Target-generated publishable key; never copy Pilot key.'),
 ('edge_secret_key','deployment','Edge SUPABASE secret key',null,'project_generated','production',true,'pending','Target-generated secret key is supplied by Supabase Edge environment; never expose in browser.'),
 ('auth_redirect_urls','auth','Auth redirect/site URLs',null,'deployment_managed','production',true,'pending','Reconfigure Auth site URL and redirects for Production origins.'),
 ('realtime_settings','supabase','Realtime settings',null,'deployment_managed','production',false,'pending','Reconfigure if enabled in Production.'),
 ('production_automation_key','automation','Production automation key',null,'deployment_managed','production',true,'pending','Create a new Production-specific automation secret; do not carry the Pilot automation key.')
on conflict(setting_key) do nothing;

insert into pipeline.integration_secret_registry(integration_key,display_name,secret_name,admin_settable,production_rotation_required,description)
values
 ('apollo','Apollo contact enrichment','coursefinder_integration_apollo',true,true,'Licensed Provider-contact enrichment credential.'),
 ('production_automation','Production automation key','coursefinder_production_automation_key',true,true,'Production-only server automation credential; distinct from Pilot.')
on conflict(integration_key) do nothing;

insert into pipeline.production_migration_manifest(component_key,component_group,display_name,migration_mode,required,source_status,target_status,production_action,validation_rule,source_summary,notes,sort_order)
values
 ('database_schema_data','Database','Database schema, data, indexes, roles and Auth user data','clone_or_restore',true,'ready','pending','Restore/clone into clean Production project, then replay/verify repository migrations.','Schema migration history matches repository and canonical row-count checks pass.','{}','Database-only clone does not complete the whole project.',10),
 ('vault_secrets','Secrets','Vault secrets and provider credentials','rotate_or_rekey',true,'ready','pending','Prefer Production re-entry/rotation through Admin. If physical clone is used, validate Vault root-key portability before relying on copied ciphertext.','Every required secret shows configured in Production and bounded connectivity UAT passes.','{}','Secret values are never exposed by Admin reads.',20),
 ('storage_buckets','Storage','Storage bucket configuration','migration_plus_verify',true,'ready','pending','Create identical private buckets/policies in Production from migrations/config.','Bucket names, privacy, limits and MIME policies match Pilot authority.','{}','Keep evidence and provider-assets bucket names stable.',30),
 ('storage_objects','Storage','Storage objects / Evidence files','copy_preserve_paths',true,'ready','pending','Copy every object preserving bucket name and exact object path.','Source/target object counts and sampled SHA-256 Evidence checks reconcile.','{}','Database storage_path references are relative and must remain unchanged.',40),
 ('edge_functions','Functions','Edge Functions','deploy_from_repo',true,'ready','pending','Deploy all governed Edge Functions from the accepted repository revision.','Function inventory/version and targeted UAT match accepted Pilot contracts.','{}','Do not rely on database clone for Edge Functions.',50),
 ('edge_function_secrets','Functions','Edge Function custom secrets','reconfigure',true,'ready','pending','Configure Production-only custom secrets and integration credentials; project-generated Supabase keys remain target-native.','Functions report configured status without exposing values.','{}','Includes Apollo and any non-Vault custom function secret still in use.',60),
 ('auth_settings_keys','Auth','Auth settings and API keys','target_generated_reconfigure',true,'ready','pending','Configure Production Auth settings; use target publishable/secret keys and update clients/deployments.','Production login/session/role UAT passes and no Pilot key remains in deployments.','{}','Use publishable/secret key model for new Production configuration.',70),
 ('cron_jobs','Scheduling','pg_cron schedules','migration_then_enable',true,'ready','pending','Recreate schedules from migrations only after target secrets, functions and source settings are ready.','Job names/schedules reconcile and no job targets Pilot URLs/secrets.','{}','Keep jobs disabled during restore validation where required.',80),
 ('extensions_settings','Database','Database extensions and project settings','verify_reconfigure',true,'ready','pending','Verify required extensions/settings in the target project.','Required extensions and settings reconcile with Pilot.','{}','Project clone may still require manual platform settings review.',90),
 ('cors_origins','Deployment','CORS/origin links','reconfigure',true,'ready','pending','Replace Pilot Admin/consumer origins with Production origins in deployment-managed configuration.','No Production request depends on coursefinder-pilot.techm.workers.dev.','{}','Admin tracks target origins even where deployment tooling owns the actual environment value.',100),
 ('evidence_links','Evidence','Evidence/source link portability','verify_relative_paths',true,'ready','pending','Preserve source_url; copy Storage objects at the same relative storage_path; regenerate signed URLs from Production.','No evidence row contains a Pilot Supabase absolute Storage URL and sampled Evidence opens in Production.','{}','Pilot Evidence and Provider assets use relative Storage paths.',110),
 ('consumer_integrations','Integrations','Website/Zoho/API consumer configuration','reconfigure_later_gate',false,'ready','pending','Update consumer base URLs/keys only when the separate Website/Zoho production gate is authorised.','Consumer contract UAT passes against Production endpoint.','{}','Does not authorise consumer cutover.',120)
on conflict(component_key) do nothing;

create or replace function public.integration_secret_resolve_service(p_integration_key text)
returns text language plpgsql security definer
set search_path='pg_catalog','public','pipeline','vault'
as $$
declare v_name text;v_value text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 select secret_name into v_name from pipeline.integration_secret_registry where integration_key=p_integration_key;
 if v_name is null then return null;end if;
 select decrypted_secret into v_value from vault.decrypted_secrets where name=v_name limit 1;
 return v_value;
end $$;
revoke all on function public.integration_secret_resolve_service(text) from public,anon,authenticated;
grant execute on function public.integration_secret_resolve_service(text) to service_role;

create or replace function public.platform_environment_read_service()
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue','security','vault','storage','cron'
as $$
declare v_settings jsonb;v_integrations jsonb;v_manifest jsonb;v_l2 jsonb;v_l3 jsonb;v_runtime jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.category,x.display_name),'[]'::jsonb) into v_settings from(
  select setting_key,category,display_name,setting_value,management_mode,environment_scope,required_for_production,status,description,updated_at
  from pipeline.environment_settings)x;
 select coalesce(jsonb_agg(jsonb_build_object('integration_key',r.integration_key,'display_name',r.display_name,'configured',v.id is not null,'admin_settable',r.admin_settable,'production_rotation_required',r.production_rotation_required,'description',r.description,'updated_at',coalesce(v.updated_at,r.updated_at)) order by r.display_name),'[]'::jsonb) into v_integrations
 from pipeline.integration_secret_registry r left join vault.secrets v on v.name=r.secret_name;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'provider_key',p.provider_key,'display_name',p.display_name,'enabled',p.enabled,'base_url',p.base_url,'auth_scheme',p.auth_scheme,'auth_field_name',p.auth_field_name,'credential_configured',p.vault_secret_id is not null,'priority',p.priority,'rate_limit_per_minute',p.rate_limit_per_minute,'concurrency',p.concurrency,'timeout_seconds',p.timeout_seconds,'billing_config',p.billing_config,'capabilities',p.capabilities,'request_template',p.request_template,'operational_owner',p.operational_owner,'change_control_ref',p.change_control_ref) order by p.priority,p.display_name),'[]'::jsonb) into v_l2 from pipeline.layer2_acquisition_providers p;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'aggregator_provider',p.aggregator_provider,'model_identifier',p.model_identifier,'credential_configured',exists(select 1 from vault.secrets vs where vs.name=security.layer3_provider_credential_name(p.id)),'enabled',p.enabled,'paused',p.paused) order by p.code),'[]'::jsonb) into v_l3 from pipeline.layer3_model_profiles p;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order),'[]'::jsonb) into v_manifest from(
  select component_key,component_group,display_name,migration_mode,required,source_status,target_status,production_action,validation_rule,source_summary,notes,sort_order,updated_at
  from pipeline.production_migration_manifest)x;
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
 return jsonb_build_object('settings',v_settings,'integration_secrets',v_integrations,'layer2_providers',v_l2,'layer3_profiles',v_l3,'migration_manifest',v_manifest,'runtime',v_runtime);
end $$;
revoke all on function public.platform_environment_read_service() from public,anon,authenticated;
grant execute on function public.platform_environment_read_service() to service_role;

create or replace function public.platform_environment_control_service(p_actor uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','security','vault'
as $$
declare v_rank int:=0;v_key text;v_secret_name text;v_secret_id uuid;v_status text;
begin
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<6 then raise exception 'platform_admin role required' using errcode='42501';end if;
 if p_action='set_setting' then
  v_key=trim(p_payload->>'setting_key');
  update pipeline.environment_settings set setting_value=case when p_payload?'value' then p_payload->'value' else setting_value end,
   status=case when p_payload?'value' and p_payload->'value' is not null and p_payload->'value'<>'null'::jsonb then 'configured' else 'pending' end,updated_by=p_actor,updated_at=now()
  where setting_key=v_key and management_mode='admin_edit';
  if not found then raise exception 'setting not admin-editable' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'setting_key',v_key);
 elsif p_action='set_integration_secret' then
  v_key=trim(p_payload->>'integration_key');if coalesce(p_payload->>'secret','')='' then raise exception 'secret required' using errcode='22023';end if;
  select secret_name into v_secret_name from pipeline.integration_secret_registry where integration_key=v_key and admin_settable;
  if v_secret_name is null then raise exception 'integration secret not admin-settable' using errcode='22023';end if;
  select id into v_secret_id from vault.secrets where name=v_secret_name;
  if v_secret_id is null then select vault.create_secret(p_payload->>'secret',v_secret_name,'CourseFinder integration credential: '||v_key,null) into v_secret_id;
  else perform vault.update_secret(v_secret_id,p_payload->>'secret',null,null,null);end if;
  update pipeline.integration_secret_registry set updated_at=now() where integration_key=v_key;
  return jsonb_build_object('ok',true,'integration_key',v_key,'configured',true);
 elsif p_action='set_manifest_status' then
  v_key=trim(p_payload->>'component_key');v_status=trim(p_payload->>'target_status');
  if v_status not in('pending','ready','verified','blocked','not_applicable') then raise exception 'invalid target status' using errcode='22023';end if;
  update pipeline.production_migration_manifest set target_status=v_status,updated_by=p_actor,updated_at=now() where component_key=v_key;
  if not found then raise exception 'manifest component not found' using errcode='22023';end if;
  return jsonb_build_object('ok',true,'component_key',v_key,'target_status',v_status);
 end if;
 raise exception 'unsupported environment action' using errcode='22023';
end $$;
revoke all on function public.platform_environment_control_service(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.platform_environment_control_service(uuid,text,jsonb) to service_role;

commit;
