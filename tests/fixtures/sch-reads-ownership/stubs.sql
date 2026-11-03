-- Live shapes for the scholarship sources and ownership fixtures (CF-247, 4 Nov 2026). Columns as read from production on 3 Nov 2026
-- (pg_attribute, read only); only the tables and helpers the definitions under test read or write. Never a Supabase project.
set check_function_bodies = off;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists scholarship; create schema if not exists auth;
create or replace function auth.role() returns text language sql as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end $$;

create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null default '', kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create or replace function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable set search_path to '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create table pipeline.automation_catalogue (jobname text primary key, description text);
create table pipeline.component_register (kind text not null, name text not null, primary key (kind, name));
create schema if not exists cron; create table cron.job (jobid bigint generated always as identity primary key, jobname text unique, schedule text, command text, active boolean default true);

create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, display_name text, lifecycle_status text default 'active', website text, country text default 'AU');
create table catalogue.provider_aliases (id uuid primary key default gen_random_uuid(), provider_id uuid, alias text, alias_type text, locale text, valid_from date, valid_to date, source_id uuid);
create view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.lifecycle_status = 'hidden';
create or replace function security.coverage_country(p uuid) returns text language sql stable as $$ select country from catalogue.providers where id = p $$;
create or replace function security.site_host_v1(p_url text) returns text language sql immutable as $$ select lower(substring(p_url from '^[a-z]+://(?:www\.)?([^/:?#]+)')) $$;
-- directory sites as live lists them (pipeline.important_links, third_party_directory)
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable as $$
  select coalesce(security.site_host_v1(p_url), '') in ('coursesearch.studymelbourne.vic.gov.au', 'search.studyqueensland.qld.gov.au') $$;
create table pipeline.provider_scholarship_search (provider_id uuid primary key, enabled boolean);
create or replace function security.provider_sch_search_off_v1(p_provider uuid) returns boolean language sql stable set search_path to '' as $$
  select exists (select 1 from pipeline.provider_scholarship_search f where f.provider_id = p_provider and not f.enabled) $$;
create or replace function security.scholarship_series_key_v1(p text) returns text language sql immutable as $$ select lower(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))) $$;
create or replace function scholarship.provider_currency(p uuid) returns text language sql as $$ select 'AUD' $$;
create or replace function security.lane_paid_hold_v1(p text) returns text language sql stable as $$ select nullif(current_setting('fx.lane_hold', true), '') $$;
create or replace function security.coverage_sweep_source(p uuid) returns uuid language sql as $$ select '00000000-0000-0000-0000-0000000000aa'::uuid $$;

create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_id uuid, evidence_type text, source_url text, storage_path text, content_hash text, mime_type text,
  metadata jsonb, capture_version int, evidence_group_key text, captured_at timestamptz default now());
create table scholarship.scholarships (id uuid primary key default gen_random_uuid(), name text, provider_id uuid, evidence_id uuid, lifecycle_status text default 'active', publication_status text default 'published');
create table pipeline.scholarship_pages (scholarship_id uuid primary key, url text, evidence_id uuid, requested_at timestamptz);
create table pipeline.scholarship_page_candidates (id bigint generated always as identity primary key, provider_id uuid, url text, title text, source text, final_url text, storage_path text,
  content_hash text, evidence_id uuid, read_at timestamptz, read_status text, next_read_at timestamptz, leased_until timestamptz, facts jsonb, admit_status text, admit_reasons text[],
  admitted_scholarship_id uuid, matched_scholarship_id uuid);
