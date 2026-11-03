-- Ops workstream G (provider identity and lifecycle, 3 Nov 2026): the shapes the migration reads or writes, cut to the columns used
-- (information_schema and check constraints, production, read-only, 3 Nov 2026 15:42-15:58 AEDT). Functions the migration only calls are small
-- fixture stand-ins (fx.*), except those it md5-guards, which load from live/. Never a Supabase project; nothing here is live data.
set check_function_bodies = off;
create extension if not exists pgcrypto;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists cron;
create schema if not exists search; create schema if not exists auth; create schema if not exists scholarship; create schema if not exists ref; create schema if not exists fx;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end $$;

-- who is calling (fixture-settable)
create table fx.caller (id int primary key default 1, uid uuid, rank int);
insert into fx.caller values (1, null, 0);
create or replace function auth.uid() returns uuid language sql stable as $$ select uid from fx.caller where id = 1 $$;
create or replace function security.current_role_rank() returns int language sql stable as $$ select rank from fx.caller where id = 1 $$;

-- settings, catalogue of jobs, component register, scheduler
create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null default '', help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create or replace function security.pipeline_list_v1(p_key text, p_default jsonb) returns text[] language sql stable set search_path to '' as $$
  select array(select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default))) $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', 'onboarding.website_check_on', 'number', '1');
create table pipeline.automation_catalogue (jobname text primary key, area text, sort int, label text, description text not null, control_rank int, batch_editable boolean, layer23_stage text);
insert into pipeline.automation_catalogue(jobname, description) values ('provider-onboarding', 'Onboarding tick.');
create table pipeline.component_register (kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, primary key (kind, name));
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $$;

-- reference and catalogue
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text, name text, provider_ingestion_enabled boolean default true,
  course_ingestion_enabled boolean default true, scholarship_ingestion_enabled boolean default true, student_search_enabled boolean default true, updated_at timestamptz);
create table pipeline.sources (id uuid primary key default gen_random_uuid(), label text, url text, last_success_at timestamptz, country_id uuid);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), stable_key text, canonical_name text, display_name text, short_name text, country_id uuid,
  website text, email text, lifecycle_status text default 'active', publication_status text default 'published', canonical_source_id uuid, updated_at timestamptz default now());
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active');
create table catalogue.campuses (id uuid primary key default gen_random_uuid(), provider_id uuid);
create table catalogue.provider_registrations (id uuid primary key default gen_random_uuid(), provider_id uuid, source_id uuid, registration_scheme text, registration_code text,
  status text, valid_from date, valid_to date, checked_at timestamptz, evidence_id uuid);
create table catalogue.course_registrations (id uuid primary key default gen_random_uuid(), course_id uuid, scheme text, registration_code text, status text);
create table catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), course_id uuid);
create table catalogue.course_english_requirements (id uuid primary key default gen_random_uuid(), course_id uuid);
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), provider_id uuid, lifecycle_status text default 'active');

-- the hide every consumer path reads (live definition, 20261010006800)
create view security.provider_hidden_v1 as
  select p.id as provider_id from catalogue.providers p where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
create table search.refresh_requests (id bigint generated always as identity primary key, requested_at timestamptz default now(), requested_by text);
create table search.course_documents (course_id uuid primary key, provider_id uuid);

-- third-party hosts (live definition) and its table
create table pipeline.important_links (domain text, enabled boolean default true, retired_at timestamptz, uses text[], authority_category text);
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable security definer set search_path to '' as $$
  select coalesce((select bool_or(case when l.domain like '%.%' then h = l.domain or h like '%.' || l.domain else h ~ ('(^|\.)' || l.domain) end)
                     from pipeline.important_links l, (select security.site_host_v1(p_url) h) x
                    where x.h is not null and l.enabled and l.retired_at is null and l.domain is not null and 'not_provider_site' = any(l.uses)
                      and l.authority_category in ('third_party_directory', 'general_web', 'ranking_publisher')), false) $$;

-- evidence, website checks
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_url text, evidence_type text, captured_at timestamptz default now(),
  storage_path text, content_hash text, review_state text, metadata jsonb default '{}');
create table pipeline.provider_website_checks (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, action text, extra_site text, reason text, requested_by uuid,
  requested_at timestamptz default now(), state text default 'queued', leased_until timestamptz, attempts int default 0, result jsonb, verdict text, why text, checked_at timestamptz,
  applied boolean default false, applied_at timestamptz, apply_note jsonb);
create table fx.kicks (at timestamptz default now());
create or replace function security.provider_website_check_kick_v1() returns boolean language sql as $$ insert into fx.kicks default values; select true $$;
-- the existing person-run check (Curator and above): stand-in that records the queued check as the live one does
create or replace function public.admin_provider_website_check(p_action text, p_args jsonb) returns jsonb language sql as $$
  insert into pipeline.provider_website_checks(provider_id, url, action, requested_by) values ((p_args->>'provider_id')::uuid, p_args->>'url', p_action, auth.uid())
  returning jsonb_build_object('id', id, 'state', 'queued') $$;
