-- M2.1 Layer 2 Enrichment Platform & Source Configuration Foundation
-- CF-CHG-20260823-029

create table if not exists pipeline.layer2_source_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  source_id uuid not null unique references pipeline.sources(id) on delete restrict,
  profile_key text not null unique,
  domain text not null,
  acquisition_method text not null,
  target_entity_type text not null,
  authority_class text not null default 'first_party',
  enabled boolean not null default true,
  paused boolean not null default false,
  operational_owner text,
  freshness_sla_hours integer check (freshness_sla_hours is null or freshness_sla_hours > 0),
  schedule_text text,
  current_version_id uuid,
  last_inventory_at timestamptz,
  last_inventory_count integer check (last_inventory_count is null or last_inventory_count >= 0),
  last_inventory_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint layer2_profiles_method_chk check (acquisition_method in ('website','course_catalogue','course_detail','fee_schedule','intake_calendar','english_requirements','scholarship_catalogue','document','structured_api','json_endpoint','csv_feed','xlsx_feed','sitemap','search_endpoint','other_deterministic'))
);

create table if not exists pipeline.layer2_source_profile_versions (
  id uuid primary key default extensions.gen_random_uuid(),
  profile_id uuid not null references pipeline.layer2_source_profiles(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  configuration jsonb not null default '{}'::jsonb,
  configuration_hash text not null,
  validation_status text not null default 'pending' check (validation_status in ('pending','valid','invalid','superseded')),
  validation_result jsonb not null default '{}'::jsonb,
  change_control_ref text,
  uat_ref text,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique(profile_id,version_no),
  unique(profile_id,configuration_hash)
);

alter table pipeline.layer2_source_profiles
  add constraint layer2_profiles_current_version_fk foreign key (current_version_id) references pipeline.layer2_source_profile_versions(id) on delete restrict;

alter table pipeline.jobs add column if not exists source_profile_version_id uuid references pipeline.layer2_source_profile_versions(id) on delete restrict;
alter table pipeline.evidence_artifacts add column if not exists source_profile_version_id uuid references pipeline.layer2_source_profile_versions(id) on delete restrict;

create index if not exists layer2_profiles_method_idx on pipeline.layer2_source_profiles(acquisition_method);
create index if not exists layer2_profiles_state_idx on pipeline.layer2_source_profiles(enabled,paused);
create index if not exists layer2_versions_profile_idx on pipeline.layer2_source_profile_versions(profile_id,version_no desc);
create index if not exists jobs_layer2_profile_version_idx on pipeline.jobs(source_profile_version_id) where source_profile_version_id is not null;
create index if not exists evidence_layer2_profile_version_idx on pipeline.evidence_artifacts(source_profile_version_id) where source_profile_version_id is not null;

alter table pipeline.layer2_source_profiles enable row level security;
alter table pipeline.layer2_source_profile_versions enable row level security;
revoke all on pipeline.layer2_source_profiles from public, anon, authenticated;
revoke all on pipeline.layer2_source_profile_versions from public, anon, authenticated;

create or replace function security.layer2_validate_profile_config(p_config jsonb)
returns jsonb
language plpgsql
stable
set search_path='pg_catalog','security'
as $$
declare
  v_errors jsonb := '[]'::jsonb;
  v_method text := coalesce(p_config->>'acquisition_method','');
  v_target text := coalesce(p_config->>'target_entity_type','');
  v_text text := lower(p_config::text);
begin
  if v_method not in ('website','course_catalogue','course_detail','fee_schedule','intake_calendar','english_requirements','scholarship_catalogue','document','structured_api','json_endpoint','csv_feed','xlsx_feed','sitemap','search_endpoint','other_deterministic') then v_errors := v_errors || jsonb_build_array('unsupported acquisition_method'); end if;
  if v_target not in ('provider','course','campus','scholarship','provider_outcome','student_flow','course_fact','mixed') then v_errors := v_errors || jsonb_build_array('unsupported target_entity_type'); end if;
  if coalesce(p_config->>'base_domain','')='' and coalesce(p_config->>'discovery_url','')='' then v_errors := v_errors || jsonb_build_array('base_domain or discovery_url is required'); end if;
  if coalesce((p_config->>'timeout_seconds')::integer,30) < 1 or coalesce((p_config->>'timeout_seconds')::integer,30) > 120 then v_errors := v_errors || jsonb_build_array('timeout_seconds must be between 1 and 120'); end if;
  if coalesce((p_config->>'concurrency')::integer,1) < 1 or coalesce((p_config->>'concurrency')::integer,1) > 20 then v_errors := v_errors || jsonb_build_array('concurrency must be between 1 and 20'); end if;
  if coalesce((p_config->>'max_payload_mb')::integer,10) < 1 or coalesce((p_config->>'max_payload_mb')::integer,10) > 100 then v_errors := v_errors || jsonb_build_array('max_payload_mb must be between 1 and 100'); end if;
  if v_text ~ '"(secret|password|token|api[_-]?key|authorization|cookie|client[_-]?secret)"[[:space:]]*:' then v_errors := v_errors || jsonb_build_array('secret-like configuration keys are prohibited; use server-side secret references only'); end if;
  if coalesce(p_config->>'evidence_required','true') <> 'true' then v_errors := v_errors || jsonb_build_array('Layer 2 evidence_required must be true'); end if;
  return jsonb_build_object('valid',jsonb_array_length(v_errors)=0,'errors',v_errors,'validated_at',now());
exception when others then
  return jsonb_build_object('valid',false,'errors',jsonb_build_array('configuration type validation failed'),'validated_at',now());
end
$$;

create or replace function security.admin_layer2_config_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path='pg_catalog','security','pipeline','ref','catalogue','public'
as $$
declare v_rank integer:=0; v_id uuid; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_operation='layer2_profiles' then
    select coalesce(jsonb_agg(row_json order by lower(row_json->>'source_label')),'[]'::jsonb) into v_result
    from (
      select jsonb_build_object(
        'profile_id',p.id,'profile_key',p.profile_key,'source_id',p.source_id,'source_label',s.label,'country_code',c.iso_alpha2,
        'source_type',s.source_type,'source_url',s.url,'trust_rank',s.trust_rank,'domain',p.domain,'acquisition_method',p.acquisition_method,
        'target_entity_type',p.target_entity_type,'authority_class',p.authority_class,'enabled',p.enabled,'paused',p.paused,
        'operational_owner',p.operational_owner,'freshness_sla_hours',p.freshness_sla_hours,'schedule_text',p.schedule_text,
        'current_version_id',p.current_version_id,'current_version',v.version_no,'validation_status',v.validation_status,
        'validation_result',v.validation_result,'change_control_ref',v.change_control_ref,'uat_ref',v.uat_ref,
        'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,
        'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,'last_inventory_hash',p.last_inventory_hash,
        'job_count',(select count(*) from pipeline.jobs j where j.source_id=p.source_id),
        'evidence_count',(select count(*) from pipeline.evidence_artifacts e where e.source_id=p.source_id),
        'version_count',(select count(*) from pipeline.layer2_source_profile_versions vv where vv.profile_id=p.id),
        'affected_provider_id',s.provider_id,
        'health',case when not p.enabled then 'disabled' when p.paused then 'paused' when v.validation_status<>'valid' then 'blocked' when s.last_failure_at is not null and (s.last_success_at is null or s.last_failure_at>s.last_success_at) then 'degraded' when p.freshness_sla_hours is not null and s.last_success_at is not null and s.last_success_at < now()-(p.freshness_sla_hours||' hours')::interval then 'stale' else 'healthy' end
      ) row_json
      from pipeline.layer2_source_profiles p
      join pipeline.sources s on s.id=p.source_id
      left join ref.countries c on c.id=s.country_id
      left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
    ) q;
    return v_result;
  end if;

  if p_operation='layer2_profile_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select jsonb_build_object(
      'profile',jsonb_build_object('id',p.id,'profile_key',p.profile_key,'source_id',p.source_id,'source_label',s.label,'country_code',c.iso_alpha2,'source_url',s.url,'trust_rank',s.trust_rank,'domain',p.domain,'acquisition_method',p.acquisition_method,'target_entity_type',p.target_entity_type,'authority_class',p.authority_class,'enabled',p.enabled,'paused',p.paused,'operational_owner',p.operational_owner,'freshness_sla_hours',p.freshness_sla_hours,'schedule_text',p.schedule_text,'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,'last_inventory_hash',p.last_inventory_hash),
      'current_version',case when v.id is null then null else jsonb_build_object('id',v.id,'version_no',v.version_no,'configuration',v.configuration,'configuration_hash',v.configuration_hash,'validation_status',v.validation_status,'validation_result',v.validation_result,'change_control_ref',v.change_control_ref,'uat_ref',v.uat_ref,'created_at',v.created_at) end,
      'history',(select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'version_no',h.version_no,'configuration_hash',h.configuration_hash,'validation_status',h.validation_status,'validation_result',h.validation_result,'change_control_ref',h.change_control_ref,'uat_ref',h.uat_ref,'created_at',h.created_at,'configuration',h.configuration) order by h.version_no desc),'[]'::jsonb) from pipeline.layer2_source_profile_versions h where h.profile_id=p.id),
      'recent_jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'status',j.status,'job_type',j.job_type,'created_at',j.created_at,'completed_at',j.completed_at,'source_profile_version_id',j.source_profile_version_id) order by j.created_at desc),'[]'::jsonb) from (select * from pipeline.jobs jj where jj.source_id=p.source_id order by jj.created_at desc limit 20) j),
      'recent_evidence',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'mime_type',e.mime_type,'captured_at',e.captured_at,'content_hash',e.content_hash,'source_profile_version_id',e.source_profile_version_id) order by e.captured_at desc),'[]'::jsonb) from (select * from pipeline.evidence_artifacts ee where ee.source_id=p.source_id order by ee.captured_at desc limit 20) e)
    ) into v_result
    from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id left join ref.countries c on c.id=s.country_id left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.id=v_id;
    return coalesce(v_result,'{}'::jsonb);
  end if;
  raise exception 'unsupported layer2 read operation: %',p_operation using errcode='22023';
