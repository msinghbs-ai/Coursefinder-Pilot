-- CF-247 integration queue (continuous validation mandate, Platform Admin 2 Nov 2026 16:58): isolated fixture database. Run on a scratch
-- PostgreSQL only (never on a Supabase project): see run.sh. The tables the 20261102120000 migration reads or writes, with their live columns
-- (read from information_schema on production, read-only, 2 Nov 2026 17:06-17:08 AEDT), and the helpers it calls as small stand-ins.
-- The alert path (security.platform_alerts_add_v1, security.platform_alerts_evaluate_v1) is loaded by run.sh from the repository migration
-- 20261031091000 and checked against the live md5s. Nothing here is live data.
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists cron; create schema if not exists search; create schema if not exists net; create schema if not exists supabase_migrations;
create schema if not exists fx;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create extension if not exists pgcrypto;

-- who is calling (the screen's role check)
create table fx.caller(id int primary key default 1, uid uuid, rank int);
insert into fx.caller values (1, null, null);
create function auth.uid() returns uuid language sql stable as $f$ select uid from fx.caller where id = 1 $f$;
create function security.current_role_rank() returns int language sql stable as $f$ select rank from fx.caller where id = 1 $f$;

-- settings (G2): live columns
create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, label text, help text, kind text, value jsonb, min_value numeric,
  max_value numeric, unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $f$;
-- live values read 2 Nov 2026 (alerts on, critical only; Firecrawl daily budget off under the 16:39 authority; AI ceiling US$14)
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
  ('pipeline', 'alerts.delivery_enabled', 'boolean', 'true'), ('pipeline', 'alerts.min_severity', 'number', '3'), ('pipeline', 'alerts.confirm_minutes', 'number', '15'),
  ('pipeline', 'alerts.cooldown_minutes', 'number', '60'), ('pipeline', 'alerts.reminder_hours', 'number', '12'), ('pipeline', 'alerts.recovery_notice', 'boolean', 'true'),
  ('pipeline', 'alerts.webhook_enabled', 'boolean', 'false'), ('pipeline', 'alerts.test_mode', 'boolean', 'false'),
  ('pipeline', 'budgets.ai_daily_ceiling_usd', 'number', '14'), ('firecrawl', 'daily_budget_on', 'boolean', 'false'), ('firecrawl', 'daily_budget_total', 'number', '25000');

-- audit, catalogue, register (live columns)
create table pipeline.admin_control_events(id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb,
  actor uuid, created_at timestamptz not null default now());
create table pipeline.automation_catalogue(jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register(kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, last_used_at timestamptz, usage jsonb not null default '{}'::jsonb,
  size_bytes bigint, note text, registered_at timestamptz not null default now(), updated_at timestamptz not null default now(), primary key (kind, name));

-- scheduler (pg_cron's columns used here)
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean not null default true);
create table cron.job_run_details(runid bigserial primary key, jobid bigint, status text, return_message text, start_time timestamptz, end_time timestamptz);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as
  $f$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $f$;
create function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
returns void language sql as $f$ update cron.job set schedule = coalesce(alter_job.schedule, cron.job.schedule), command = coalesce(alter_job.command, cron.job.command),
  active = coalesce(alter_job.active, cron.job.active) where jobid = job_id $f$;
create table net._http_response(id bigint primary key, status_code int, content text, timed_out boolean, error_msg text, created timestamptz not null default now());
create table supabase_migrations.schema_migrations(version text primary key, statements text[], name text, created_by text, idempotency_key text, rollback text[]);

-- Platform health issues and the alert outbox (live columns; outbox as created by 20261031091000)
create table pipeline.platform_issues(id uuid primary key default gen_random_uuid(), check_key text not null, severity text not null, area text not null, title text not null,
  detail jsonb not null default '{}'::jsonb, first_seen timestamptz not null default now(), last_seen timestamptz not null default now(), occurrences int not null default 1,
  resolved_at timestamptz, acknowledged_by uuid, acknowledged_at timestamptz, acknowledged_note text);
create unique index platform_issues_open_uq on pipeline.platform_issues (check_key) where resolved_at is null;
create table pipeline.platform_alerts (id bigserial primary key, issue_id uuid references pipeline.platform_issues(id) on delete set null, check_key text not null,
  kind text not null check (kind in ('raised', 'escalated', 'reminder', 'recovered', 'test')), severity text not null check (severity in ('critical', 'warning', 'info')),
  title text not null, body text not null, status text not null check (status in ('held', 'pending', 'sending', 'sent', 'failed')), attempts int not null default 0,
  next_attempt_at timestamptz not null default now(), lease_until timestamptz, sent_via text, sent_at timestamptz, net_request_id bigint, last_error text,
  dedupe_key text not null unique, created_at timestamptz not null default now());
create function security.platform_alerts_webhook_v1() returns jsonb language sql as $f$ select '{}'::jsonb $f$;

-- catalogue and search (live columns)
create table catalogue.providers(id uuid primary key, stable_key text not null, canonical_name text not null, display_name text, short_name text, country_id uuid not null,
  subdivision_id uuid, provider_type_id uuid, website text, description text, primary_city text, address_line1 text, address_line2 text, postcode text, latitude numeric,
  longitude numeric, phone text, email text, logo_url text, established_year smallint, lifecycle_status text not null default 'active', publication_status text not null default 'published',
  canonical_source_id uuid, last_verified_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), enrols_international boolean,
  enrols_international_basis text, provider_type_basis text, provider_type_set_at timestamptz);
create table catalogue.courses(id uuid primary key, stable_key text not null, provider_id uuid not null, canonical_title text not null, display_title text, course_code text,
  source_version text, study_level_id uuid, primary_field_id uuid, description text, course_url text, duration_value numeric, duration_unit text, delivery_mode text,
  lifecycle_status text not null default 'active', publication_status text not null default 'unpublished', canonical_source_id uuid, last_verified_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), open_to_international boolean, open_to_domestic boolean, applicant_basis text);
