-- M2.5 — Production readiness / platform operations maturity foundation.
-- CF-CHG-20260901-051
-- Additive Pilot-only controls. Does not provision Production, enable Production consumers,
-- alter Layer authority, or perform destructive retention.

begin;

create table if not exists pipeline.environment_source_gates (
  id uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('pilot','production')),
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  capability text not null check (capability in (
    'provider_ingestion','course_ingestion','scholarship_ingestion',
    'layer2_enrichment','consumer_search_exposure'
  )),
  lifecycle_state text not null default 'seed_only' check (lifecycle_state in (
    'seed_only','source_identified','source_qualified','pilot_ingestion',
    'pilot_uat_pass','production_approved','production_enabled','monitored'
  )),
  enabled boolean not null default false,
  uat_ref text,
  approval_evidence jsonb not null default '{}'::jsonb,
  reason text not null default 'not yet approved',
  approved_by uuid,
  approved_at timestamptz,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(environment,source_id,capability),
  check (
    environment='production'
    or lifecycle_state not in ('production_approved','production_enabled','monitored')
  ),
  check (
    not enabled
    or (environment='pilot' and lifecycle_state in ('pilot_ingestion','pilot_uat_pass'))
    or (environment='production' and lifecycle_state in ('production_enabled','monitored'))
  )
);

comment on table pipeline.environment_source_gates is
'Environment-specific country/source capability approval. Pilot qualification never implies Production enablement.';

create table if not exists pipeline.layer2_provider_environment_gates (
  acquisition_provider_id uuid not null references pipeline.layer2_acquisition_providers(id) on delete restrict,
  environment text not null check (environment in ('pilot','production')),
  qualification_state text not null default 'registered' check (qualification_state in (
    'registered','credential_ready','pilot_qualified','production_approved',
    'production_enabled','suspended'
  )),
  enabled boolean not null default false,
  uat_ref text,
  qualification_evidence jsonb not null default '{}'::jsonb,
  reason text not null default 'not yet approved',
  approved_by uuid,
  approved_at timestamptz,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(acquisition_provider_id,environment),
  check (
    environment='production'
    or qualification_state not in ('production_approved','production_enabled')
  ),
  check (
    not enabled
    or (environment='pilot' and qualification_state='pilot_qualified')
    or (environment='production' and qualification_state='production_enabled')
  )
);

comment on table pipeline.layer2_provider_environment_gates is
'Scraper/acquisition-provider qualification per environment. Provider config and credentials remain separate.';

create table if not exists pipeline.layer3_profile_environment_gates (
  profile_id uuid not null references pipeline.layer3_model_profiles(id) on delete restrict,
  environment text not null check (environment in ('pilot','production')),
  qualification_state text not null default 'registered' check (qualification_state in (
    'registered','credential_ready','benchmark_pending','pilot_qualified',
    'production_approved','production_enabled','suspended'
  )),
  enabled boolean not null default false,
  uat_ref text,
  benchmark_ref text,
  qualification_evidence jsonb not null default '{}'::jsonb,
  reason text not null default 'not yet approved',
  approved_by uuid,
  approved_at timestamptz,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(profile_id,environment),
  check (
    environment='production'
    or qualification_state not in ('production_approved','production_enabled')
  ),
  check (
    not enabled
    or (environment='pilot' and qualification_state='pilot_qualified')
    or (environment='production' and qualification_state='production_enabled')
  )
);

comment on table pipeline.layer3_profile_environment_gates is
'AI model/task profile qualification per environment. No profile receives generic canonical mutation authority.';

create table if not exists pipeline.platform_capacity_policy (
  environment text primary key check (environment in ('pilot','production')),
  database_warn_bytes bigint,
  database_high_bytes bigint,
  database_critical_bytes bigint,
  temp_spill_warn_bytes_per_day bigint,
  temp_spill_high_bytes_per_day bigint,
  temp_spill_critical_bytes_per_day bigint,
  failed_orphan_upload_warn_count integer not null default 1,
  observation_retention_days integer not null default 180 check (observation_retention_days between 30 and 730),
  notification_target text,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  updated_at timestamptz not null default now(),
  check (
    database_warn_bytes is null or database_high_bytes is null or database_warn_bytes < database_high_bytes
  ),
  check (
    database_high_bytes is null or database_critical_bytes is null or database_high_bytes < database_critical_bytes
  )
);

