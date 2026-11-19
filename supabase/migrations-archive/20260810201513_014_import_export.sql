create table workflow.import_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  file_name text,
  storage_path text,
  import_type text not null,
  status text not null default 'uploaded',
  requested_by uuid references auth.users(id),
  total_rows int not null default 0,
  valid_rows int not null default 0,
  error_rows int not null default 0,
  inserted_rows int not null default 0,
  updated_rows int not null default 0,
  conflict_rows int not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table workflow.import_rows (
  id uuid primary key default extensions.gen_random_uuid(),
  import_job_id uuid not null references workflow.import_jobs(id) on delete cascade,
  sheet_name text,
  row_number int not null,
  business_key text,
  payload jsonb not null,
  validation_status text not null default 'pending',
  action text,
  target_entity_id uuid references pim.entity_registry(id),
  validation_messages jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique(import_job_id,sheet_name,row_number)
);
create index import_rows_job_status_idx on workflow.import_rows(import_job_id,validation_status);
create index import_rows_business_key_idx on workflow.import_rows(business_key);

create table workflow.import_errors (
  id uuid primary key default extensions.gen_random_uuid(),
  import_job_id uuid not null references workflow.import_jobs(id) on delete cascade,
  import_row_id uuid references workflow.import_rows(id) on delete cascade,
  error_code text not null,
  field_name text,
  message text not null,
  severity text not null default 'error',
  created_at timestamptz not null default now()
);
create index import_errors_job_idx on workflow.import_errors(import_job_id,severity);

create table workflow.export_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  export_type text not null,
  filters jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  requested_by uuid references auth.users(id),
  storage_path text,
  row_count bigint,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
