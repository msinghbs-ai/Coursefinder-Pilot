-- CF-247 P0 workstream A (operations controller) on isolated fixtures: the live shapes this change reads or guards, beyond the integration
-- queue stubs (../integration-queue/stubs.sql). Columns read from information_schema on production (read-only, 3 Nov 2026 15:43-15:47 AEDT).
-- Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is live data.
create schema if not exists scholarship;

-- tasks (live columns; state check as live)
create table pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), kind text not null, lane text, state text not null default 'queued'
  check (state = any (array['queued', 'running', 'paused', 'done', 'failed', 'cancelled'])), title text, args jsonb not null default '{}', cursor jsonb,
  progress jsonb, result jsonb, error text, cancel_requested boolean not null default false, pause_requested boolean not null default false, requested_by uuid,
  reason text, created_at timestamptz not null default now(), started_at timestamptz, updated_at timestamptz not null default now(), finished_at timestamptz, scope text);

-- manual locks (live columns: 7,561 rows on 3 Nov)
create table pipeline.manual_locks(entity text not null, entity_id uuid not null, field text not null, mode text, set_by uuid, set_at timestamptz not null default now(),
  primary key (entity, entity_id, field));

-- Layer 4 decisions and automatic admissions (the columns written here)
create table pipeline.layer4_decisions(id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb,
  proposed_value jsonb, final_value jsonb, evidence_id uuid, layer2_state jsonb, layer3_state jsonb, scalar_resolution_id uuid, change_control_ref text, created_at timestamptz not null default now());
create table pipeline.layer4_auto_admissions(id bigserial primary key, review_item_id uuid, at timestamptz not null default now(), detail jsonb);

-- paid-service limits (Firecrawl's monthly limit and reserve live in billing_config)
create table pipeline.layer2_acquisition_providers(id uuid primary key default gen_random_uuid(), provider_key text unique not null, enabled boolean not null default true,
  concurrency int, rate_limit_per_minute int, billing_config jsonb, updated_at timestamptz not null default now());

-- what the report reads (live columns)
create table pipeline.mode_outcome_ledger(id bigserial primary key, run_at timestamptz not null default now(), mode text, status int, ms int, items int, ok int, failed int,
  wait_ms int, landed jsonb, worker text, detail jsonb, outcome text, lane_outcome text, hold_reason text);
create table pipeline.gap_cause_snapshots(at timestamptz not null, country_code text not null, attribute text not null, cause text not null, action text, automatic boolean,
  courses int, primary key (at, country_code, attribute, cause));
create table pipeline.course_page_proofs(course_id uuid primary key, page_key text, proven boolean, checked_at timestamptz);
create table scholarship.scholarships(id uuid primary key default gen_random_uuid(), provider_id uuid, name text, publication_status text, lifecycle_status text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table pipeline.field_enrich_items add column if not exists field text, add column if not exists reason text, add column if not exists cost_usd numeric,
  add column if not exists created_at timestamptz not null default now(), add column if not exists updated_at timestamptz not null default now();