insert into pipeline.platform_capacity_policy(
  environment,database_warn_bytes,database_high_bytes,database_critical_bytes,
  temp_spill_warn_bytes_per_day,temp_spill_high_bytes_per_day,temp_spill_critical_bytes_per_day,
  failed_orphan_upload_warn_count,notification_target,change_control_ref
) values (
  'pilot',
  1073741824,2147483648,4294967296,
  5368709120,10737418240,21474836480,
  1,null,'CF-CHG-20260901-051'
)
on conflict(environment) do nothing;

comment on table pipeline.platform_capacity_policy is
'Operational warning/high/critical planning thresholds. These are CourseFinder policy thresholds, not vendor hard quotas.';

create table if not exists pipeline.platform_capacity_observations (
  id bigint generated always as identity primary key,
  environment text not null check (environment in ('pilot','production')),
  observed_at timestamptz not null default now(),
  database_bytes bigint not null,
  cumulative_temp_bytes bigint not null,
  cumulative_temp_files bigint not null,
  evidence_object_count bigint not null,
  evidence_object_bytes bigint not null,
  evidence_artifact_count bigint not null,
  orphan_object_count bigint not null,
  failed_upload_count bigint not null,
  largest_relations jsonb not null default '[]'::jsonb,
  evidence_policy jsonb not null default '{}'::jsonb,
  backup_status text not null default 'platform_api_required',
  pitr_status text not null default 'platform_api_required',
  change_control_ref text not null default 'CF-CHG-20260901-051'
);

create index if not exists platform_capacity_observations_env_time_idx
  on pipeline.platform_capacity_observations(environment,observed_at desc);

create table if not exists pipeline.retention_class_policies (
  class_key text primary key,
  object_scope text not null,
  immutable boolean not null default false,
  purge_allowed boolean not null default false,
  default_retention_days integer,
  dry_run_required boolean not null default true,
  bounded_delete_limit integer,
  post_delete_integrity_required boolean not null default true,
  notes text not null,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  updated_at timestamptz not null default now(),
  check (not immutable or not purge_allowed),
  check (default_retention_days is null or default_retention_days >= 1),
  check (bounded_delete_limit is null or bounded_delete_limit between 1 and 10000)
);

insert into pipeline.retention_class_policies(
  class_key,object_scope,immutable,purge_allowed,default_retention_days,
  dry_run_required,bounded_delete_limit,post_delete_integrity_required,notes
) values
 ('regulatory_evidence','pipeline.evidence_artifacts',true,false,null,true,null,true,
  'Regulatory Evidence is normally immutable; no automated purge.'),
 ('accepted_source_versions','pipeline source/profile/version history',true,false,null,true,null,true,
  'Accepted source versions and provenance are retained.'),
 ('layer4_decisions','Layer 4 decision/audit ledgers',true,false,null,true,null,true,
  'Human intervention and supersession history are retained.'),
 ('publication_decisions','publication decision/audit ledgers',true,false,null,true,null,true,
  'Publication decisions are material audit records.'),
 ('material_audit','security/operations audit history',true,false,null,true,null,true,
  'Material audit records are retained.'),
 ('terminal_jobs','pipeline.jobs terminal operational rows',false,true,90,true,500,true,
  'Only terminal operational jobs may be considered; Evidence/history remain excluded.'),
 ('expired_queue_rows','bounded transient queues',false,true,30,true,500,true,
  'Only terminal/expired queue rows after ownership-specific integrity checks.'),
 ('stale_locks','transient locks/reservations',false,true,7,true,500,true,
  'Recovery must prove no active owner/heartbeat before deletion.'),
 ('cache_entries','rebuildable cache/projection entries',false,true,30,true,1000,true,
  'Only explicitly rebuildable cache state.'),
 ('temporary_staging','temporary staging rows',false,true,14,true,1000,true,
  'Only transient staging with no unresolved lineage dependency.'),
 ('bounded_operational_logs','non-material operational logs',false,true,90,true,1000,true,
  'Never includes security/material audit records.')
