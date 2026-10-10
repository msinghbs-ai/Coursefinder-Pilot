create table pipeline.layer2_acquisition_providers (
  id uuid primary key default extensions.gen_random_uuid(),
  provider_key text not null unique,
  display_name text not null,
  adapter_type text not null check (adapter_type in ('direct_http','scraper_api','browser_api','structured_api_proxy','custom')),
  base_url text,
  auth_scheme text not null default 'none' check (auth_scheme in ('none','bearer','header','query_param')),
  auth_field_name text,
  vault_secret_id uuid,
  capabilities jsonb not null default '{}'::jsonb,
  request_template jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  priority integer not null default 100 check (priority>0),
  rate_limit_per_minute integer,
  concurrency integer not null default 1 check (concurrency between 1 and 20),
  timeout_seconds integer not null default 30 check (timeout_seconds between 1 and 120),
  last_tested_at timestamptz,
  last_test_status text,
  last_test_http_status integer,
  last_test_error text,
  operational_owner text,
  change_control_ref text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table pipeline.layer2_profile_provider_routes (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references pipeline.layer2_source_profiles(id) on delete cascade,
  acquisition_provider_id uuid not null references pipeline.layer2_acquisition_providers(id) on delete restrict,
  priority integer not null check(priority>0),
  enabled boolean not null default true,
  required_capabilities jsonb not null default '{}'::jsonb,
  request_overrides jsonb not null default '{}'::jsonb,
  evidence_policy jsonb not null default '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true}'::jsonb,
  fallback_on jsonb not null default '["blocked","timeout","403","429","extraction_failed"]'::jsonb,
  change_control_ref text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_id,acquisition_provider_id),
  unique(profile_id,priority)
);

create table pipeline.layer2_provider_attempts (
  id uuid primary key default extensions.gen_random_uuid(),
  job_id uuid not null references pipeline.jobs(id) on delete cascade,
  profile_version_id uuid not null references pipeline.layer2_source_profile_versions(id) on delete restrict,
  acquisition_provider_id uuid not null references pipeline.layer2_acquisition_providers(id) on delete restrict,
  attempt_no integer not null check(attempt_no>0),
  status text not null check(status in ('queued','running','succeeded','failed','blocked','extraction_failed')),
  request_url text,
  response_http_status integer,
  response_mime_type text,
  raw_evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  html_evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  screenshot_evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  extraction_status text,
  blocker text,
  metrics jsonb not null default '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(job_id,attempt_no)
);

create index layer2_provider_route_profile_idx on pipeline.layer2_profile_provider_routes(profile_id,priority) where enabled;
create index layer2_provider_attempt_job_idx on pipeline.layer2_provider_attempts(job_id,attempt_no);
create index layer2_provider_attempt_provider_idx on pipeline.layer2_provider_attempts(acquisition_provider_id,created_at desc);
alter table pipeline.layer2_acquisition_providers enable row level security;
alter table pipeline.layer2_profile_provider_routes enable row level security;
alter table pipeline.layer2_provider_attempts enable row level security;
revoke all on pipeline.layer2_acquisition_providers,pipeline.layer2_profile_provider_routes,pipeline.layer2_provider_attempts from public,anon,authenticated;

