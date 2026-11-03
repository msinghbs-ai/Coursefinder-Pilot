-- Live shapes for the workstream B worker-release fixtures (coverage-sweep v0.59.5, migration 20261104110000). Only the columns the definitions
-- under test read or write; read-only from production on 3 Nov 2026 18:16 AEDT (information_schema). Never a Supabase project.
create schema if not exists pipeline; create schema if not exists security; create schema if not exists cron; create schema if not exists auth;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end $$;
create or replace function auth.role() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create or replace function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable set search_path to '' as $$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $$;
create table pipeline.automation_catalogue (jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register (kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, primary key (kind, name));
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $$;
create table pipeline.course_link_search (course_id uuid primary key, provider_id uuid, stage text, state text, query text, req_id bigint, attempts int not null default 0, results jsonb,
  candidates jsonb, cand_idx int, bound_url text, queued_at timestamptz, sent_at timestamptz, done_at timestamptz, requested_at timestamptz);
-- the tables the three live functions read (workstreams A and D)
create table pipeline.ops_ai_diagnosis_requests (id bigserial primary key, issue_id bigint, requested_at timestamptz not null default now(), state text not null default 'queued',
  leased_until timestamptz, context jsonb, answer jsonb, model text, cost_usd numeric, answered_at timestamptz, note text);
create table pipeline.ops_root_causes (code text primary key, class text, title text, description text, detect jsonb, created_at timestamptz default now());
create table pipeline.integration_issues (id bigserial primary key, diagnosis jsonb, next_action_at timestamptz);
create table pipeline.field_enrich_items (id bigserial primary key, attempts int default 0, evidence_id uuid, storage_path text);
create table pipeline.enrich_ai_answers (item_id bigint, attempts int, evidence_id uuid, storage_path text, answer jsonb, cost_usd numeric, primary key (item_id, attempts));
create or replace function security.ai_spend_today_v1() returns table(use text, spent numeric, guard numeric) language sql stable as $$ select 'x'::text, 0::numeric, 0::numeric $$;
-- live only (no migration in the repository); the worker calls it as before, so only its presence is checked
create or replace function public.svc_course_link_search_record(p_course_id uuid, p_http integer, p_urls text[], p_error text default null) returns text language sql as $$ select 'stub'::text $$;
