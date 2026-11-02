-- AER Phase B: isolated fixture database (CF-247 AER mandate 2 Nov 2026 14:45, §16 Phase B). Run on a scratch PostgreSQL only (never on a
-- Supabase project): see run.sh. The AER tables carry their live column definitions (information_schema on fxcwkweaxjtknorudmwp, read
-- 2 Nov 2026 15:19 AEDT); the platform tables carry the columns and checks the reconcile, the alert job and the screens use. No live data.
create extension if not exists pgcrypto;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists ref; create schema if not exists cron; create schema if not exists fx;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role supabase_read_only_user; exception when duplicate_object then null; end $$;

-- settings (the live readers' semantics)
create table pipeline.platform_toolsets(key text primary key);
insert into pipeline.platform_toolsets values ('pipeline');
create table pipeline.platform_toolset_settings(toolset_key text not null references pipeline.platform_toolsets(key), key text not null, label text not null, help text not null default '',
  kind text not null check (kind in ('number', 'text', 'boolean', 'list')), value jsonb not null, min_value numeric, max_value numeric, unit text, sort int not null default 100,
  reason text, updated_by uuid, updated_at timestamptz not null default now(), section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('pipeline', 'alerts.delivery_enabled', 'Alerts: delivery', 'boolean', 'true'),   -- as live (Phase A baseline §6)
  ('pipeline', 'alerts.min_severity', 'Alerts: minimum severity', 'number', '3'),
  ('pipeline', 'alerts.confirm_minutes', 'Alerts: open before alerting', 'number', '0');  -- fixtures: alert at once (live 15)

-- the signed-in person
create table auth.session(uid uuid, rank int);
create function auth.uid() returns uuid language sql stable as $f$ select uid from auth.session limit 1 $f$;
create function security.current_role_rank() returns int language sql stable as $f$ select rank from auth.session limit 1 $f$;

-- scheduler (pg_cron's surface as the migration uses it)
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as
  $f$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $f$;
create function cron.alter_job(job_id bigint, active boolean) returns void language sql as $f$ update cron.job set active = alter_job.active where jobid = job_id $f$;

-- reference and catalogue (live columns used by AER)
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 character(2) not null, iso_alpha3 character(3) not null default 'XXX', name text not null);
create table ref.study_levels(id uuid primary key default gen_random_uuid(), code text, short_code text, name text, sort_order int, parent_id uuid);
create table ref.provider_types(id uuid primary key default gen_random_uuid(), code text not null, name text not null, status text not null default 'active', description text);
create table catalogue.providers(id uuid primary key default gen_random_uuid(), display_name text, short_name text, canonical_name text, country_id uuid not null,
  lifecycle_status text not null default 'active', publication_status text not null default 'published', enrols_international boolean, provider_type_id uuid);
create table catalogue.courses(id uuid primary key default gen_random_uuid(), provider_id uuid not null, study_level_id uuid, canonical_title text, course_code text,
  lifecycle_status text not null default 'active', publication_status text not null default 'published', open_to_international boolean);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), captured_at timestamptz default now(), content_hash text);

create table catalogue.provider_entry_matrix(id uuid not null default gen_random_uuid() primary key, provider_id uuid not null, course_id uuid, course_label text,
  matrix_kind text not null default 'provider_minimum', benchmark_band text, level_label text, study_level_id uuid, country_id uuid not null, country_code text not null,
  qualification_name text not null, min_grade text, min_value numeric, grade_scale text, conditions jsonb not null default '{}', audience text not null default 'international',
  edition text, intake_year integer, quote text not null, source_url text not null, source_id uuid, evidence_id uuid, content_hash text, run_id uuid, confidence numeric,
  as_at date not null default current_date, status text not null default 'proposed', status_reason text, provenance jsonb not null default '{}',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), routes jsonb, valid_to date, withdrawal_reason character varying,
  row_hash character(64), version integer default 1, aer_level character varying);