create or replace function security.admin_layer2_provider_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','security','pipeline','public' as $$
declare v_rank int;v_id uuid;v_result jsonb;begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select security.current_role_rank() into v_rank;if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501';end if;
 if p_operation='layer2_acquisition_providers' then
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'provider_key',p.provider_key,'display_name',p.display_name,'adapter_type',p.adapter_type,'base_url',p.base_url,'auth_scheme',p.auth_scheme,'auth_field_name',p.auth_field_name,'credential_configured',p.vault_secret_id is not null,'capabilities',p.capabilities,'request_template',p.request_template,'enabled',p.enabled,'priority',p.priority,'rate_limit_per_minute',p.rate_limit_per_minute,'concurrency',p.concurrency,'timeout_seconds',p.timeout_seconds,'last_tested_at',p.last_tested_at,'last_test_status',p.last_test_status,'last_test_http_status',p.last_test_http_status,'last_test_error',p.last_test_error,'operational_owner',p.operational_owner,'change_control_ref',p.change_control_ref,'route_count',(select count(*) from pipeline.layer2_profile_provider_routes r where r.acquisition_provider_id=p.id)) order by p.priority,p.display_name),'[]'::jsonb) into v_result from pipeline.layer2_acquisition_providers p;return v_result;
 end if;
 if p_operation='layer2_provider_routes' then
  v_id:=nullif(p_args->>'profile_id','')::uuid;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'profile_id',r.profile_id,'provider_id',p.id,'provider_key',p.provider_key,'display_name',p.display_name,'adapter_type',p.adapter_type,'priority',r.priority,'enabled',r.enabled,'credential_configured',p.vault_secret_id is not null,'capabilities',p.capabilities,'required_capabilities',r.required_capabilities,'request_overrides',r.request_overrides,'evidence_policy',r.evidence_policy,'fallback_on',r.fallback_on,'last_test_status',p.last_test_status) order by r.priority),'[]'::jsonb) into v_result from pipeline.layer2_profile_provider_routes r join pipeline.layer2_acquisition_providers p on p.id=r.acquisition_provider_id where r.profile_id=v_id;return v_result;
 end if;
 if p_operation='layer2_provider_attempts' then
  v_id:=nullif(p_args->>'job_id','')::uuid;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'job_id',a.job_id,'attempt_no',a.attempt_no,'status',a.status,'provider_key',p.provider_key,'display_name',p.display_name,'response_http_status',a.response_http_status,'response_mime_type',a.response_mime_type,'raw_evidence_id',a.raw_evidence_id,'html_evidence_id',a.html_evidence_id,'screenshot_evidence_id',a.screenshot_evidence_id,'extraction_status',a.extraction_status,'blocker',a.blocker,'metrics',a.metrics,'started_at',a.started_at,'completed_at',a.completed_at) order by a.attempt_no),'[]'::jsonb) into v_result from pipeline.layer2_provider_attempts a join pipeline.layer2_acquisition_providers p on p.id=a.acquisition_provider_id where a.job_id=v_id;return v_result;
 end if;
 raise exception 'unsupported Layer 2 provider read operation' using errcode='22023';