on conflict(class_key) do update set
  object_scope=excluded.object_scope,
  immutable=excluded.immutable,
  purge_allowed=excluded.purge_allowed,
  default_retention_days=excluded.default_retention_days,
  dry_run_required=excluded.dry_run_required,
  bounded_delete_limit=excluded.bounded_delete_limit,
  post_delete_integrity_required=excluded.post_delete_integrity_required,
  notes=excluded.notes,
  updated_at=now();

create table if not exists pipeline.platform_uat_catalogue (
  test_code text primary key,
  domain text not null,
  environment_scope text not null check (environment_scope in ('pilot','production','both')),
  gate_class text not null check (gate_class in ('permanent','production','maturity')),
  status text not null check (status in ('accepted_baseline','designed','not_run','pass','fail','blocked')),
  hard_gate boolean not null default false,
  evidence_ref text,
  description text not null,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  updated_at timestamptz not null default now()
);

insert into pipeline.platform_uat_catalogue(test_code,domain,environment_scope,gate_class,status,hard_gate,evidence_ref,description)
values
 ('M244-L1','Layer 1 operations','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-DQ','Data Quality/readiness','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-PERF','Performance/payload budgets','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-L2OPS','Layer 2 operations maturity','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-L2PLAT','Layer 2 platform/profile configuration','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-L2PROV','Layer 2 Provider operations','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-ADMINNAV','Administration navigation/deep links','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-COURSE','Course detail UX','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-STATE','Screen-state persistence','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-L3','Layer 3 operations/credentials','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-L4','Layer 4/cross-layer controls','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-NAV','Permanent Layer navigation','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-BLADES','Responsive detail blades','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-FIRECRAWL','Firecrawl/quota/background operation','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-EVIDENCE','Evidence type/screenshot integrity','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-PARENT','Parent run/operator progress','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-SCHOLAR','Scholarships','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-INSIGHTS','QILT/PRISMS contextual insights','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-FILTERS','Paged/stable filters','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-CONTACTS','International Provider contacts','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M244-RELEASE','Release notes','pilot','permanent','accepted_baseline',true,'33468512515','Accepted M2.4.4 permanent domain'),
 ('M25-COUNTRY-CANARY','Country Production canary','production','production','not_run',true,null,'Environment-specific source/capability enablement and rollback'),
 ('M25-STORAGE','Storage/capacity alerts','both','maturity','designed',true,null,'Capacity snapshot, thresholds and alert severity'),
 ('M25-RETENTION','Retention/purge dry-run','both','maturity','designed',true,null,'Immutable exclusions and bounded candidate reporting'),
 ('M25-SCRAPER','Scraper Production enablement','production','production','not_run',true,null,'Separate provider qualification and Production enablement'),
 ('M25-AI','AI Production enablement','production','production','not_run',true,null,'Separate task/model benchmark and Production enablement'),
 ('M25-LOAD','Serving vs ingestion workload','production','production','not_run',true,null,'Steady-state serving separated from bulk ingestion contention'),
 ('M25-CONCURRENT','Concurrent serving/admin/background','production','production','not_run',true,null,'Representative concurrent workload under unchanged hard budgets'),
 ('M25-RESTORE','Production restore/DR','production','production','not_run',true,null,'Backup/restore/DR proof before Production acceptance')
on conflict(test_code) do update set
  domain=excluded.domain,
  environment_scope=excluded.environment_scope,
  gate_class=excluded.gate_class,
  status=excluded.status,
  hard_gate=excluded.hard_gate,
  evidence_ref=excluded.evidence_ref,
  description=excluded.description,
  updated_at=now();