end
$$;

-- public.admin_read is replaced in the deployed migration by preserving all existing branches
-- and adding only these operations before admin_read_impl fallback:
--   if p_operation in ('layer2_profiles','layer2_profile_detail') then
--     return security.admin_layer2_config_read(p_operation,p_args);
--   end if;

create or replace function public.layer2_config_control(p_actor uuid,p_action text,p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','security','pipeline'
as $$
declare v_rank integer:=0; v_version pipeline.layer2_source_profile_versions%rowtype; v_validation jsonb;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 6 then raise exception 'platform_admin role required' using errcode='42501'; end if;
  if p_action='validate' then
    select v.* into v_version from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.id=p_profile_id for update of v;
    if v_version.id is null then raise exception 'profile/current version not found' using errcode='22023'; end if;
    v_validation:=security.layer2_validate_profile_config(v_version.configuration);
    update pipeline.layer2_source_profile_versions set validation_result=v_validation,validation_status=case when (v_validation->>'valid')::boolean then 'valid' else 'invalid' end where id=v_version.id;
  elsif p_action='pause' then update pipeline.layer2_source_profiles set paused=true,updated_at=now() where id=p_profile_id;
  elsif p_action='resume' then update pipeline.layer2_source_profiles set paused=false,updated_at=now() where id=p_profile_id;
  elsif p_action='disable' then update pipeline.layer2_source_profiles set enabled=false,paused=true,updated_at=now() where id=p_profile_id;
  elsif p_action='enable' then update pipeline.layer2_source_profiles set enabled=true,paused=false,updated_at=now() where id=p_profile_id;
  else raise exception 'unsupported action' using errcode='22023';
  end if;
  if not found and p_action<>'validate' then raise exception 'profile not found' using errcode='22023'; end if;
  return jsonb_build_object('ok',true,'profile_id',p_profile_id,'action',p_action,'validation',v_validation);
end
$$;
revoke all on function public.layer2_config_control(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_config_control(uuid,text,uuid) to service_role;

with seed as (
  select s.id source_id,
    case s.id
      when '1f48c9a3-8c13-43f9-9134-ef533ef7bed8'::uuid then 'au-rmit-course-detail'
      when '9d1ce891-c80e-4f4e-b8ef-e0ffb1b0dd05'::uuid then 'au-uq-course-catalogue'
      when 'a37a569c-105e-4d9e-b802-44b68ff7ecc6'::uuid then 'au-qilt-ess-structured-file'
      when '37f1776c-77a3-4083-8ec7-7d76ad7a9ad8'::uuid then 'au-prisms-xlsx'
      when '17a7d379-9448-41ca-bca5-bb7537ffff4b'::uuid then 'au-study-australia-scholarship-search'
    end profile_key,
    case when s.id='17a7d379-9448-41ca-bca5-bb7537ffff4b'::uuid then 'scholarship' when s.id in ('a37a569c-105e-4d9e-b802-44b68ff7ecc6'::uuid,'37f1776c-77a3-4083-8ec7-7d76ad7a9ad8'::uuid) then 'outcomes' else 'course_facts' end domain,
    case s.id when '1f48c9a3-8c13-43f9-9134-ef533ef7bed8'::uuid then 'course_detail' when '9d1ce891-c80e-4f4e-b8ef-e0ffb1b0dd05'::uuid then 'course_catalogue' when 'a37a569c-105e-4d9e-b802-44b68ff7ecc6'::uuid then 'document' when '37f1776c-77a3-4083-8ec7-7d76ad7a9ad8'::uuid then 'xlsx_feed' else 'search_endpoint' end acquisition_method,
    case when s.id='17a7d379-9448-41ca-bca5-bb7537ffff4b'::uuid then 'scholarship' when s.id='a37a569c-105e-4d9e-b802-44b68ff7ecc6'::uuid then 'provider_outcome' when s.id='37f1776c-77a3-4083-8ec7-7d76ad7a9ad8'::uuid then 'student_flow' else 'course_fact' end target_entity_type
  from pipeline.sources s where s.id in ('1f48c9a3-8c13-43f9-9134-ef533ef7bed8','9d1ce891-c80e-4f4e-b8ef-e0ffb1b0dd05','a37a569c-105e-4d9e-b802-44b68ff7ecc6','37f1776c-77a3-4083-8ec7-7d76ad7a9ad8','17a7d379-9448-41ca-bca5-bb7537ffff4b')
)
insert into pipeline.layer2_source_profiles(source_id,profile_key,domain,acquisition_method,target_entity_type,authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text)
select source_id,profile_key,domain,acquisition_method,target_entity_type,'official_or_first_party',true,false,'PIM/Data Operations',168,'manual/governed' from seed
on conflict (source_id) do nothing;

do $$
declare r record; cfg jsonb; h text; vid uuid; val jsonb;
begin
  for r in select p.*,s.url,s.label,s.metadata from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id where p.current_version_id is null loop
    cfg:=jsonb_build_object(
      'acquisition_method',r.acquisition_method,'base_domain',regexp_replace(coalesce(r.url,''),'^(https?://[^/]+).*$','\1'),'discovery_url',r.url,
      'url_patterns',jsonb_build_array(r.url),'inclusion_rules',jsonb_build_array(),'exclusion_rules',jsonb_build_array(),
      'pagination',jsonb_build_object('mode','source_specific'),'headers',jsonb_build_object('user_agent','CourseFinder deterministic acquisition'),
      'authentication',jsonb_build_object('mechanism','none_or_server_secret_reference'),'rate_limit_per_minute',60,'concurrency',2,'timeout_seconds',30,'retry',jsonb_build_object('max_attempts',3,'backoff','exponential'),
      'robots_policy','respect','allowed_mime_types',case when r.acquisition_method in ('document','xlsx_feed') then jsonb_build_array('application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/zip') else jsonb_build_array('text/html','application/json') end,
      'max_payload_mb',25,'parser_profile',coalesce(r.metadata->>'worker_version','deterministic-v1'),'target_entity_type',r.target_entity_type,
      'mapping_strategy',case when r.target_entity_type='course_fact' then 'stable Layer 1 course match; exact regulatory code where available' else 'source-scoped deterministic mapping' end,
      'stable_identifier_strategy',coalesce(r.metadata->>'course_identity',r.metadata->>'source_identifier_scheme','source_scoped_stable_identifier'),
      'regulatory_code_extraction',jsonb_build_object('cricos',r.metadata->>'provider_cricos','nzqa',null),'evidence_required',true,
      'freshness_sla_hours',r.freshness_sla_hours,'schedule',r.schedule_text,'content_change_policy','hash_then_observe_never_direct_canonical_mutation',
      'source_authority','official/first-party deterministic enrichment','operational_owner',r.operational_owner,'change_control_ref','CF-CHG-20260823-029'
    );
    h:=encode(extensions.digest(cfg::text,'sha256'),'hex');
    val:=security.layer2_validate_profile_config(cfg);
    insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref)
    values(r.id,1,cfg,h,case when (val->>'valid')::boolean then 'valid' else 'invalid' end,val,'CF-CHG-20260823-029') returning id into vid;
    update pipeline.layer2_source_profiles set current_version_id=vid where id=r.id;
  end loop;
end $$;