end$$;
revoke all on function security.admin_layer2_provider_read(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer2_provider_read(text,jsonb) to authenticated,service_role;

create or replace function public.layer2_provider_control(p_actor uuid,p_action text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','security','pipeline','vault' as $$
declare v_rank int:=0;v_id uuid;v_secret_id uuid;v_profile uuid;v_provider uuid;begin
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if p_action in ('create_provider','update_provider','set_secret') and v_rank<6 then raise exception 'platform_admin role required' using errcode='42501';end if;
 if p_action='upsert_route' and v_rank<5 then raise exception 'pim_admin role required' using errcode='42501';end if;
 if p_action='create_provider' then
  insert into pipeline.layer2_acquisition_providers(provider_key,display_name,adapter_type,base_url,auth_scheme,auth_field_name,capabilities,request_template,enabled,priority,rate_limit_per_minute,concurrency,timeout_seconds,operational_owner,change_control_ref)
  values(trim(p_payload->>'provider_key'),trim(p_payload->>'display_name'),p_payload->>'adapter_type',nullif(trim(p_payload->>'base_url'),''),coalesce(nullif(p_payload->>'auth_scheme',''),'none'),nullif(trim(p_payload->>'auth_field_name'),''),coalesce(p_payload->'capabilities','{}'::jsonb),coalesce(p_payload->'request_template','{}'::jsonb),coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'priority')::int,100),nullif(p_payload->>'rate_limit_per_minute','')::int,coalesce((p_payload->>'concurrency')::int,1),coalesce((p_payload->>'timeout_seconds')::int,30),nullif(trim(p_payload->>'operational_owner'),''),coalesce(nullif(trim(p_payload->>'change_control_ref'),''),'CF-CHG-20260823-029')) returning id into v_id;return jsonb_build_object('ok',true,'id',v_id);
 elsif p_action='update_provider' then
  v_id:=(p_payload->>'id')::uuid;update pipeline.layer2_acquisition_providers set display_name=coalesce(nullif(trim(p_payload->>'display_name'),''),display_name),base_url=case when p_payload?'base_url' then nullif(trim(p_payload->>'base_url'),'') else base_url end,auth_scheme=coalesce(nullif(p_payload->>'auth_scheme',''),auth_scheme),auth_field_name=case when p_payload?'auth_field_name' then nullif(trim(p_payload->>'auth_field_name'),'') else auth_field_name end,capabilities=coalesce(p_payload->'capabilities',capabilities),request_template=coalesce(p_payload->'request_template',request_template),enabled=coalesce((p_payload->>'enabled')::boolean,enabled),priority=coalesce((p_payload->>'priority')::int,priority),rate_limit_per_minute=case when p_payload?'rate_limit_per_minute' then nullif(p_payload->>'rate_limit_per_minute','')::int else rate_limit_per_minute end,concurrency=coalesce((p_payload->>'concurrency')::int,concurrency),timeout_seconds=coalesce((p_payload->>'timeout_seconds')::int,timeout_seconds),operational_owner=case when p_payload?'operational_owner' then nullif(trim(p_payload->>'operational_owner'),'') else operational_owner end,updated_at=now() where id=v_id;return jsonb_build_object('ok',found,'id',v_id);
 elsif p_action='set_secret' then
  v_id:=(p_payload->>'id')::uuid;if coalesce(p_payload->>'secret','')='' then raise exception 'secret required' using errcode='22023';end if;select vault_secret_id into v_secret_id from pipeline.layer2_acquisition_providers where id=v_id for update;if v_secret_id is null then select vault.create_secret(p_payload->>'secret','coursefinder_l2_provider_'||v_id::text,'CourseFinder Layer 2 provider credential',null) into v_secret_id;update pipeline.layer2_acquisition_providers set vault_secret_id=v_secret_id,updated_at=now() where id=v_id;else perform vault.update_secret(v_secret_id,p_payload->>'secret',null,null,null);end if;return jsonb_build_object('ok',true,'id',v_id,'credential_configured',true);
 elsif p_action='upsert_route' then
  v_profile:=(p_payload->>'profile_id')::uuid;v_provider:=(p_payload->>'provider_id')::uuid;insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref) values(v_profile,v_provider,coalesce((p_payload->>'priority')::int,100),coalesce((p_payload->>'enabled')::boolean,true),coalesce(p_payload->'required_capabilities','{}'::jsonb),coalesce(p_payload->'request_overrides','{}'::jsonb),coalesce(p_payload->'evidence_policy','{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":true}'::jsonb),coalesce(p_payload->'fallback_on','["blocked","timeout","403","429","extraction_failed"]'::jsonb),coalesce(nullif(trim(p_payload->>'change_control_ref'),''),'CF-CHG-20260823-029')) on conflict(profile_id,acquisition_provider_id) do update set priority=excluded.priority,enabled=excluded.enabled,required_capabilities=excluded.required_capabilities,request_overrides=excluded.request_overrides,evidence_policy=excluded.evidence_policy,fallback_on=excluded.fallback_on,updated_at=now();return jsonb_build_object('ok',true);
 end if;
 raise exception 'unsupported provider action' using errcode='22023';
end$$;
revoke all on function public.layer2_provider_control(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_provider_control(uuid,text,jsonb) to service_role;

insert into pipeline.layer2_acquisition_providers(provider_key,display_name,adapter_type,base_url,auth_scheme,capabilities,request_template,priority,operational_owner,change_control_ref)
values
 ('direct-http','Direct HTTP','direct_http',null,'none','{"raw":true,"html":true,"json":true,"screenshot":false,"javascript":false}'::jsonb,'{}'::jsonb,10,'Platform Operations','CF-CHG-20260823-029'),
 ('scrape-do','Scrape.do','scraper_api','https://api.scrape.do/','query_param','{"raw":true,"html":true,"json":true,"screenshot":false,"javascript":true,"anti_bot":true,"proxy":true}'::jsonb,'{"target_url_parameter":"url","credential_parameter":"token"}'::jsonb,20,'Platform Operations','CF-CHG-20260823-029')
on conflict(provider_key) do nothing;
