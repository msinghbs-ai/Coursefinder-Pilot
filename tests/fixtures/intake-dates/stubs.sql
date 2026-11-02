-- Intake dates fixtures: what the intake-dates migration needs beyond the E16 fixture database (CF-247, Platform Admin 2 Nov 2026 11:10 §2).
-- Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is a copy of live data.
-- The live catalogue.course_intakes columns (read 2 Nov 2026): id, course_id, intake_year, intake_label, start_date, application_deadline,
-- campus_id, status, source_id, evidence_id, confidence, source_intake_key; unique (course_id, source_id, source_intake_key) where both set.
alter table catalogue.course_intakes add column evidence_id uuid, add column confidence numeric, add column source_intake_key text;
create unique index course_intakes_source_identity_uidx on catalogue.course_intakes (course_id, source_id, source_intake_key)
  where source_id is not null and source_intake_key is not null;

-- the two live triggers on catalogue.course_intakes, rebuilt from this repository by run.sh (same-month guard; manual lock guard)

-- admission rule per country (security.coverage_apply_course_v1 joins it)
create table pipeline.coverage_admission_countries(country_id uuid, active boolean, currency_code text);
create function security.fee_below_floor_v1(p_course uuid, p_amount numeric, p_basis text) returns numeric language sql as $f$ select null::numeric $f$;
create function security.coverage_identity_allowed(p_provider uuid, p_basis text, p_field text) returns boolean language sql as $f$ select true $f$;

-- the approved calendars (live shape: pipeline.provider_policy_proposals, archive 20261002183000)
create table pipeline.provider_policy_proposals (
  id uuid primary key default gen_random_uuid(), provider_id uuid not null, fact_source_id uuid, kind text not null, parser text not null, content_hash text,
  evidence_id uuid, url text, style text, proposal jsonb not null, status text not null default 'proposed', decided_by uuid, decided_at timestamptz,
  decision_note text, apply_summary jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now());

-- jobs (G1) and pg_cron, as far as the migration uses them
create table pipeline.automation_catalogue(jobname text primary key, area text, sort int, label text, description text, control_rank int, batch_editable boolean, layer23_stage text);
create schema if not exists cron;
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $f$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $f$;
create function cron.alter_job(job_id bigint, active boolean) returns void language sql as $f$ update cron.job set active = $2 where jobid = $1 $f$;

-- the full projection is stood in for by the live core projection (run in the fixtures); the apply's own refresh call is recorded here
create table public.fixture_refresh_calls(course_ids uuid[], at timestamptz default now());
create or replace function search.refresh_course_enrichment_scoped_v1(p_ids uuid[], p_apply boolean) returns jsonb language sql as
  $f$ insert into public.fixture_refresh_calls(course_ids) values (p_ids) returning jsonb_build_object('courses', cardinality(p_ids)) $f$;

-- the intake columns of search.course_documents the projection writes and the consumer API reads (live names and types)
alter table search.course_documents add column intake_options jsonb not null default '[]'::jsonb, add column earliest_intake_date date, add column has_intake boolean;
-- the consumer API's month helper, as created 8 Oct 2026 (archive 20261008032806)
create schema if not exists api;
create or replace function api.website_v2_label_month(p_label text)
returns int language sql immutable set search_path to 'pg_catalog' as $$
  select m.n from (values (1,'jan'),(2,'feb'),(3,'mar'),(4,'apr'),(5,'may'),(6,'jun'),(7,'jul'),(8,'aug'),(9,'sep'),(10,'oct'),(11,'nov'),(12,'dec')) m(n,k)
  where strpos(lower(coalesce(p_label,'')), m.k) > 0
  order by strpos(lower(p_label), m.k) limit 1
$$;