create table if not exists pipeline.performance_workload_profiles (
  profile_key text primary key,
  workload_class text not null,
  serving_traffic boolean not null,
  background_ingestion boolean not null,
  concurrent_admin_uat boolean not null,
  rpc_detail_budget_ms integer not null default 3000,
  management_payload_budget_bytes integer not null default 250000,
  filter_payload_budget_bytes integer not null default 60000,
  acquisition_on_read_allowed boolean not null default false,
  sizing_role text not null,
  notes text not null,
  change_control_ref text not null default 'CF-CHG-20260901-051',
  updated_at timestamptz not null default now(),
  check (rpc_detail_budget_ms <= 3000),
  check (management_payload_budget_bytes <= 250000),
  check (filter_payload_budget_bytes <= 60000),
  check (not acquisition_on_read_allowed)
);

insert into pipeline.performance_workload_profiles(
  profile_key,workload_class,serving_traffic,background_ingestion,concurrent_admin_uat,
  sizing_role,notes
) values
 ('consumer_read_steady_state','normal_api_serving',true,false,false,'primary_production_serving_baseline',
  'Read-heavy bounded Website/Zoho/API workload. Stable/reference data should be cached by consumers.'),
 ('scheduled_refresh','scheduled_background_refresh',true,true,false,'contention_profile',
  'Normal reads remain available while quota/concurrency-bounded refresh runs in background.'),
 ('bulk_reingestion','major_reingestion',false,true,false,'ingestion_capacity_profile_not_serving_baseline',
  'Heavy ingestion is measured independently and must not determine steady-state serving size by itself.'),
 ('concurrent_admin_uat','representative_concurrency',true,true,true,'production_acceptance_concurrency_profile',
  'Representative serving + Admin/UAT + background work under unchanged hard budgets.')
on conflict(profile_key) do update set
  workload_class=excluded.workload_class,
  serving_traffic=excluded.serving_traffic,
  background_ingestion=excluded.background_ingestion,
  concurrent_admin_uat=excluded.concurrent_admin_uat,
  sizing_role=excluded.sizing_role,
  notes=excluded.notes,
  updated_at=now();

create or replace function security.platform_capacity_snapshot_internal(p_environment text default 'pilot')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','storage','public'
as $$
declare
  v_db bigint;
  v_temp_bytes bigint;
  v_temp_files bigint;
  v_obj_count bigint;
  v_obj_bytes bigint;
  v_evidence_count bigint;
  v_orphans bigint;
  v_failed bigint;
  v_largest jsonb;
  v_evidence_policy jsonb;
  v_policy jsonb;
  v_severity text := 'ok';