create table catalogue.course_entry_requirements(id uuid not null default gen_random_uuid() primary key, course_id uuid not null, kind text not null,
  audience text not null default 'international', country_id uuid, description text not null, min_grade text, min_value numeric, grade_scale text, min_entry_score numeric,
  min_entry_score_basis text, benchmark_band text, quote text not null, source_url text, evidence_id uuid, confidence numeric, as_at date not null default current_date,
  status text not null default 'proposed', status_reason text, provenance jsonb not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table pipeline.entry_matrix_sources(id uuid not null default gen_random_uuid() primary key, provider_id uuid not null, url text not null, title text,
  rank integer not null default 1, found_via text not null, status text not null default 'found', read_via text, http_status integer, evidence_id uuid, content_hash text,
  attempts integer not null default 0, read_at timestamptz, error text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (provider_id, url));
create table pipeline.entry_matrix_runs(id uuid not null default gen_random_uuid() primary key, provider_id uuid not null, source_id uuid not null, content_hash text not null,
  state text not null default 'queued', attempts integer not null default 0, leased_until timestamptz, model_code text, slices integer, rows_admitted integer, rows_dropped integer,
  result jsonb, cost_usd numeric not null default 0, error text, review_item_id uuid, created_at timestamptz not null default now(), done_at timestamptz,
  updated_at timestamptz not null default now(), previous_results jsonb not null default '[]', unique (source_id, content_hash));
create table pipeline.layer4_review_items(id uuid not null default gen_random_uuid() primary key, entity_type text not null, entity_id uuid not null, field_code text not null,
  evidence_id uuid, layer3_interpretation_id uuid, before_value jsonb, proposed_value jsonb, layer2_state jsonb not null default '{}', layer3_state jsonb not null default '{}',
  status text not null default 'pending', assigned_to uuid, escalation_reason text, change_control_ref text not null default 'CF-CHG-20260825-038',
  created_at timestamptz not null default now(), decided_at timestamptz, claimed_at timestamptz);
create table pipeline.aer_course_outcomes(course_id uuid not null primary key, provider_id uuid not null, country text not null, provider_name text, provider_published boolean not null,
  course_title text, course_code text, outcome text not null, detail text not null, course_url text, page_status text, identity_basis text, read_state text, read_reason text,
  review_item_id uuid, built_at timestamptz not null);
create table pipeline.ai_spend_ledger(id bigserial primary key, at timestamptz not null default now(), lane text not null, source text not null, source_id text,
  cost_usd numeric not null check (cost_usd > 0), calls int not null default 1);

-- platform health, alerts, catalogue and register (live columns and checks)
create table pipeline.platform_issues(id uuid not null default gen_random_uuid() primary key, check_key text not null, severity text not null check (severity in ('critical', 'warning', 'info')),
  area text not null check (area in ('scheduled jobs', 'edge functions', 'coverage sweep', 'admission', 'Layer 3', 'scholarships', 'budgets', 'search/API', 'storage/DB')),
  title text not null, detail jsonb not null default '{}', first_seen timestamptz not null default now(), last_seen timestamptz not null default now(), occurrences integer not null default 1,
  resolved_at timestamptz, acknowledged_by uuid, acknowledged_at timestamptz, acknowledged_note text);
create unique index platform_issues_open_uq on pipeline.platform_issues (check_key) where resolved_at is null;
create table pipeline.platform_health_checks(key text primary key, area text not null, label text not null, status text not null default 'skipped' check (status in ('ok', 'warning', 'critical', 'skipped')),
  detail jsonb not null default '{}', checked_at timestamptz, duration_ms integer, cadence_minutes integer not null default 10, slow boolean not null default false, sort_order integer not null default 100);
create table pipeline.platform_alerts(id bigserial primary key, issue_id uuid references pipeline.platform_issues(id) on delete set null, check_key text not null,
  kind text not null check (kind in ('raised', 'escalated', 'reminder', 'recovered', 'test')), severity text not null check (severity in ('critical', 'warning', 'info')),
  title text not null, body text not null, status text not null check (status in ('held', 'pending', 'sending', 'sent', 'failed')), attempts int not null default 0,
  next_attempt_at timestamptz not null default now(), lease_until timestamptz, sent_via text, sent_at timestamptz, net_request_id bigint, last_error text,
  dedupe_key text not null unique, created_at timestamptz not null default now());
create table pipeline.automation_catalogue(jobname text primary key, area text not null, sort integer not null default 100, label text not null, description text not null,
  control_rank integer not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register(kind text not null check (kind in ('job', 'table', 'view', 'edge_function', 'screen', 'function')), name text not null, layer text not null,
  area text, purpose text, status text not null default 'active' check (status in ('active', 'retiring', 'retired')), replaces text[] not null default '{}', replaced_by text,
  introduced_in text, retire_after date, last_used_at timestamptz, usage jsonb not null default '{}', size_bytes bigint, note text, registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), primary key (kind, name));
create table pipeline.ops_scorecards(week_start date primary key, week_end date not null, generated_at timestamptz not null default now(), generated_by text not null, scorecard jsonb not null);
-- the weekly scorecard itself is not part of these fixtures: a stand-in returns the week (its live definition is unchanged by Phase B)
create function security.ops_scorecard_v1(p_week_start date default null, p_prior jsonb default null) returns jsonb language sql stable as
  $f$ select jsonb_build_object('week_start', p_week_start, 'complete', false, 'met', 0, 'missed', 0) $f$;

-- fixture assertion helper
create function fx.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
