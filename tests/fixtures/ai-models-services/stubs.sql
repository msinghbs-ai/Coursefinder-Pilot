-- CF-247 AI models and services (migration 20261113380000): the live shapes the migration and the functions it edits touch, cut to the columns
-- they read. Scratch PostgreSQL only. The definitions the change edits or calls are in live/ as pg_get_functiondef gave them on 13 Nov 2026.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;
create schema auth; create schema security; create schema pipeline; create schema catalogue; create schema ref;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fx.uid', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('fx.role', true), ''), 'service_role') $$;
create function security.current_role_rank() returns smallint language sql stable as $$ select coalesce(nullif(current_setting('fx.rank', true), ''), '0')::smallint $$;

create table pipeline.platform_toolsets (key text primary key, enforcement text);
insert into pipeline.platform_toolsets values ('openrouter', 'observe');
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text,
  sort integer, reason text, updated_by uuid, updated_at timestamptz default now(), section text, used_by text, control_class text, primary key (toolset_key, key));
insert into pipeline.platform_toolset_settings (toolset_key, key, label, kind, value, min_value, max_value, unit, used_by) values
  ('pipeline', 'budgets.ai_daily_ceiling_usd', 'AI spend: daily ceiling', 'number', '14', 1, 500, 'US$', 'security.ai_use_refusal_v1'),
  ('pipeline', 'entry.matrix_model', 'Entry matrices: pinned model', 'text', '"openai/gpt-4.1-mini"', null, null, null, 'public.svc_entry_matrix_next'),
  ('pipeline', 'ops.ai_diagnosis_model', 'Operations controller: pinned AI diagnosis model', 'text', '"openai/gpt-4.1-mini"', null, null, null, 'public.svc_ops_diagnosis_next'),
  ('pipeline', 'ops.ai_diagnosis_on', 'Operations controller: AI diagnosis', 'number', '1', 0, 1, null, null),
  ('pipeline', 'ops.ai_diagnosis_usd_per_day', 'Operations controller: AI diagnosis spend a day', 'number', '0.5', 0, 5, 'US$', null),
  ('pipeline', 'ops.ai_requests_per_day', 'Operations controller: AI diagnoses a day', 'number', '20', 0, 500, 'requests', null),
  ('pipeline', 'entry.matrix_enabled', 'Entry matrices: on', 'number', '1', 0, 1, null, null),
  ('pipeline', 'entry.course_page_chars', 'Course entry requirements: page characters', 'number', '100000', 1000, 400000, 'characters', null),
  ('pipeline', 'enrich.course_text_items_per_day', 'Course description and deadline: standing items a day', 'number', '8000', 0, 20000, 'items', null),
  ('pipeline', 'enrich.multi_field_on', 'Course fields together', 'number', '1', 0, 1, null, null),
  ('pipeline', 'aer.v2_shadow_daily_usd', 'Entry requirements v2: shadow spend a day', 'number', '10', 0, 50, 'US$ a day', null),
  ('pipeline', 'batch.coverage_read', 'Not an AI setting', 'number', '60', 1, 500, 'pages', null),
  ('openrouter', 'credit_floor_usd', 'Credit floor', 'number', '0.5', 0, 500, 'US$', null),
  ('openrouter', 'low_balance_warn_usd', 'Warn when the balance is below', 'number', '10', 0, 1000, 'US$', null),
  ('openrouter', 'balance_stale_minutes', 'Warn when the balance has not been read for', 'number', '30', 5, 1440, 'minutes', null),
  ('openrouter', 'guard_enrich_fields', 'Daily guard: Enrich fields with AI', 'number', '50', 0, 50, 'US$ a day', null),
  ('openrouter', 'guard_entry_matrix', 'Daily guard: entry matrices with AI', 'number', '20', 0, 500, 'US$ a day', null),
  ('openrouter', 'guard_scholarship_ai', 'Daily guard: read scholarship pages with AI', 'number', '20', 0, 500, 'US$ a day', null),
  ('openrouter', 'guard_central_ai', 'Daily guard: central pages with AI', 'number', '5', 0, 500, 'US$ a day', null),
  ('openrouter', 'guard_fee_ai', 'Fee reader with AI', 'number', '5', 0, 100, 'US$ a day', null),
  ('openrouter', 'guard_course_match', 'Daily guard: AI course-page matching', 'number', '5', 0, 500, 'US$ a day', null),
  ('openrouter', 'guard_adapter_builder', 'Daily guard: adapter proposals', 'number', '5', 0, 500, 'US$ a day', null),
  ('openrouter', 'guard_provider_description', 'Daily guard: provider descriptions with AI', 'number', '1', 0, 100, 'US$ a day', null),
  ('firecrawl', 'builder_model', 'Model that proposes adapters', 'text', '"qwen/qwen3-30b-a3b-instruct-2507"', null, null, null, null),
  ('firecrawl', 'builder_ai_daily_usd', 'AI allowance a day', 'number', '5', 0, 20, 'US$', null),
  ('firecrawl', 'builder_proposals_per_day', 'Proposals a day', 'number', '1000', 0, 2000, 'calls', null);
