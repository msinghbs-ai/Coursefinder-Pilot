-- CF-247 P0 workstream E (AI evaluation, migration 20261104070000) on isolated fixtures: the live shapes this change reads, writes beside or
-- registers into. Columns read from information_schema on production (read-only, 3 Nov 2026 15:43-15:52 AEDT); security.pipeline_num_v1 is
-- the live text (md5 09f9b1551daf42b4a0c9795e6f30c6d4). Scratch PostgreSQL only (never a Supabase project): see run.sh. Nothing here is live data.
create schema if not exists pipeline; create schema if not exists security; create schema if not exists catalogue; create schema if not exists cron; create schema if not exists auth;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;
grant usage on schema pipeline, security, public, catalogue to service_role;
alter default privileges in schema pipeline grant all on tables to service_role;  -- as on Supabase: new tables are open to service_role unless revoked

create table auth.users (id uuid primary key);

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null default '', help text not null default '', kind text not null,
  value jsonb not null, min_value numeric, max_value numeric, unit text, sort int, reason text, updated_by uuid, updated_at timestamptz default now(), section text, used_by text,
  primary key (toolset_key, key));
CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;
create table pipeline.automation_catalogue (jobname text primary key, area text not null, sort int not null default 100, label text not null, description text not null,
  control_rank int not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register (kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, last_used_at timestamptz, usage jsonb not null default '{}', size_bytes bigint,
  note text, registered_at timestamptz not null default now(), updated_at timestamptz not null default now(), primary key (kind, name));
create table pipeline.admin_control_events (id bigint generated always as identity primary key, area text not null, action text not null, target text, detail jsonb not null default '{}',
  actor uuid, created_at timestamptz not null default now());
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $$;

-- what workstream A's contract alters (live columns used by A)
create table pipeline.integration_issues (id bigserial primary key, fingerprint text, title text, state text not null default 'detected', created_at timestamptz not null default now());
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text not null, state text not null default 'queued');

-- catalogue (the columns read)
create table catalogue.courses (id uuid primary key, provider_id uuid, canonical_title text, display_title text, course_url text, lifecycle_status text default 'active');
create table catalogue.providers (id uuid primary key, canonical_name text, display_name text, short_name text, website text, logo_url text, lifecycle_status text default 'active');

-- trusted sources (live columns)
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid, layer3_interpretation_id uuid,
  before_value jsonb, proposed_value jsonb, layer2_state jsonb, layer3_state jsonb, status text, assigned_to uuid, escalation_reason text, change_control_ref text,
  created_at timestamptz default now(), decided_at timestamptz, claimed_at timestamptz);
create table pipeline.layer4_decisions (id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb,
  proposed_value jsonb, final_value jsonb, evidence_id uuid, layer2_state jsonb, layer3_state jsonb, scalar_resolution_id uuid, change_control_ref text, created_at timestamptz default now());
create table pipeline.manual_edit_log (id bigint generated always as identity primary key, entity text, entity_id uuid, field text, action text, before jsonb, after jsonb, reason text,
  actor uuid, at timestamptz default now());
create table pipeline.manual_locks (entity text not null, entity_id uuid not null, field text not null, mode text, set_by uuid, set_at timestamptz not null default now(),
  primary key (entity, entity_id, field));
create table pipeline.field_enrich_items (id bigint generated always as identity primary key, job_id uuid, provider_id uuid, course_id uuid, field text, state text, source text,
  tried text[], value jsonb, quote text, reason text, evidence_id uuid, storage_path text, attempts int default 0, leased_until timestamptz, cost_usd numeric,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.scholarship_ai_reviews (id bigint generated always as identity primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, storage_path text,
  extraction_ids bigint[], reason text, status text, decided_by uuid, decided_at timestamptz, note text, decision jsonb, created_at timestamptz default now(), recheck jsonb);
create table pipeline.coverage_ai_match (id bigint generated always as identity primary key, course_id uuid, provider_id uuid, attempt int, state text, candidates jsonb, chosen_url text,
  answer jsonb, model text, cost_usd numeric, leased_until timestamptz, created_at timestamptz default now(), decided_at timestamptz);

-- model and prompt homes (the columns read)
create table pipeline.scholarship_ai_prompts (version int primary key, text text, active boolean, reason text, created_by uuid, created_at timestamptz default now());
create table pipeline.scholarship_ai_models (code text primary key, label text, model_identifier text, price_note text, status text, activated_at timestamptz, activated_by uuid, reason text, sort int);
create table pipeline.layer3_model_profiles (id uuid primary key default gen_random_uuid(), code text, model_identifier text, enabled boolean, paused boolean, retired_at timestamptz);
create table pipeline.central_ai_settings (id int primary key, enabled boolean, model_code text, model_identifier text, calls_at_once int);

-- live values these read (3 Nov 2026)
insert into pipeline.scholarship_ai_prompts values (1, 'v1 text', false, 'v1'), (2, 'v2 text', true, 'v2');
insert into pipeline.scholarship_ai_models(code, model_identifier, status) values ('qwen3-30b', 'qwen/qwen3-30b-a3b-instruct-2507', 'active'), ('gpt-4.1-mini', 'openai/gpt-4.1-mini', 'candidate'),
  ('gpt-4.1', 'openai/gpt-4.1', 'candidate'), ('person', 'person', 'retired');
insert into pipeline.layer3_model_profiles(code, model_identifier, enabled, paused, retired_at) values
  ('openrouter-free-router-v1', 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free', false, true, now()),
  ('openrouter-intake-l3r-claude-haiku-4-5-v1', 'anthropic/claude-haiku-4.5', true, false, null);
insert into pipeline.central_ai_settings values (1, true, 'gpt-4.1-mini', 'openai/gpt-4.1-mini', 2);
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value, min_value, max_value, unit, used_by) values
  ('pipeline', 'entry.matrix_model', 'text', '"openai/gpt-4.1-mini"', null, null, null, 'public.svc_entry_matrix_next'),
  ('pipeline', 'batch.enrich_fields', 'number', '1200', 20, 5000, 'items a minute', 'admin-jobs'),
  ('pipeline', 'enrich.ai_items_per_call', 'number', '30', 5, 40, 'items', 'worker enrich_ai'),
  ('pipeline', 'batch.coverage_read', 'number', '60', 10, 200, 'pages every 30 seconds', 'coverage-read'),
  ('pipeline', 'batch.coverage_admit', 'number', '500', 10, 5000, 'courses a run', 'coverage-admit'),
  ('openrouter', 'guard_enrich_fields', 'number', '25', 0, 500, 'USD', 'OpenRouter guard');
