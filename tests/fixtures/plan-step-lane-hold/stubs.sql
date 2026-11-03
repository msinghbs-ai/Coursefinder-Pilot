-- IQ-00064 plan step lane hold (CF-247 Agent D, 3 Nov 2026): the shapes the four edited live definitions read or write, cut to the columns
-- used (information_schema, production, read-only, 3 Nov 2026 12:50 AEDT). Helpers the definitions only call are small fixture-settable
-- stand-ins (fx.*). Never a Supabase project; nothing here is live data.
set check_function_bodies = off;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists cron;
create schema if not exists net; create schema if not exists search; create schema if not exists auth; create schema if not exists fx;
create or replace function auth.role() returns text language sql as $$ select 'service_role'::text $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end $$;

-- settings, register, catalogue
create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null default '', help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create or replace function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $$;
create table pipeline.automation_catalogue (jobname text primary key, description text not null);
insert into pipeline.automation_catalogue values ('flag-recheck', 'Idle flag recheck.'), ('admin-jobs', 'Task runner.');
create table pipeline.component_register (kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, primary key (kind, name));

-- scheduler and the idle guard's evidence
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.alter_job(job_id bigint, schedule text default null, command text default null, database text default null, username text default null, active boolean default null)
returns void language sql as $$ update cron.job set active = coalesce(alter_job.active, job.active) where jobid = job_id $$;
create table pipeline.edge_request_log (id bigint generated always as identity primary key, function_name text, mode text, created_at timestamptz default now(), request_id bigint);
create table net._http_response (id bigint primary key, status_code int, content text);
create table pipeline.enrichment_flags (id bigint generated always as identity primary key, entity text, entity_key text, field text default '', reason_code text, state text,
  reason text, flagged_at timestamptz default now(), released_at timestamptz, next_check_at timestamptz, checks int default 0, release_reason text);
create or replace function security.worker_call_work_v1(p text) returns int language sql immutable as $$ select (p::jsonb->>'items')::int $$;
create or replace function security.flag_list_num_v1(p_key text, p_i int) returns int language sql stable as $$ select null::int $$;
create or replace function security.flag_raise_v1(p_entity text, p_key text, p_provider uuid, p_field text, p_code text, p_reason text, p_kind text, p_source text, p_by text,
  p_evidence jsonb, p_x text, p_next timestamptz) returns void language sql as $$
  insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, state, reason, next_check_at) values (p_entity, p_key, p_field, p_code, 'raised', p_reason, p_next) $$;
create or replace function security.flag_release_v1(p_id bigint, p_by text, p_kind text, p_reason text, p_detail jsonb, p_resume boolean) returns void language plpgsql as $$
begin
  update pipeline.enrichment_flags set state = 'released', released_at = now(), release_reason = p_reason, checks = checks + 1 where id = p_id;
  if p_resume then update cron.job set active = true where jobname = (select entity_key from pipeline.enrichment_flags where id = p_id); end if;
end $$;
create or replace function security.job_held_off_v1(p text) returns boolean language sql stable as $$ select false $$;
-- not edited here: the picker-shaped "work is waiting" test, fixture-settable per mode
create table fx.waiting (mode text primary key, waiting boolean);
create or replace function security.worker_mode_waiting_v1(p_mode text) returns boolean language sql stable as $$ select coalesce((select waiting from fx.waiting where mode = p_mode), false) $$;

-- tasks
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text not null, lane text not null default 'adapters', state text not null default 'queued'
  check (state in ('queued', 'running', 'paused', 'done', 'failed', 'cancelled')), title text, args jsonb not null default '{}', cursor jsonb, progress jsonb, result jsonb, error text,
  cancel_requested boolean not null default false, pause_requested boolean not null default false, requested_by uuid, reason text, created_at timestamptz not null default now(),
  started_at timestamptz, updated_at timestamptz not null default now(), finished_at timestamptz, scope jsonb);
create table pipeline.admin_job_events (id bigint generated always as identity primary key, job_id uuid references pipeline.admin_jobs(id), note text, detail jsonb, at timestamptz default now());
create table pipeline.admin_job_items (id bigint generated always as identity primary key, job_id uuid, kind text, outcome text);
create or replace function security.admin_job_close_v1(p uuid) returns void language sql as $$ select null::void $$;
create table cron.job_run_details (jobid bigint, start_time timestamptz);
-- course page search rows and spend
create table pipeline.course_link_search (course_id uuid primary key, provider_id uuid, state text, requested_at timestamptz, queued_at timestamptz default now(), sent_at timestamptz);
create table pipeline.coverage_vendor_usage (id bigint generated always as identity primary key, units numeric, purpose text, provider_id uuid, at timestamptz default now(), on_demand_run uuid);
-- not edited here: the stall cause (the first course-search gate that holds), fixture-settable
create table fx.block (id int primary key default 1, block jsonb);
create or replace function security.link_search_block_v1(p_provider uuid, p_course_ids uuid[] default null) returns jsonb language sql stable as $$ select (select block from fx.block where id = 1) $$;

-- plans
create table catalogue.providers (id uuid primary key, website text);
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, mode text default 'auto', state text default 'queued', steps jsonb default '[]',
  created_at timestamptz default now(), started_at timestamptz, finished_at timestamptz, updated_at timestamptz, fields_before jsonb, fields_after jsonb, needs_person text, actual jsonb);
create view security.provider_hidden_v1 as select null::uuid provider_id where false;
create or replace function security.enrich_provider_fields_v1(p uuid) returns jsonb language sql stable as $$ select '{}'::jsonb $$;
create or replace function security.enrich_plan_needs_person_v1(p uuid) returns text language sql stable as $$ select null::text $$;
create or replace function security.enrich_plan_start_step_v1(p_run uuid, p_step text) returns jsonb language sql as $$ select '{}'::jsonb $$;
create or replace function security.fc_budget_left_v1(p text) returns numeric language sql stable as $$ select 1000::numeric $$;
create table pipeline.field_enrich_items (id bigint generated always as identity, provider_id uuid, job_id uuid, state text, updated_at timestamptz, cost_usd numeric);
create table pipeline.uni_adapter_drafts (provider_id uuid, created_at timestamptz, cost_usd numeric);
create table pipeline.scholarship_ai_extractions (provider_id uuid, at timestamptz, cost_usd numeric);
create table pipeline.provider_onboarding (id uuid primary key, status text, stop_reason text);
create table search.refresh_requests (requested_by text);