create table pipeline.layer3_openrouter_observations (id uuid default gen_random_uuid() primary key, kind text, payload jsonb, remaining_usd numeric, observed_at timestamptz default now());
create table pipeline.central_ai_settings (id integer primary key, enabled boolean, model_code text, model_identifier text, calls_at_once integer, reason text, changed_by uuid, changed_at timestamptz);
insert into pipeline.central_ai_settings values (1, true, 'qwen3-30b', 'qwen/qwen3-30b-a3b-instruct-2507', 2, 'too much usage', null, now());
create table pipeline.scholarship_ai_models (code text primary key, label text, model_identifier text, price_note text, status text, sort integer);
insert into pipeline.scholarship_ai_models values ('qwen3-30b', 'Qwen3 30B', 'qwen/qwen3-30b-a3b-instruct-2507', null, 'active', 10), ('gpt-4.1-mini', 'GPT-4.1 mini', 'openai/gpt-4.1-mini', null, 'candidate', 20);
create table pipeline.scholarship_ai_extract_settings (id integer primary key, chain text[], reason text, changed_at timestamptz, changed_by uuid);
insert into pipeline.scholarship_ai_extract_settings values (1, array['qwen3-30b', 'gpt-4.1-mini'], 'F-SCH redesign 12 Nov 2026', now(), null);
create table pipeline.provider_description_prompts (version integer primary key, system_prompt text, status text);
insert into pipeline.provider_description_prompts values (3, 'old prompt', 'retired'), (4, 'You write a provider description.', 'active');
create table pipeline.scholarship_ai_prompts (version integer primary key, text text, active boolean);
insert into pipeline.scholarship_ai_prompts values (3, 'You read one scholarship page.', true);
create table pipeline.aer_prompt_versions (version text primary key, purpose text, system_text text, model text, status text, created_at timestamptz default now());
insert into pipeline.aer_prompt_versions values ('aer-v2-course-v1', 'course_page', 'You read entry requirements.', 'openai/gpt-4.1-mini', 'trial');
create table pipeline.ai_spend_ledger (id bigint generated always as identity primary key, at timestamptz not null default now(), lane text not null, source text not null, source_id text, cost_usd numeric not null, calls integer not null default 1);
create index ai_spend_ledger_at_idx on pipeline.ai_spend_ledger (at);
create table pipeline.admin_control_events (id bigint generated always as identity primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table pipeline.component_register (kind text not null check (kind = any (array['job', 'table', 'view', 'edge_function', 'screen', 'function'])), name text not null, layer text, area text, purpose text,
  status text not null default 'active' check (status = any (array['active', 'retiring', 'retired'])), replaces text[] default '{}', replaced_by text, introduced_in text, retire_after date, note text,
  registered_at timestamptz default now(), updated_at timestamptz default now(), primary key (kind, name));
insert into pipeline.component_register (kind, name, layer) values ('table', 'pipeline.central_ai_settings', 'L3 interpret');

-- the course field reader
create table ref.countries (id integer primary key, name text, iso_alpha2 text);
create table ref.subdivisions (id integer primary key, country_id integer, name text);
create table ref.study_levels (id integer primary key, name text, short_code text, sort_order integer);
create table ref.fields_of_study (code text primary key, name text);
create table catalogue.providers (id uuid primary key, display_name text, canonical_name text, website text, country_id integer);
create table catalogue.courses (id uuid primary key, canonical_title text, study_level_id integer);
create table catalogue.campuses (id uuid primary key, provider_id uuid, status text, subdivision_id integer, city text);
create table pipeline.admin_jobs (id uuid primary key, args jsonb);
create table security.provider_hidden_v1 (provider_id uuid);
create table pipeline.field_enrich_items (id bigint generated always as identity primary key, job_id uuid, provider_id uuid, course_id uuid, field text, state text, source text, tried text[], value jsonb,
  quote text, reason text, evidence_id uuid, storage_path text, attempts integer not null default 0, leased_until timestamptz, cost_usd numeric, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.central_ai_queue (id bigint generated always as identity primary key, provider_id uuid, kind text, state text, cost_usd numeric);
-- entry matrices
create table pipeline.evidence_artifacts (id uuid primary key, storage_path text, mime_type text);
create table pipeline.entry_matrix_sources (id uuid primary key, url text, evidence_id uuid);
create table pipeline.entry_matrix_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, source_id uuid, state text, attempts integer not null default 0, leased_until timestamptz, model_code text,
  cost_usd numeric, created_at timestamptz default now(), updated_at timestamptz default now());
create function security.entry_matrix_enabled_v1(uuid) returns boolean language sql stable as $$ select true $$;
create function security.entry_completeness_required_v1(uuid) returns boolean language sql stable as $$ select false $$;
-- operations diagnosis
create table pipeline.ops_root_causes (code text primary key);
insert into pipeline.ops_root_causes values ('unknown'), ('vendor_outage');
create table pipeline.ops_ai_diagnosis_requests (id bigint generated always as identity primary key, issue_id bigint, requested_at timestamptz default now(), state text, leased_until timestamptz,
  context jsonb, answer jsonb, model text, cost_usd numeric, answered_at timestamptz, note text);
create function security.ai_use_allowed_v1(p_use text) returns boolean language sql stable as $$ select true $$;
-- the spend triggers as live has them (pg_get_triggerdef, 13 Nov 2026), on the tables this fixture uses
create function security.ai_spend_capture_v1() returns trigger language plpgsql as $$ begin return null; end $$;  -- replaced by live/ai_spend_capture_v1.sql
create trigger ai_spend_capture after insert or update of cost_usd on pipeline.field_enrich_items for each row execute function security.ai_spend_capture_v1('enrich_fields', 'delta', '{cost_usd}');
create trigger ai_spend_capture after insert or update of cost_usd on pipeline.central_ai_queue for each row execute function security.ai_spend_capture_v1('central_ai', 'delta', '{cost_usd}');
create trigger ai_spend_capture after insert or update of cost_usd on pipeline.entry_matrix_runs for each row execute function security.ai_spend_capture_v1('entry_matrix', 'delta', '{cost_usd}');
create trigger ai_spend_capture after insert or update of cost_usd on pipeline.ops_ai_diagnosis_requests for each row execute function security.ai_spend_capture_v1('ops_diagnose', 'delta', '{cost_usd}');
-- on-demand requests (operating model 3.3.2; migration 20261113153100), the columns read here
create table pipeline.on_demand_requests (id uuid primary key default gen_random_uuid(), provider_ids uuid[] not null default '{}', toolsets text[] not null default '{firecrawl,openrouter}',
  state text not null default 'open', opened_at timestamptz not null default now(), expires_at timestamptz not null);
