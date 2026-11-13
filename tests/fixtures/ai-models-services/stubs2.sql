-- Phase 2 (migration 20261113390000): the further live shapes its functions touch, cut to the columns they read. Scratch PostgreSQL only.
create schema cron;
create table cron.job (jobid bigint generated always as identity primary key, jobname text, schedule text, command text, active boolean default true);
create table pipeline.layer3_model_profiles (id uuid primary key default gen_random_uuid(), code text unique, model_identifier text, allowed_task_classes text[], enabled boolean, paused boolean,
  retired_at timestamptz, aggregator_provider text default 'openrouter', max_output_tokens integer);
create table pipeline.layer3_route_tiers (profile_id uuid, task_class text, tier_no integer, active boolean);
create table pipeline.layer3_interpretations (id bigint generated always as identity primary key, profile_id uuid, created_at timestamptz default now());
create table pipeline.uni_adapter_models (provider_id uuid primary key, profile_code text, set_by uuid, set_at timestamptz default now(), reason text);
create table pipeline.uni_adapter_drafts (id uuid primary key default gen_random_uuid(), provider_id uuid, proposals jsonb not null default '[]', model text, cost_usd numeric not null default 0);
create function security.firecrawl_setting(p_key text) returns jsonb language sql stable as $$ select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key $$;
insert into pipeline.platform_toolset_settings (toolset_key, key, label, kind, value) values ('firecrawl', 'builder_model_profile', 'Its Models and services profile', 'text', '"openrouter-intake-l3c-qwen3-30b-a3b-2507-v1"');
alter table pipeline.aer_prompt_versions add column system_sha256 text, add column quote_max_chars integer;
create table pipeline.aer_v2_shadow_results (id bigint generated always as identity primary key, cost_usd numeric, created_at timestamptz default now());
insert into pipeline.platform_toolset_settings (toolset_key, key, label, kind, value) values ('pipeline', 'aer.v2_shadow_on', 'Entry requirements v2: shadow trial', 'number', '1'), ('pipeline', 'aer.v2_shadow_budget_usd', 'Entry requirements v2: shadow trial budget', 'number', '20');
-- central pages and course-page matching readers
alter table pipeline.central_ai_queue add column fact_source_id uuid, add column attempts integer not null default 0, add column leased_until timestamptz, add column status text, add column done_at timestamptz, add column error text;
create table pipeline.provider_fact_sources (id uuid primary key, url text, evidence_id uuid);
create function security.calendar_reader_notes_v1(uuid) returns jsonb language sql stable as $$ select null::jsonb $$;
create table pipeline.coverage_ai_match (id bigint generated always as identity primary key, course_id uuid, provider_id uuid, state text, candidates jsonb, model text, cost_usd numeric, leased_until timestamptz, decided_at timestamptz);
create table pipeline.course_priority (course_id uuid primary key, sort integer);
create table pipeline.provider_priority (provider_id uuid primary key, rank integer);
alter table catalogue.courses add column course_code text;
create function security.coverage_country(uuid) returns text language sql stable as $$ select 'AU'::text $$;
create table pipeline.provider_description_reads (id uuid primary key, provider_id uuid, state text, model text, cost_usd numeric);  -- for a %rowtype in the reserve function
create table pipeline.scholarship_ai_queue (id bigint generated always as identity primary key, model_code text, provider_id uuid, state text);  -- for a %rowtype in the record function
alter table pipeline.scholarship_ai_extract_settings add column ai_admission boolean default true;
-- round 3 (independent QA, 13 Nov 2026): the live constraints that matter to the scholarship chain and to on-demand scope
alter table pipeline.scholarship_ai_models add column activated_at timestamptz, add column activated_by uuid, add column reason text;
alter table pipeline.scholarship_ai_models alter column status set default 'candidate', alter column sort set default 100, alter column label set not null, alter column model_identifier set not null;
alter table pipeline.scholarship_ai_models add constraint scholarship_ai_models_status_check check (status = any (array['candidate', 'active', 'retired']));
alter table pipeline.scholarship_ai_queue add constraint scholarship_ai_queue_model_code_fkey foreign key (model_code) references pipeline.scholarship_ai_models(code);
alter table pipeline.on_demand_requests add column purpose_groups text[];
alter table pipeline.layer3_model_profiles add column secret_env_key text default 'OPENROUTER_API_KEY';
