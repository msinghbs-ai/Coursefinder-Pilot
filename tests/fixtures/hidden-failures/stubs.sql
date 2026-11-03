-- CF-247 Workstream F hidden failures and country settings (Platform Admin direction 3 Nov 2026 09:32 §5, §7): the tables and helpers the
-- 20261103140000 migration and the live definitions it edits read or write, on top of the pipeline-yield fixture database (integration-queue
-- stubs, migration 20261102120000, pipeline-yield stubs, migration 20261103040000). Columns as live (information_schema, production, read-only,
-- 3 Nov 2026 10:10-10:30 AEDT), the ones used here. Helpers the edited definitions call are small stand-ins. Nothing here is live data.
create schema if not exists ref; create schema if not exists ranking; create schema if not exists public;
do $$ begin create role service_role; exception when duplicate_object then null; end $$;
create function auth.role() returns text language sql stable as $f$ select 'service_role'::text $f$;

-- the task table, its events and the enrich items (the foreign keys are what the defect is about)
create table pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), kind text not null, lane text not null default 'default', state text not null default 'queued',
  title text, reason text, args jsonb not null default '{}', cursor jsonb, progress jsonb, result jsonb, error text, requested_by uuid, cancel_requested boolean not null default false,
  pause_requested boolean not null default false, created_at timestamptz not null default now(), started_at timestamptz, finished_at timestamptz, updated_at timestamptz not null default now());
create unique index admin_jobs_governed_idempotency_uq on pipeline.admin_jobs ((args->>'idempotency_key')) where kind = 'governed_action';
create table pipeline.admin_job_events(id bigserial primary key, job_id uuid not null references pipeline.admin_jobs(id) on delete cascade, note text, detail jsonb, at timestamptz default now());
create table pipeline.admin_job_items(id bigserial primary key, job_id uuid references pipeline.admin_jobs(id) on delete cascade, kind text, outcome text);
alter table pipeline.field_enrich_items add column job_id uuid references pipeline.admin_jobs(id) on delete cascade, add column field text, add column source text,
  add column tried text[] not null default '{}', add column value jsonb, add column quote text, add column reason text, add column evidence_id uuid, add column storage_path text,
  add column attempts int not null default 0, add column cost_usd numeric, add column created_at timestamptz not null default now(), add column updated_at timestamptz not null default now();
create function security.admin_job_close_v1(p_id uuid) returns void language sql as $f$ select null::void $f$;
create function security.firecrawl_setting(p_key text) returns jsonb language sql stable as $f$ select null::jsonb $f$;
create table fx.fired(id bigserial primary key, what text, body jsonb, at timestamptz default clock_timestamp());
create function security.enrich_ai_fire_v1() returns int language sql as $f$ insert into fx.fired(what) values ('enrich_ai') returning 1 $f$;
create function security.enrich_campus_link_v1(p_id uuid) returns void language sql as $f$ select null::void $f$;
create table search.refresh_requests(id bigserial primary key, requested_by text, at timestamptz default now());
create table pipeline.firecrawl_runs(id uuid primary key, status text, done int, items int, credits_used int);
create table ref.countries(id uuid primary key, iso_alpha2 text, scholarship_ingestion_enabled boolean default true);

-- the job submitter (records the call instead of an HTTP request)
create function pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb default '{}'::jsonb) returns bigint language sql as
  $f$ insert into fx.fired(what, body) values (p_function, p_body) returning id $f$;

-- NZ Code of Practice picker: the evidence of the NZQA register reader and the reads already done
create table pipeline.sources(id uuid primary key default gen_random_uuid(), url text, provider_id uuid);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), source_id uuid, evidence_type text, storage_path text, captured_at timestamptz default now(),
  created_at timestamptz default now());
create table pipeline.nz_cop_reads(path text primary key, error text, reader text, read_at timestamptz default now());