begin
  if p_environment not in ('pilot','production') then
    raise exception 'invalid environment';
  end if;

  select pg_database_size(current_database()) into v_db;
  select coalesce(temp_bytes,0),coalesce(temp_files,0)
    into v_temp_bytes,v_temp_files
  from pg_stat_database where datname=current_database();

  select count(*),
         coalesce(sum(case when coalesce(metadata->>'size','') ~ '^[0-9]+$'
                           then (metadata->>'size')::bigint else 0 end),0)
    into v_obj_count,v_obj_bytes
  from storage.objects where bucket_id='evidence' and not is_delete_marker;

  select count(*) into v_evidence_count from pipeline.evidence_artifacts;

  select count(*) into v_orphans
  from storage.objects o
  where o.bucket_id='evidence'
    and not o.is_delete_marker
    and not exists (
      select 1 from pipeline.evidence_artifacts e
      where e.storage_path=o.name
         or e.storage_path=('evidence/'||o.name)
    );

  select count(*) into v_failed
  from pipeline.evidence_artifacts e
  where e.storage_path is not null
    and not exists (
      select 1 from storage.objects o
      where o.bucket_id='evidence'
        and not o.is_delete_marker
        and (o.name=e.storage_path or ('evidence/'||o.name)=e.storage_path)
    );

  select coalesce(jsonb_agg(jsonb_build_object(
           'schema',schema_name,'relation',relation_name,'bytes',total_bytes
         ) order by total_bytes desc),'[]'::jsonb)
  into v_largest
  from (
    select n.nspname schema_name,c.relname relation_name,pg_total_relation_size(c.oid) total_bytes
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind in ('r','m')
      and n.nspname not in ('pg_catalog','information_schema')
    order by total_bytes desc
    limit 10
  ) x;

  select coalesce(to_jsonb(p),'{}'::jsonb) into v_evidence_policy
  from pipeline.evidence_capacity_policy p where id=true;

  select coalesce(to_jsonb(p),'{}'::jsonb) into v_policy
  from pipeline.platform_capacity_policy p where environment=p_environment;

  if coalesce((v_policy->>'database_critical_bytes')::bigint,9223372036854775807) <= v_db
     or coalesce((v_policy->>'failed_orphan_upload_warn_count')::integer,1) <= greatest(v_orphans,v_failed)
  then v_severity:='critical';
  elsif coalesce((v_policy->>'database_high_bytes')::bigint,9223372036854775807) <= v_db
  then v_severity:='high';
  elsif coalesce((v_policy->>'database_warn_bytes')::bigint,9223372036854775807) <= v_db
  then v_severity:='warning';
  end if;

  return jsonb_build_object(
    'environment',p_environment,
    'observed_at',now(),
    'severity',v_severity,
    'database_bytes',v_db,
    'cumulative_temp_bytes',v_temp_bytes,
    'cumulative_temp_files',v_temp_files,
    'evidence_object_count',v_obj_count,
    'evidence_object_bytes',v_obj_bytes,
    'evidence_artifact_count',v_evidence_count,
    'orphan_object_count',v_orphans,
    'failed_upload_count',v_failed,
    'largest_relations',v_largest,
    'evidence_capacity_policy',v_evidence_policy,
    'platform_capacity_policy',v_policy,
    'backup_status','platform_api_required',
    'pitr_status','platform_api_required'
  );
end $$;

revoke all on function security.platform_capacity_snapshot_internal(text) from public,anon,authenticated;
grant execute on function security.platform_capacity_snapshot_internal(text) to service_role;

create or replace function security.platform_capacity_snapshot_read(p_environment text default 'pilot')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security'
as $$
declare v_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  return security.platform_capacity_snapshot_internal(p_environment);
end $$;

revoke all on function security.platform_capacity_snapshot_read(text) from public,anon;
grant execute on function security.platform_capacity_snapshot_read(text) to authenticated,service_role;

create or replace function public.svc_record_platform_capacity_observation(p_environment text default 'pilot')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare v jsonb; v_id bigint;
begin
  if current_user not in ('postgres','service_role') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  v:=security.platform_capacity_snapshot_internal(p_environment);
  insert into pipeline.platform_capacity_observations(
    environment,database_bytes,cumulative_temp_bytes,cumulative_temp_files,
    evidence_object_count,evidence_object_bytes,evidence_artifact_count,
    orphan_object_count,failed_upload_count,largest_relations,evidence_policy,
    backup_status,pitr_status
  ) values (
    p_environment,(v->>'database_bytes')::bigint,(v->>'cumulative_temp_bytes')::bigint,
    (v->>'cumulative_temp_files')::bigint,(v->>'evidence_object_count')::bigint,
    (v->>'evidence_object_bytes')::bigint,(v->>'evidence_artifact_count')::bigint,
    (v->>'orphan_object_count')::bigint,(v->>'failed_upload_count')::bigint,
    v->'largest_relations',v->'evidence_capacity_policy',
    v->>'backup_status',v->>'pitr_status'
  ) returning id into v_id;
  return jsonb_build_object('observation_id',v_id,'snapshot',v);
end $$;

revoke all on function public.svc_record_platform_capacity_observation(text) from public,anon,authenticated;
grant execute on function public.svc_record_platform_capacity_observation(text) to service_role;