create index courses_not_active_idx on catalogue.courses (id) where lifecycle_status is distinct from 'active';
create table search.course_documents(course_id uuid primary key, provider_id uuid not null, country_id uuid not null, study_level_id uuid, primary_field_id uuid,
  provider_name text not null, course_title text not null, collection_names text[] not null default '{}', academic_option_names text[] not null default '{}', description text,
  search_text text not null, search_tsv tsvector not null, has_fee boolean not null default false, has_intake boolean not null default false, has_english boolean not null default false,
  has_scholarship boolean not null default false, publication_status text not null, completeness_score numeric, catalogue_generation bigint not null default 1, content_hash text,
  updated_at timestamptz not null default now(), course_stable_key text, provider_stable_key text, course_code text, country_code text, study_level_code text,
  primary_field_code text, primary_field_name text, subdivision_codes text[] not null default '{}', delivery_modes text[] not null default '{}', has_state boolean not null default false,
  has_link boolean not null default false, projection_version text not null default 'course-v2', source_updated_at timestamptz, generated_at timestamptz not null default now(),
  semantic_content_hash text, regulatory_tuition_state text, has_regulatory_tuition boolean not null default false, regulatory_tuition_amount numeric,
  regulatory_tuition_currency character(3), regulatory_tuition_basis text, has_provider_current_tuition boolean not null default false, provider_annual_tuition_amount numeric,
  provider_annual_tuition_currency character(3), provider_tuition_options jsonb not null default '[]', official_course_url text, intake_options jsonb not null default '[]',
  earliest_intake_date date, english_requirement_options jsonb not null default '[]', scholarship_options jsonb not null default '[]', enrichment_semantic_text text, enrichment_content_hash text);
create index course_documents_provider_idx on search.course_documents (provider_id, publication_status);

-- Layer 4, course-url-fill, adapter drafts, ledgers (live columns)
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null, field_code text not null,
  evidence_id uuid, layer3_interpretation_id uuid, before_value jsonb, proposed_value jsonb, layer2_state jsonb not null default '{}', layer3_state jsonb not null default '{}',
  status text not null default 'pending', assigned_to uuid, escalation_reason text, change_control_ref text not null default 'CF-CHG-20260825-038',
  created_at timestamptz not null default now(), decided_at timestamptz, claimed_at timestamptz);
create index layer4_review_items_status_created_idx on pipeline.layer4_review_items (status, created_at desc);
create table pipeline.course_url_fills(course_id uuid primary key, url text not null, evidence_id uuid not null, identity_basis text not null, filled_at timestamptz not null default now(),
  retracted_at timestamptz, retract_reason text);
create table pipeline.uni_adapter_drafts(id uuid primary key default gen_random_uuid(), provider_id uuid not null, status text not null default 'capturing', samples jsonb not null default '[]',
  captures jsonb not null default '[]', marks jsonb not null default '[]', comments text, proposals jsonb not null default '[]', model text, model_profile text,
  cost_usd numeric not null default 0, reason text, created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table pipeline.coverage_vendor_usage(id bigserial primary key, acquisition_provider_id uuid not null, units numeric not null, purpose text not null, provider_id uuid, url text,
  at timestamptz not null default now(), on_demand_run uuid);
create index coverage_vendor_usage_provider_at_idx on pipeline.coverage_vendor_usage (provider_id, at);
create table pipeline.ai_spend_ledger(id bigserial primary key, at timestamptz not null default now(), lane text not null, source text not null, source_id text, cost_usd numeric not null,
  calls int not null default 1);
-- stand-ins for the two spend readers (live: security.fc_billed_today_v1 sums today's Firecrawl ledger; security.ai_spend_today_v1 returns use, label, spent, guard, calls)
create function security.fc_billed_today_v1() returns numeric language sql stable as
  $f$ select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' $f$;
create function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint) language sql stable as
  $f$ select lane, lane, sum(cost_usd), null::numeric, sum(calls)::bigint from pipeline.ai_spend_ledger
      where at >= date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' group by lane $f$;

-- the ten lease tables the stale-lease check reads (the columns it uses)
create table pipeline.coverage_ai_match(id bigserial primary key, provider_id uuid, course_id uuid, state text, leased_until timestamptz);
create table pipeline.field_enrich_items(id bigserial primary key, provider_id uuid, course_id uuid, state text, leased_until timestamptz);
create table pipeline.scholarship_ai_queue(id bigserial primary key, provider_id uuid, state text, leased_until timestamptz);
create table pipeline.central_ai_queue(id bigserial primary key, provider_id uuid, state text, leased_until timestamptz);
create table pipeline.entry_matrix_runs(id uuid primary key default gen_random_uuid(), provider_id uuid, state text, leased_until timestamptz);
create table pipeline.provider_description_reads(id bigserial primary key, provider_id uuid, state text, leased_until timestamptz);
create table pipeline.layer1_run_queue(id bigserial primary key, status text, lease_until timestamptz);
create table pipeline.fee_reader_queue(id bigserial primary key, provider_id uuid, state text, leased_until timestamptz);
create table pipeline.provider_central_search(id bigserial primary key, provider_id uuid, state text, leased_until timestamptz);
create table pipeline.source_find_runs(id bigserial primary key, provider_id uuid, state text, leased_until timestamptz);
