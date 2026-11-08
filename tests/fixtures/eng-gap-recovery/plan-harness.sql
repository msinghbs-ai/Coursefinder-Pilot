-- Guards: Platform Admin 8 Nov 2026 14:06 (IQ-00072 zero-yield plans): the stand-ins the stalled-onboarding hold (20261108122000) needs to run security.enrich_plan_v1, the LIVE definition (live/, read with pg_get_functiondef on 8 Nov 2026,
-- md5 774c061974916b878f7762e55de07bb6), on a small database. Everything here is a LOCAL STAND-IN for a production object the plan reads; the plan function itself is the live text.
-- Isolated local PostgreSQL only.
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists scholarship; create schema if not exists auth;
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, section text, used_by text, reason text, primary key (toolset_key, key));
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
 ('pipeline', 'plans.retry_waits_for_change', 'list', '["too_few_pages", "nothing_ready", "no_website", "not a search target", "no website is recorded", "already has a read page", "Needs a website first", "needs_source_discovery"]'::jsonb);
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key and jsonb_typeof(value) = 'number'), p_default) $$;
-- auth.uid(): null (the automatic planner) unless a test sets request.jwt.claim.sub (a person behind the call)
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table catalogue.providers (id uuid primary key, display_name text, canonical_name text, website text, phone text, email text);
create table catalogue.courses (id uuid primary key, provider_id uuid, lifecycle_status text, created_at timestamptz not null default now(), duration_value numeric, study_level_id uuid, delivery_mode text, primary_field_id uuid, open_to_international boolean);
create table catalogue.course_campuses (course_id uuid);
create table pipeline.provider_central_search (provider_id uuid primary key, state text, searched_at timestamptz, updated_at timestamptz default now());
create table pipeline.provider_onboarding (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, stop_reason text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), finished_at timestamptz);
create table pipeline.uni_adapters (provider_id uuid, enabled boolean, admit boolean, admit_fields jsonb);
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, status text, read_status text, read_at timestamptz, evidence_id uuid);
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text, scope text, created_at timestamptz default now());
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, state text, steps jsonb);
create table scholarship.scholarships (provider_id uuid, lifecycle_status text);
create function security.enrich_unit_costs_v1() returns jsonb language sql stable as $$ select jsonb_build_object('site_credits', 5, 'search_credits_per_course', 1, 'adapter_credits', 40, 'adapter_usd', 0, 'enrich_usd_per_item', 0.01, 'scholarship_credits', 3, 'scholarship_usd', 0) $$;
-- the missing official URLs of a provider: its active courses with no bound page
create function security.enrich_provider_fields_v1(p_provider uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('official_url', jsonb_build_object('missing', (select count(*) from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active'
                                                                              and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)))) $$;
create function security.coverage_country(p uuid) returns text language sql stable as $$ select 'AU'::text $$;
create function security.enrich_item_held_v1(p_course uuid, p_field text) returns boolean language sql stable as $$ select false $$;
create function security.plan_step_work_v1(p uuid, p_step text) returns jsonb language sql stable as $$ select null::jsonb $$;
create function security.plan_empty_cycles_v1(p uuid, p_missing bigint) returns jsonb language sql stable as $$ select null::jsonb $$;
