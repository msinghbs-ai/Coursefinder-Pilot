create table integration.systems (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  system_type text not null,
  base_url text,
  status text not null default 'active',
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table integration.extraction_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  domain text not null,
  country_id uuid references ref.countries(id),
  provider_id uuid references catalogue.providers(id),
  version text not null,
  config jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table integration.model_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  purpose text not null,
  provider_name text not null,
  model_name text not null,
  dimensions int,
  config jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  created_at timestamptz not null default now()
);

create table pipeline.sources (
  id uuid primary key default extensions.gen_random_uuid(),
  source_type text not null,
  system_id uuid references integration.systems(id),
  provider_id uuid references catalogue.providers(id),
  country_id uuid references ref.countries(id),
  url text,
  label text,
  trust_rank smallint not null default 50,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pipeline_sources_provider_idx on pipeline.sources(provider_id,status);

create table pipeline.acquisition_policies (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  country_id uuid references ref.countries(id),
  provider_id uuid references catalogue.providers(id),
  domain text not null,
  priority int not null default 100,
  scraper_order jsonb not null default '[]'::jsonb,
  extraction_profile_id uuid references integration.extraction_profiles(id),
  model_profile_id uuid references integration.model_profiles(id),
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table pipeline.jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  job_type text not null,
  domain text,
  source_id uuid references pipeline.sources(id),
  provider_id uuid references catalogue.providers(id),
  entity_id uuid references pim.entity_registry(id),
  status text not null default 'queued',
  requested_by uuid references auth.users(id),
  started_at timestamptz,
  completed_at timestamptz,
  attempt_count int not null default 0,
  payload jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  error_text text,
  created_at timestamptz not null default now()
);
create index pipeline_jobs_status_idx on pipeline.jobs(status,created_at);
create index pipeline_jobs_entity_idx on pipeline.jobs(entity_id);

create table pipeline.evidence_artifacts (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_id uuid references pim.entity_registry(id),
  source_id uuid references pipeline.sources(id),
  job_id uuid references pipeline.jobs(id),
  evidence_type text not null,
  source_url text,
  storage_path text,
  content_hash text,
  mime_type text,
  captured_at timestamptz not null default now(),
  valid_from timestamptz,
  valid_to timestamptz,
  supersedes_evidence_id uuid references pipeline.evidence_artifacts(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index evidence_entity_idx on pipeline.evidence_artifacts(entity_id,captured_at desc);
create index evidence_source_idx on pipeline.evidence_artifacts(source_id);
create index evidence_supersedes_idx on pipeline.evidence_artifacts(supersedes_evidence_id);

create table pipeline.claims (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  field_code text not null,
  value_json jsonb not null,
  source_id uuid references pipeline.sources(id),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  layer smallint not null check (layer between 1 and 4),
  confidence numeric(5,4),
  status text not null default 'candidate',
  created_at timestamptz not null default now()
);
create index claims_entity_field_idx on pipeline.claims(entity_id,field_code,status);

revoke all on all tables in schema integration from anon, authenticated;
revoke all on all tables in schema pipeline from anon, authenticated;
revoke usage on schema integration from anon, authenticated;
revoke usage on schema pipeline from anon, authenticated;
grant usage on schema integration,pipeline to service_role;
grant all on all tables in schema integration,pipeline to service_role;
