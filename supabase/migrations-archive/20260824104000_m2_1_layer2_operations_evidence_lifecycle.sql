-- CF-CHG-20260823-029
-- Layer 2 management policy / run / Evidence lifecycle foundation.
-- Live migration: m2_1_layer2_operations_evidence_lifecycle

create table if not exists pipeline.layer2_execution_policies (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references pipeline.layer2_source_profiles(id) on delete cascade,
  schedule_mode text not null default 'manual' check (schedule_mode in ('manual','daily','weekly','disabled')),
  scheduled_hour_utc smallint null check (scheduled_hour_utc between 0 and 23),
  batch_size integer not null default 10 check (batch_size between 1 and 500),
  routing_strategy text not null default 'direct_then_best_value' check (routing_strategy in ('direct_then_best_value','lowest_cost_proven','highest_success','manual_provider')),
  max_paid_attempts_per_entity smallint not null default 2 check (max_paid_attempts_per_entity between 0 and 5),
  max_vendor_units_per_entity numeric null check (max_vendor_units_per_entity is null or max_vendor_units_per_entity >= 0),
  max_cost_usd_per_entity numeric null check (max_cost_usd_per_entity is null or max_cost_usd_per_entity >= 0),
  auto_handoff_layer3 boolean not null default true,
  stop_on_identity_mismatch boolean not null default true,
  enabled boolean not null default true,
  next_run_at timestamptz null,
  last_run_at timestamptz null,
  updated_by uuid null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists pipeline.layer2_run_batches (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer2_source_profiles(id),
  profile_version_id uuid not null references pipeline.layer2_source_profile_versions(id),
  trigger_type text not null default 'manual' check (trigger_type in ('manual','schedule','trial','resume')),
  status text not null default 'queued' check (status in ('queued','running','completed','partial','failed','cancelled')),
  requested_by uuid null,
  policy_snapshot jsonb not null default '{}'::jsonb,
  target_count integer not null default 0,
  processed_count integer not null default 0,
  resolved_l2_count integer not null default 0,
  escalated_l3_count integer not null default 0,
  blocked_count integer not null default 0,
  vendor_units numeric not null default 0,
  vendor_cost_usd numeric not null default 0,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now()
);

create table if not exists pipeline.layer2_run_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references pipeline.layer2_run_batches(id) on delete cascade,
  entity_type text not null check (entity_type in ('course','scholarship')),
  entity_id uuid null,
  source_url text null,
  status text not null default 'queued' check (status in ('queued','discovering','acquiring','extracting','resolved_l2','layer3_required','blocked','cancelled')),
  selected_provider_id uuid null references pipeline.layer2_acquisition_providers(id),
  job_id uuid null references pipeline.jobs(id),
  evidence_count integer not null default 0,
  fields_targeted integer not null default 0,
  fields_resolved integer not null default 0,
  vendor_units numeric not null default 0,
  vendor_cost_usd numeric not null default 0,
  blocker text null,
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now()
);

alter table pipeline.layer2_provider_attempts
  add column if not exists runtime_platform text null,
  add column if not exists runtime_region text null,
  add column if not exists runtime_execution_id text null,
  add column if not exists runtime_deployment_id text null,
  add column if not exists egress_identity text null;

alter table pipeline.evidence_artifacts
  add column if not exists retention_class text,
  add column if not exists retain_until timestamptz,
  add column if not exists review_state text,
  add column if not exists capture_version integer,
  add column if not exists evidence_group_key text;

update pipeline.evidence_artifacts
set retention_class=coalesce(retention_class,case when coalesce(metadata->>'layer','')='2' then 'standard_365' else 'legacy' end),
    review_state=coalesce(review_state,'unreviewed')
where retention_class is null or review_state is null;

create index if not exists layer2_policy_schedule_idx on pipeline.layer2_execution_policies(enabled,schedule_mode,next_run_at);
create index if not exists layer2_batches_profile_created_idx on pipeline.layer2_run_batches(profile_id,created_at desc);
create index if not exists layer2_items_batch_status_idx on pipeline.layer2_run_items(batch_id,status,created_at);
create index if not exists layer2_evidence_review_idx on pipeline.evidence_artifacts(retention_class,review_state,captured_at desc) where retention_class is not null;
create index if not exists layer2_evidence_group_version_idx on pipeline.evidence_artifacts(evidence_group_key,capture_version desc) where evidence_group_key is not null;

alter table pipeline.layer2_execution_policies enable row level security;
alter table pipeline.layer2_run_batches enable row level security;
alter table pipeline.layer2_run_items enable row level security;
revoke all on pipeline.layer2_execution_policies,pipeline.layer2_run_batches,pipeline.layer2_run_items from anon,authenticated;
grant select,insert,update,delete on pipeline.layer2_execution_policies,pipeline.layer2_run_batches,pipeline.layer2_run_items to service_role;

insert into pipeline.layer2_execution_policies(profile_id,schedule_mode,batch_size,routing_strategy,max_paid_attempts_per_entity,auto_handoff_layer3,stop_on_identity_mismatch)
select p.id,'manual',10,'direct_then_best_value',2,true,true
from pipeline.layer2_source_profiles p
where p.enabled=true and p.domain in ('course_facts','scholarship')
on conflict(profile_id) do nothing;

-- Admin reads and policy mutation are installed by the corresponding live migration.
-- Kept intentionally behind security.admin_layer2_ops_read and public.layer2_ops_policy_update.
