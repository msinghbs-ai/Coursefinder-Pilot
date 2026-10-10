-- CF-CHG-20260903-084 follow-up: remove hard-coded Pilot Edge dispatch targets.
begin;

insert into pipeline.environment_settings(setting_key,category,display_name,setting_value,management_mode,environment_scope,required_for_production,status,description)
values
 ('runtime_edge_base_url','runtime','Runtime Edge Functions base URL','"https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1"'::jsonb,'admin_edit','per_environment',true,'configured','Database-to-Edge dispatch base URL. Rebind to Production before enabling Production cron.'),
 ('runtime_automation_integration_key','runtime','Runtime automation credential selector','"pilot_automation"'::jsonb,'admin_edit','per_environment',true,'configured','Selects which registered Vault automation secret database dispatch helpers use. Production must use production_automation.')
on conflict(setting_key) do update set display_name=excluded.display_name,management_mode=excluded.management_mode,required_for_production=excluded.required_for_production,description=excluded.description;

insert into pipeline.integration_secret_registry(integration_key,display_name,secret_name,admin_settable,production_rotation_required,description)
values('pilot_automation','Pilot automation key','coursefinder_pilot_automation_key',false,true,'Existing Pilot-only automation credential. Must not be selected in Production.')
on conflict(integration_key) do update set display_name=excluded.display_name,secret_name=excluded.secret_name,admin_settable=false,production_rotation_required=true,description=excluded.description;

create or replace function public.coursefinder_runtime_edge_base_url()
returns text language sql stable security definer
set search_path='pg_catalog','pipeline'
as $$select nullif(trim(both '"' from setting_value::text),'') from pipeline.environment_settings where setting_key='runtime_edge_base_url'$$;
revoke all on function public.coursefinder_runtime_edge_base_url() from public,anon,authenticated;
grant execute on function public.coursefinder_runtime_edge_base_url() to service_role;

create or replace function public.coursefinder_runtime_automation_key()
returns text language plpgsql stable security definer
set search_path='pg_catalog','public','pipeline','vault'
as $$
declare v_integration text;v_secret_name text;v_value text;
begin
 select trim(both '"' from setting_value::text) into v_integration from pipeline.environment_settings where setting_key='runtime_automation_integration_key';
 select secret_name into v_secret_name from pipeline.integration_secret_registry where integration_key=v_integration;
 if v_secret_name is null then return null;end if;
 select decrypted_secret into v_value from vault.decrypted_secrets where name=v_secret_name limit 1;
 return v_value;
end $$;
revoke all on function public.coursefinder_runtime_automation_key() from public,anon,authenticated;
grant execute on function public.coursefinder_runtime_automation_key() to service_role;

create or replace function pipeline.svc_pilot_invoke_edge(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','vault','net','public'
as $$
declare v_key text;v_id bigint;v_base text;
begin
 if p_function not in('layer1-ca-ab-alis-degrees','layer1-ca-bc-epbc-programs','layer1-ca-qc-university-programs','layer1-ca-sk-programs','layer1-ca-mb-programs','layer1-ca-ns-sk-programs','layer1-ca-cna-programs','layer1-ca-firstparty-catalogues','layer1-ca-provider-geography','layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue','layer1-ca-conestoga-catalogue','layer1-ca-fanshawe-pgwp','layer1-ca-mohawk-catalogue','layer1-ca-durham-programs') then raise exception 'Edge function is not allowlisted';end if;
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation secret missing';end if;if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=30000) into v_id;return v_id;
end $$;

create or replace function pipeline.svc_pilot_invoke_layer2(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','vault','net','public'
as $$
declare v_key text;v_id bigint;v_base text;
begin
 if p_function not in('layer2-acquire-v2','layer2-extract-v2','layer2-course-fact-extract-v2','layer2-scholarship-extract','layer2-scholarship-catalogue-enumerate','layer2-provider-page-fanout','layer2-provider-asset-promote') then raise exception 'Layer2 automation function not allowlisted';end if;
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation secret missing';end if;if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;return v_id;
end $$;

create or replace function pipeline.svc_pilot_invoke_layer2_v2(p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','vault','net','public'
as $$
declare v_key text;v_id bigint;v_base text;
begin
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation secret missing';end if;if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/layer2-acquire-v2',headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;return v_id;
end $$;

create or replace function pipeline.svc_pilot_invoke_scholarship_edge(p_body jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_nonce uuid:=gen_random_uuid();v_request_id bigint;v_base text;
begin
 insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,'scholarships-au-etl',now()+interval '5 minutes');
 v_base:=public.coursefinder_runtime_edge_base_url();if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/scholarships-au-etl',headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=30000) into v_request_id;
 return jsonb_build_object('request_id',v_request_id,'nonce',v_nonce);
end $$;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','net','public','extensions'
as $$
declare v_nonce uuid:=extensions.gen_random_uuid();v_id bigint;v_base text;
begin
 if p_function not in('layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness','coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled','layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled','layer3-source-pattern-benchmark','layer3-contact-benchmark','layer2-screenshot-backfill-scheduled','provider-contact-discover-scheduled','provider-contact-enrich-apollo') then raise exception 'one-time Edge function is not allowlisted';end if;
 insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
 v_base:=public.coursefinder_runtime_edge_base_url();if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;return v_id;
end $$;

create or replace function public.layer2_run_batch_dispatch(p_batch_id uuid)
returns bigint language plpgsql security definer set search_path='pg_catalog','public','vault','net'
as $$
declare v_key text;v_req bigint;v_base text;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation key unavailable';end if;if v_base is null then raise exception 'runtime Edge base URL unavailable';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/layer2-batch-runner',headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=jsonb_build_object('batch_id',p_batch_id),timeout_milliseconds:=120000) into v_req;return v_req;
end $$;

update pipeline.production_migration_manifest
set production_action='Set runtime_edge_base_url to the target /functions/v1 base and runtime_automation_integration_key to production_automation before enabling Production cron. Replace deployment CORS origins separately.',
validation_rule='No dispatch helper or cron job contains/calls the Pilot project URL; bounded Edge dispatch reaches the target project.'
where component_key='cors_origins';

commit;