create table pipeline.scholarship_discovery_providers (provider_id uuid primary key, method text);
create table pipeline.scholarship_ai_models (code text primary key, model_identifier text);
create table pipeline.scholarship_ai_prompts (version int primary key, text text, active boolean default true);
create table pipeline.scholarship_ai_queue (id bigint generated always as identity primary key, model_code text not null references pipeline.scholarship_ai_models(code), prompt_version int not null,
  run_kind text not null check (run_kind = any (array['qualify', 'admit', 'reread', 'test'])), job_id uuid, sample_id int, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text not null,
  state text not null default 'queued' check (state = any (array['queued', 'leased', 'done', 'failed'])), attempts int not null default 0, leased_until timestamptz,
  next_try_at timestamptz not null default now(), created_at timestamptz not null default now(), done_at timestamptz, extraction_id bigint, step int not null default 1, storage_path text,
  root_id bigint, skip_reason text);
create table pipeline.scholarship_ai_extractions (id bigint generated always as identity primary key, queue_id bigint, model_code text, model_identifier text, prompt_version int, run_kind text,
  job_id uuid, sample_id int, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, storage_path text, content_hash text, evidence_id uuid, answer jsonb, checks jsonb,
  verdict text, applied jsonb, cost_usd numeric, tokens_in int, tokens_out int, seconds numeric, error text, at timestamptz not null default now());
create table pipeline.scholarship_ai_extract_settings (id int primary key default 1, ai_admission boolean not null default false, calls_at_once int not null default 3, chain text[] not null default '{}',
  confirm_admissions boolean not null default true);
create table pipeline.scholarship_ai_reviews (id bigint generated always as identity primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text not null, storage_path text,
  extraction_ids bigint[] not null default '{}', reason text not null, status text not null default 'pending' check (status = any (array['pending', 'admitted', 'refused', 'superseded'])),
  decided_by uuid, decided_at timestamptz, note text, decision jsonb, created_at timestamptz not null default now(), recheck jsonb);

-- the chain helpers the record reads (same rules as live: the chain order; an error or an unproven name is unsettled)
create or replace function security.scholarship_ai_next_model_v1(p text) returns text language sql stable as $$
  select s.chain[array_position(s.chain, p) + 1] from pipeline.scholarship_ai_extract_settings s where s.id = 1 $$;
create or replace function security.scholarship_ai_unsettled_v1(a jsonb, c jsonb, v text, e text) returns text language sql immutable as $$
  select case when e is not null then 'the model''s reply failed: ' || e when v is distinct from 'scholarship' then null when not coalesce((c->>'name')::boolean, false) then 'the name is not proven'
              when not coalesce((c->>'audience')::boolean, false) then 'who it is for is not proven by a quote on the page' end $$;
create or replace function security.scholarship_ai_active_v1() returns table(model_code text, prompt_version int, model_identifier text, ai_admission boolean) language sql stable as $$
  select s.chain[1], 2, m.model_identifier, s.ai_admission from pipeline.scholarship_ai_extract_settings s left join pipeline.scholarship_ai_models m on m.code = s.chain[1] where s.id = 1 $$;
create table pipeline.fx_calls (id bigint generated always as identity, fn text, arg text);
create or replace function security.scholarship_ai_fire_v1() returns integer language sql as $$ insert into pipeline.fx_calls(fn) values ('fire') returning 1 $$;
-- admission and the person's decision: recorded only (the fixture proves a request-bound answer never reaches them)
create or replace function security.scholarship_ai_apply_v1(p bigint) returns jsonb language sql as $$ insert into pipeline.fx_calls(fn, arg) values ('apply', p::text) returning jsonb_build_object('applied', true) $$;
create or replace function security.scholarship_ai_review_apply_v1(p_review bigint, p_decision text, p_extraction bigint, p_note text, p_by uuid) returns jsonb language plpgsql as $$
begin
  insert into pipeline.fx_calls(fn, arg) values ('review_apply', p_review || ':' || p_decision);
  update pipeline.scholarship_ai_reviews set status = case when p_decision = 'admit' then 'admitted' else 'refused' end, decided_by = p_by, decided_at = now(), note = p_note where id = p_review;
  return jsonb_build_object('review', p_review, 'decision', p_decision);
end $$;
