create table if not exists pipeline.layer2_provider_benchmark_observations (
  id uuid primary key default gen_random_uuid(),
  benchmark_ref text not null,
  country_code text not null,
  university_label text,
  course_key text,
  source_profile_id uuid not null references pipeline.layer2_source_profiles(id),
  acquisition_provider_id uuid not null references pipeline.layer2_acquisition_providers(id),
  request_id bigint,
  target_url text not null,
  http_status integer,
  response_bytes bigint,
  vendor_units numeric,
  body_sha256 text,
  identity_marker_present boolean,
  fee_marker_present boolean,
  english_marker_present boolean,
  intake_marker_present boolean,
  rate_limited boolean not null default false,
  evidence_retention_mode text not null default 'probe_hash_only' check (evidence_retention_mode in ('probe_hash_only','native_evidence_retained')),
  notes jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  change_control_ref text not null default 'CF-CHG-20260823-029'
);
alter table pipeline.layer2_provider_benchmark_observations enable row level security;
revoke all on pipeline.layer2_provider_benchmark_observations from anon, authenticated;
grant select,insert,update,delete on pipeline.layer2_provider_benchmark_observations to service_role;
create index if not exists layer2_provider_benchmark_provider_idx on pipeline.layer2_provider_benchmark_observations(acquisition_provider_id,observed_at desc);
create index if not exists layer2_provider_benchmark_profile_idx on pipeline.layer2_provider_benchmark_observations(source_profile_id,observed_at desc);
create unique index if not exists layer2_provider_benchmark_request_uq on pipeline.layer2_provider_benchmark_observations(request_id) where request_id is not null;