create table pipeline.scholarship_discovery_providers (provider_id uuid primary key, website text, site_origin text, status text);

-- register departures and archives
create table pipeline.layer1_provider_departures (id bigint generated always as identity primary key, provider_id uuid, run_id uuid, courses_retired int, status text,
  successor_provider_id uuid, note text, created_at timestamptz default now(), reviewed_by uuid, reviewed_at timestamptz);
create table pipeline.provider_archives (id bigint generated always as identity primary key, provider_id uuid, source text, reason text, previous_lifecycle text, previous_publication text,
  cascade jsonb, archived_by uuid, archived_at timestamptz default now(), restored_by uuid, restored_at timestamptz, restore_note text);
create table pipeline.manual_edit_log (id bigint generated always as identity primary key, entity text, entity_id uuid, field text, action text, before jsonb, after jsonb, reason text, actor uuid,
  at timestamptz default now());
create table pipeline.uni_adapters (provider_id uuid primary key, enabled boolean, admit boolean, updated_at timestamptz);
create table pipeline.course_link_recipes (provider_id uuid primary key, active boolean, updated_at timestamptz);
create table pipeline.course_link_search (course_id uuid primary key, provider_id uuid, state text check (state in ('queued', 'sent', 'found', 'none', 'error', 'verified')));
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text,
  status text check (status in ('pending', 'approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded')), decided_at timestamptz);

-- work
create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text not null default 'x', lane text not null default 'x', state text not null default 'queued'
  check (state in ('queued', 'running', 'paused', 'done', 'failed', 'cancelled')), args jsonb not null default '{}', cancel_requested boolean not null default false,
  updated_at timestamptz default now(), scope text);
create table pipeline.enrich_plan_runs (id uuid primary key default gen_random_uuid(), provider_id uuid, mode text default 'auto',
  state text default 'queued' check (state in ('queued', 'running', 'done', 'failed', 'cancelled')), actual jsonb, updated_at timestamptz, finished_at timestamptz);
create table pipeline.provider_onboarding_settings (id int primary key, enabled boolean, max_active int, run_as uuid);
insert into pipeline.provider_onboarding_settings values (1, true, 5, gen_random_uuid());
create table pipeline.provider_onboarding (id uuid primary key default gen_random_uuid(), provider_id uuid,
  status text check (status in ('queued', 'website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships', 'waiting_admit', 'waiting_courses', 'stopped', 'done', 'cancelled')),
  step_started_at timestamptz, started_at timestamptz, job_id uuid, attempts int default 0, stop_reason text, note text, result jsonb default '{}', priority int default 0,
  requested_by uuid, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.coverage_course_pages (provider_id uuid, read_status text);
create table pipeline.provider_policy_proposals (provider_id uuid, status text, decided_at timestamptz);
create or replace function security.adapter_builder_budget() returns jsonb language sql stable as $$ select '{"used_usd": 0, "limit_usd": 1, "proposals": 0, "limit_proposals": 1}'::jsonb $$;
create table fx.stepped (onboarding_id uuid, at timestamptz default now());
create or replace function security.provider_onboarding_step_v1(p uuid) returns void language sql as $$ insert into fx.stepped(onboarding_id) values (p) $$;
create table pipeline.field_enrich_items (id bigint generated always as identity primary key, provider_id uuid, state text);
create table pipeline.aer_gap_findings (id bigint generated always as identity primary key, provider_id uuid, state text);
create table pipeline.provider_contacts (id uuid primary key default gen_random_uuid(), provider_id uuid, deleted_at timestamptz);
create table pipeline.provider_contact_profiles (id uuid primary key default gen_random_uuid(), provider_id uuid, paused boolean default false, updated_at timestamptz);
create table pipeline.admin_control_events (id bigint generated always as identity primary key, area text not null, action text not null, target text, detail jsonb not null default '{}',
  actor uuid, created_at timestamptz not null default now());

-- integration queue (live columns used) and the live upsert cut to create / observe by fingerprint
create table pipeline.integration_issues (id bigint generated always as identity primary key, fingerprint text unique, title text, status text default 'detected', severity text,
  failure text, provider_ids uuid[] default '{}', evidence jsonb, workstream text, observed int default 1, condition_cleared_at timestamptz);
create or replace function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language plpgsql as $$
declare v pipeline.integration_issues; v_new boolean;
begin
  v_new := not exists (select 1 from pipeline.integration_issues where fingerprint = p->>'fingerprint');
  insert into pipeline.integration_issues(fingerprint, title, severity, failure, provider_ids, evidence, workstream)
  values (p->>'fingerprint', p->>'title', p->>'severity', p->>'failure', array(select jsonb_array_elements_text(p->'provider_ids'))::uuid[], p->'evidence', p->>'workstream')
  on conflict (fingerprint) do update set observed = pipeline.integration_issues.observed + 1, failure = excluded.failure, provider_ids = excluded.provider_ids
  returning * into v;
  return jsonb_build_object('id', v.id, 'action', case when v_new then 'created' else 'observed' end);
end $$;