-- CRICOS contact
create table catalogue.provider_registrations(provider_id uuid, registration_scheme text, registration_code text);
create table pipeline.provider_contact_checks(provider_id uuid, kind text, checked_at timestamptz, outcome text, primary key (provider_id, kind));

-- focus providers and their helpers
create table pipeline.enrich_focus_providers(provider_id uuid primary key, rank int, gaps int, in_focus boolean, set_at timestamptz);
create table pipeline.adapter_builds(provider_id uuid, wave text);
create table fx.country(provider_id uuid primary key, cc text);
create function security.coverage_country(p uuid) returns text language sql stable as $f$ select cc from fx.country where provider_id = p $f$;
create function security.flag_provider_held_v1(p uuid, p_codes text[]) returns boolean language sql stable as $f$ select false $f$;

-- scholarship refill and its helpers (the eligibility and tier rules are not under test: stand-ins say yes, tier 1)
create table pipeline.coverage_provider_discovery(provider_id uuid primary key, website text, status text);
alter table pipeline.scholarship_discovery_providers add column next_discover_at timestamptz;
create function security.provider_sch_search_auto_v1() returns int language sql as $f$ select 0 $f$;
create function security.fc_sch_eligible_v1(p uuid) returns boolean language sql stable as $f$ select true $f$;
create function security.third_party_host_v1(p text) returns boolean language sql stable as $f$ select false $f$;
create function security.provider_sch_search_off_v1(p uuid) returns boolean language sql stable as $f$ select false $f$;
create table fx.admission_ok(provider_id uuid primary key);
create function security.scholarship_admission_provider_ok_v1(p uuid) returns boolean language sql stable as $f$ select exists (select 1 from fx.admission_ok a where a.provider_id = p) $f$;
create function security.fc_provider_tier_v1(p uuid) returns int language sql stable as $f$ select 1 $f$;
create function security.scholarship_pilot_start_v1() returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create function security.scholarship_discovery_tier_refresh_v1(n int) returns int language sql as $f$ select 0 $f$;
create function security.scholarship_candidate_skip_v1(p uuid, n int) returns int language sql as $f$ select 0 $f$;
create function security.scholarship_round_state_refresh_v1(n int) returns int language sql as $f$ select 0 $f$;

-- country scope gate (the live gate is not under test: the stand-in reports the country it was asked for)
create function security.country_scope_gate_v1(p_apply boolean default true, p_country text default 'CA') returns jsonb language sql as
  $f$ insert into fx.fired(what, body) values ('country_scope_gate', jsonb_build_object('country', p_country)) returning jsonb_build_object('country', p_country) $f$;

-- course link search: the picker's day count and the person-task bypass
create table pipeline.course_link_search(id bigserial primary key, provider_id uuid, course_id uuid, state text, sent_at timestamptz, queued_at timestamptz default now());
create function security.course_link_search_eligible_v1() returns table(provider_id uuid, course_id uuid) language sql stable as $f$ select null::uuid, null::uuid where false $f$;
create function security.link_search_person_task_v1(p uuid, c uuid) returns boolean language sql stable as $f$ select false $f$;

-- rankings (live columns used)
create table ranking.systems(id uuid primary key default gen_random_uuid(), code text unique, publisher_name text, ranking_name text, official_url text, active boolean default true);
create table ranking.editions(id uuid primary key default gen_random_uuid(), system_id uuid, edition_year int, status text, retrieved_at timestamptz);
create table ranking.manual_imports(id uuid primary key default gen_random_uuid(), system_id uuid, edition_year int, status text, uploaded_at timestamptz);

-- settings the edited definitions read (live values, 3 Nov 2026, except enrich.focus_top_n: 2 here, so three Australian providers show the rule)
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
  ('pipeline', 'enrich.focus_top_n', 'number', '2'), ('pipeline', 'search.daily_picked_cap', 'number', '200'), ('pipeline', 'recheck.cricos_contact_days', 'number', '180')
on conflict do nothing;
