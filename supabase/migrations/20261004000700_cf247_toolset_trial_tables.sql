-- CF-247 Decision 252: trial tables only (part 1 of the trials change; functions follow in part 2).
create table if not exists pipeline.toolset_trial_runs (
  id uuid primary key default gen_random_uuid(),
  toolset_key text not null references pipeline.platform_toolsets(key),
  purpose text not null check (purpose in ('find_course_page', 'find_provider_site', 'render_page')),
  countries text[] not null,
  settings jsonb not null,
  status text not null default 'ready' check (status in ('ready', 'running', 'paused_time_limit', 'done', 'stopped', 'stopped_credit_cap', 'stopped_vendor_limit')),
  status_note text,
  credits_used numeric not null default 0,
  reason text not null,
  requested_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz
);
create table if not exists pipeline.toolset_trial_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references pipeline.toolset_trial_runs(id),
  country text not null,
  subject_key text not null,
  course_id uuid,
  provider_id uuid,
  input jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'leased', 'done')),
  leased_until timestamptz,
  outcome text,
  http_status int,
  credits numeric,
  latency_ms int,
  result jsonb,
  done_at timestamptz,
  unique (run_id, subject_key)
);
create index if not exists toolset_trial_items_run on pipeline.toolset_trial_items(run_id, status);
create index if not exists toolset_trial_items_subject on pipeline.toolset_trial_items(subject_key);
alter table pipeline.toolset_trial_runs enable row level security;
alter table pipeline.toolset_trial_items enable row level security;
revoke all on pipeline.toolset_trial_runs, pipeline.toolset_trial_items from anon, authenticated;
