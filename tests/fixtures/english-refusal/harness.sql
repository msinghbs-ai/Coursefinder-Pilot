-- Labelled stand-ins (NOT production objects) for what the functions under test name but the English path manifest does not capture.
-- Everything the tests assert on (pipeline.provider_fact_sources, platform_toolset_settings, pipeline_num_v1, providers, courses, countries) comes from the production manifest.
insert into pipeline.platform_toolsets(key) values ('pipeline') on conflict do nothing;  -- the parent row of the settings foreign key
create table if not exists pipeline.coverage_admission_countries (country_id uuid, currency_code text);
create or replace view security.provider_hidden_v1 as select null::uuid as provider_id where false;
create or replace function security.tuition_chase_enabled(uuid) returns boolean language sql stable as $$ select false $$;
-- scholarship queue and read requests: the columns svc_scholarship_ai_record's retry branch reads and writes (live column list)
create table if not exists pipeline.scholarship_ai_queue (id bigserial primary key, model_code text, prompt_version text, run_kind text, job_id bigint, sample_id bigint, candidate_id bigint,
  scholarship_id uuid, provider_id uuid, url text, state text not null default 'queued', attempts int not null default 0, leased_until timestamptz, next_try_at timestamptz not null default now(),
  created_at timestamptz not null default now(), done_at timestamptz, extraction_id bigint, step int not null default 1, storage_path text, root_id bigint, skip_reason text, fresh_read boolean not null default false, read_request_id bigint);
create table if not exists pipeline.scholarship_read_requests (id bigserial primary key, state text not null default 'queued', finished_at timestamptz, outcome jsonb);
-- the picker orders by a provider's active course count: columns of catalogue.courses the English-path manifest does not capture
alter table catalogue.courses add column if not exists provider_id uuid;
alter table catalogue.courses add column if not exists lifecycle_status text;
alter table catalogue.providers add column if not exists country_id uuid;