create or replace function security.retention_dry_run_read(p_environment text default 'pilot')
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare v_rank integer; v_terminal bigint; v_immutable bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if p_environment not in ('pilot','production') then raise exception 'invalid environment'; end if;

  select count(*) into v_terminal
  from pipeline.jobs
  where status in ('completed','failed','cancelled')
    and coalesce(completed_at,created_at) < now()-interval '90 days';

  select count(*) into v_immutable
  from pipeline.retention_class_policies where immutable;

  return jsonb_build_object(
    'environment',p_environment,
    'mode','dry_run_only',
    'delete_performed',false,
    'terminal_job_candidates_older_than_90d',v_terminal,
    'immutable_policy_classes',v_immutable,
    'evidence_delete_candidates',0,
    'layer4_delete_candidates',0,
    'publication_audit_delete_candidates',0,
    'rule','Any future purge requires explicit class mapping, immutable exclusions, bounded delete and post-delete integrity verification.'
  );
end $$;

revoke all on function security.retention_dry_run_read(text) from public,anon;
grant execute on function security.retention_dry_run_read(text) to authenticated,service_role;

create or replace function security.m2_5_readiness_snapshot_read()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare v_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  return jsonb_build_object(
    'production_source_capabilities_enabled',
      (select count(*) from pipeline.environment_source_gates where environment='production' and enabled),
    'production_scrapers_enabled',
      (select count(*) from pipeline.layer2_provider_environment_gates where environment='production' and enabled),
    'production_ai_profiles_enabled',
      (select count(*) from pipeline.layer3_profile_environment_gates where environment='production' and enabled),
    'production_uat_open',
      (select count(*) from pipeline.platform_uat_catalogue
       where environment_scope in ('production','both') and hard_gate and status<>'pass'),
    'capacity',security.platform_capacity_snapshot_internal('pilot'),
    'retention_policy_classes',(select count(*) from pipeline.retention_class_policies),
    'performance_profiles',(select count(*) from pipeline.performance_workload_profiles),
    'current_layer2_wave',(
      select coalesce(to_jsonb(x),'{}'::jsonb)
      from (
        select id,status,country_code,scope_type,requested_wave_size,accepted_wave_size,
               schedule_remaining,total_items,dispatched_items,completed_items,failed_items,
               last_wave_at,updated_at
        from pipeline.layer2_scope_wave_requests
        order by created_at desc limit 1
      ) x
    )
  );
end $$;

revoke all on function security.m2_5_readiness_snapshot_read() from public,anon;
grant execute on function security.m2_5_readiness_snapshot_read() to authenticated,service_role;

-- Seed Pilot environment gates from currently configured providers/profiles without inferring qualification.
insert into pipeline.layer2_provider_environment_gates(
  acquisition_provider_id,environment,qualification_state,enabled,reason
)
select id,'pilot','registered',false,'M2.5 environment gate introduced; existing Pilot runtime qualification remains historical evidence until reconciled into this gate.'
from pipeline.layer2_acquisition_providers
on conflict(acquisition_provider_id,environment) do nothing;

insert into pipeline.layer3_profile_environment_gates(
  profile_id,environment,qualification_state,enabled,reason
)
select id,'pilot','registered',false,'M2.5 environment gate introduced; existing benchmark state remains historical evidence until reconciled into this gate.'
from pipeline.layer3_model_profiles
on conflict(profile_id,environment) do nothing;

-- Record the first Pilot observation. Production has no row because no Production project exists.
select public.svc_record_platform_capacity_observation('pilot');

-- Daily observation only. It is read/insert telemetry; it performs no purge or acquisition.
do $$
begin
  perform cron.unschedule(jobid)
  from cron.job where jobname='coursefinder-platform-capacity-observation';
  perform cron.schedule(
    'coursefinder-platform-capacity-observation',
    '12 4 * * *',
    $cmd$select public.svc_record_platform_capacity_observation('pilot');$cmd$
  );
end $$;

commit;
