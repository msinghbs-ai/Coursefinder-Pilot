create table workflow.migration_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  source_environment text not null,
  source_project_ref text,
  migration_scope text not null,
  status text not null default 'planned',
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  notes text,
  metrics jsonb not null default '{}'::jsonb
);

create table workflow.migration_entity_map (
  id uuid primary key default extensions.gen_random_uuid(),
  migration_run_id uuid not null references workflow.migration_runs(id) on delete cascade,
  entity_type text not null,
  source_id text,
  source_stable_key text,
  target_entity_id uuid references pim.entity_registry(id),
  target_stable_key text,
  action text not null,
  status text not null default 'pending',
  notes text,
  created_at timestamptz not null default now()
);
create index migration_entity_map_run_idx on workflow.migration_entity_map(migration_run_id,entity_type,status);
create unique index migration_entity_map_key_idx on workflow.migration_entity_map(migration_run_id,entity_type,coalesce(source_stable_key,source_id));

create table workflow.reconciliation_checks (
  id uuid primary key default extensions.gen_random_uuid(),
  migration_run_id uuid not null references workflow.migration_runs(id) on delete cascade,
  check_code text not null,
  entity_type text,
  expected_value jsonb,
  actual_value jsonb,
  status text not null default 'pending',
  checked_at timestamptz,
  notes text,
  unique(migration_run_id,check_code,entity_type)
);

create table workflow.handover_events (
  id uuid primary key default extensions.gen_random_uuid(),
  event_type text not null,
  environment text not null,
  project_ref text,
  details jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  recorded_by uuid references auth.users(id)
);

insert into workflow.handover_events(event_type,environment,project_ref,details)
values('environment_created','pilot_mumbai','fxcwkweaxjtknorudmwp',jsonb_build_object('region','ap-south-1','project_name','coursefinder_Pilot','schema_version','v2.9.1'));
