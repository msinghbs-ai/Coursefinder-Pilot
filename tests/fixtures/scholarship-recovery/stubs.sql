-- CF-247 Scholarship Coverage Recovery: isolated fixture database. Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh.
-- The scholarship pipeline tables carry their live column definitions (information_schema on fxcwkweaxjtknorudmwp, read 2 Nov 2026 ~20:40 AEDT,
-- with the live unique keys and checks the code relies on); the platform tables and helper functions carry the columns and the behaviour the
-- functions under test use. No live data.
create extension if not exists pgcrypto;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists ref; create schema if not exists cron; create schema if not exists scholarship; create schema if not exists net; create schema if not exists pim;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role service_role; exception when duplicate_object then null; end $$;

-- settings (the live readers' semantics)
create table pipeline.platform_toolsets(key text primary key);
insert into pipeline.platform_toolsets values ('pipeline'), ('firecrawl');
create table pipeline.platform_toolset_settings(toolset_key text not null references pipeline.platform_toolsets(key), key text not null, label text not null, help text not null default '',
  kind text not null check (kind in ('number', 'text', 'boolean', 'list')), value jsonb not null, min_value numeric, max_value numeric, unit text, sort int not null default 100,
  reason text, updated_by uuid, updated_at timestamptz not null default now(), section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('firecrawl', 'daily_budget_on', 'Daily budget', 'boolean', 'true'),            -- the normal value after the 16:39 authority expired
  ('firecrawl', 'scholarship_min_courses', 'Min courses', 'number', '30'),
  ('firecrawl', 'scholarship_cap_per_uni', 'Cap per university', 'number', '150'),
  ('firecrawl', 'daily_share_scholarships', 'Scholarship share', 'number', '3500'),
  ('pipeline', 'hygiene.retire_after_days', 'Retire after', 'number', '14');
create table pipeline.scholarship_layer_settings(key text not null primary key, layer integer not null, label text not null, help text not null, value numeric not null, min_value numeric not null, max_value numeric not null, unit text not null, updated_at timestamp with time zone not null default now(), updated_by uuid, reason text);
insert into pipeline.scholarship_layer_settings(key, layer, label, help, value, min_value, max_value, unit) values
  ('firecrawl_cap', 2, 'Scraper credits for scholarships', '', 60000, 0, 100000, 'credits'), ('firecrawl_reserve', 2, 'Reserve', '', 800, 0, 10000, 'credits'),
  ('discover_limit', 2, 'Universities searched per run', '', 6, 1, 30, 'universities'), ('candidate_read_limit', 2, 'Candidate pages read per run', '', 30, 1, 60, 'pages'),
  ('read_limit', 2, 'Scholarship pages re-read per run', '', 40, 1, 200, 'pages');

-- the caller
create table auth.session(role text);
insert into auth.session values ('service_role');
create function auth.role() returns text language sql stable as $f$ select role from auth.session limit 1 $f$;

-- scheduler and outbound requests (pg_cron and pg_net as the code uses them)
create table cron.job(jobid bigserial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as
  $f$ insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $f$;
create function cron.alter_job(job_id bigint, active boolean) returns void language sql as $f$ update cron.job set active = alter_job.active where jobid = job_id $f$;
create table net._http_response(id bigint primary key, status_code int, content text);
create table pipeline.edge_request_log(slot int, request_id bigint, function_name text, mode text, created_at timestamptz default now());
create table fx_sent(body jsonb, at timestamptz default now());
create function pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb) returns bigint language sql as
  $f$ insert into public.fx_sent(body) values (p_body); insert into pipeline.edge_request_log(request_id, function_name, mode) values (null, p_function, p_body->>'mode'); select 1::bigint $f$;

-- reference and catalogue
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 character(2) not null, scholarship_ingestion_enabled boolean not null default false);
create table ref.provider_types(id uuid not null default gen_random_uuid() primary key, code text not null, name text not null, description text, status text not null default 'active'::text);
create table catalogue.providers(id uuid primary key default gen_random_uuid(), canonical_name text, display_name text, country_id uuid not null, website text,
  lifecycle_status text not null default 'active', publication_status text not null default 'published', enrols_international boolean, provider_type_id uuid, provider_type_basis text);
create table catalogue.courses(id uuid primary key default gen_random_uuid(), provider_id uuid not null, course_code text, lifecycle_status text not null default 'active');
create table fx_groups(provider_id uuid);
create function security.provider_university_groups(p uuid) returns jsonb language sql stable as $f$ select case when exists (select 1 from public.fx_groups g where g.provider_id = p) then '["go8"]'::jsonb else '[]'::jsonb end $f$;
create table fx_hidden(provider_id uuid);
create view security.provider_hidden_v1 as select provider_id from public.fx_hidden;
create function security.third_party_host_v1(p_url text) returns boolean language sql stable as $f$ select coalesce(p_url, '') ~* '(oneuedu|findthecourses)' $f$;
create table pipeline.provider_scholarship_search(provider_id uuid not null primary key, enabled boolean not null, auto boolean not null default false, reason text, set_by uuid, set_at timestamptz not null default now());
create function security.provider_sch_search_off_v1(p uuid) returns boolean language sql stable as $f$ select exists (select 1 from pipeline.provider_scholarship_search s where s.provider_id = p and not s.enabled) $f$;
create function security.provider_sch_search_auto_v1() returns void language sql as $f$ select $f$;
create function security.provider_name_list(p uuid) returns jsonb language sql stable as $f$ select '[]'::jsonb $f$;
create function security.scholarship_held_without_page(p uuid) returns jsonb language sql stable as $f$ select '[]'::jsonb $f$;
create function security.fc_sch_cap_since_v1(p uuid) returns timestamptz language sql stable as $f$ select now() - interval '30 days' $f$;
create table pipeline.coverage_vendor_usage(id bigserial, units numeric, purpose text, provider_id uuid, url text, at timestamptz default now());
create table pipeline.coverage_provider_discovery(provider_id uuid, website text, status text);
create table pipeline.onboarding_pilot(cohort text not null, provider_id uuid not null, country text, picked_at timestamp with time zone not null default now(), baseline jsonb not null default '{}'::jsonb);
create function security.url_on_provider_sites(p_url text, p uuid) returns boolean language sql stable as
  $f$ select exists (select 1 from catalogue.providers pr where pr.id = p and substring(lower(p_url) from '^https?://(?:www\.)?(?:[a-z0-9-]+\.)*?([a-z0-9-]+\.edu\.au)') = substring(lower(pr.website) from '^https?://(?:www\.)?(?:[a-z0-9-]+\.)*?([a-z0-9-]+\.edu\.au)')) $f$;
create function security.url_on_provider_site(p_url text, p_origin text) returns boolean language sql stable as
  $f$ select substring(lower(p_url) from '^https?://(?:www\.)?([^/]+)') = substring(lower(p_origin) from '^https?://(?:www\.)?([^/]+)') $f$;

-- scholarship records and pipeline (live columns)
create table scholarship.scholarships(id uuid primary key, stable_key text, provider_id uuid, name text, scholarship_type text, audience text, source_url text,
  lifecycle_status text, publication_status text, source_id uuid, evidence_id uuid, confidence numeric, award_value_type text, updated_at timestamptz,
  application_open_date date, application_close_date date);
create function scholarship.normalise_title(t text) returns text language sql immutable as $f$ select lower(regexp_replace(coalesce(t, ''), '[^a-z0-9]+', ' ', 'gi')) $f$;
create function scholarship.provider_currency(p uuid) returns text language sql stable as $f$ select 'AUD' $f$;
create function scholarship.deterministic_uuid(k text) returns uuid language sql immutable as $f$ select md5(k)::uuid $f$;
create table scholarship.identifiers(scholarship_id uuid, scheme text, identifier_value text, source_id uuid, evidence_id uuid, is_primary boolean, status text, unique (scholarship_id, scheme, identifier_value));
create table pim.entity_registry(id uuid, entity_type text, stable_key text unique, lifecycle_status text, updated_at timestamptz);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), entity_id uuid, source_id uuid, evidence_type text, source_url text, storage_path text, content_hash text,
  mime_type text, metadata jsonb, capture_version int, evidence_group_key text, supersedes_evidence_id uuid);
create table pipeline.scholarship_acquisition_trace(provider_id uuid, observed_title text, first_party_detail_url text, scholarship_id uuid, verification_evidence_id uuid, stage text,
  verification_status text, observed_at timestamptz, verified_at timestamptz, updated_at timestamptz, metadata jsonb);
create table pipeline.scholarship_admission_log(candidate_id bigint, scholarship_id uuid, provider_id uuid, action text, detail jsonb);
create function security.coverage_sweep_source(p uuid) returns uuid language sql stable as $f$ select '00000000-0000-0000-0000-0000000000aa'::uuid $f$;
create function security.reference_url_has_use(u text, k text) returns boolean language sql stable as $f$ select false $f$;
create function security.scholarship_page_match_v1(s uuid, u text, b text, c bigint) returns jsonb language sql as $f$ select '{"matched": false}'::jsonb $f$;
create function security.scholarship_sweep_apply_v1(s uuid) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create function security.scholarship_admission_withdraw_v1(s uuid, r jsonb) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create table pipeline.scholarship_ai_extract_settings(id int primary key, ai_admission boolean);
insert into pipeline.scholarship_ai_extract_settings values (1, true);
create table pipeline.scholarship_ai_models(model_code text, status text);
insert into pipeline.scholarship_ai_models values ('qwen3-30b', 'active');
create table pipeline.scholarship_ai_queue(id bigserial, model_code text, prompt_version text, run_kind text, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, state text default 'queued');
create function security.scholarship_ai_active_v1() returns table(model_code text, prompt_version text) language sql stable as $f$ select 'qwen3-30b'::text, 'v2'::text $f$;

create table pipeline.scholarship_discovery_providers(provider_id uuid not null primary key, website text not null, site_origin text, priority integer not null, reason text not null, status text not null default 'pending'::text, method text, url_count integer, kept_count integer, matched_count integer, attempts integer not null default 0, leased_until timestamp with time zone, discovered_at timestamp with time zone, last_error text, updated_at timestamp with time zone not null default now(), allowed_hosts text[] not null default '{}'::text[]);
create table pipeline.scholarship_page_candidates(id bigserial primary key, provider_id uuid not null, url text not null, url_norm text not null, title text, source text not null check ((source = any (array['sitemap'::text, 'map'::text, 'search'::text, 'register'::text]))), found_at timestamp with time zone not null default now(), matched_scholarship_id uuid, match_basis text, matched_at timestamp with time zone, read_status text, http_status integer, fetched_via text, final_url text, read_at timestamp with time zone, attempts integer not null default 0, leased_until timestamp with time zone, next_read_at timestamp with time zone not null default now(), storage_path text, content_hash text, facts jsonb, admit_status text, admit_reasons text[], admitted_scholarship_id uuid, admitted_at timestamp with time zone, requested_at timestamp with time zone, evidence_id uuid, unique (provider_id, url_norm));
create table pipeline.scholarship_listing_pages(id bigserial primary key, provider_id uuid not null, url text not null, url_norm text not null, source text not null check ((source = any (array['auto'::text, 'suggested'::text, 'manual'::text]))), active boolean not null default true, status text not null default 'waiting'::text check ((status = any (array['waiting'::text, 'read'::text, 'failed'::text, 'suggested'::text]))), http_status integer, read_at timestamp with time zone, next_read_at timestamp with time zone default now(), items jsonb not null default '[]'::jsonb, item_hash text, error text, added_by uuid, added_at timestamp with time zone not null default now(), unique (provider_id, url_norm));
create table pipeline.scholarship_pages(scholarship_id uuid not null primary key, url text not null, final_url text, read_status text, http_status integer, fetched_via text, read_at timestamp with time zone, next_read_at timestamp with time zone not null default now(), attempts integer not null default 0, leased_until timestamp with time zone, evidence_id uuid, facts jsonb, applied_at timestamp with time zone, apply_result jsonb, url_source text not null default 'original'::text, candidate_id bigint, name_check jsonb, requested_at timestamp with time zone);
create table pipeline.scholarship_skip_rules(id bigserial primary key, pattern text not null, label text not null, active boolean not null default true, unless_pattern text not null default '(scholarship|bursar|stipend|grant)'::text, reason text, added_by uuid, added_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now());
create table pipeline.scholarship_sweep_changes(id bigserial primary key, scholarship_id uuid not null, field text not null, before_value jsonb, after_value jsonb, evidence_id uuid, changed_at timestamp with time zone not null default now());

-- platform tables
create table pipeline.mode_outcome_ledger(id bigserial primary key, run_at timestamp with time zone not null default now(), mode text not null, status integer not null default 200, ms integer, items integer not null default 0, ok integer not null default 0, failed integer not null default 0, wait_ms integer, landed jsonb not null default '{}'::jsonb, worker text, detail jsonb);
create function security.worker_call_work_v1(t text) returns int language sql immutable as
  $f$ select coalesce((regexp_match(t, '"items":\s*(\d+)'))[1]::int, (regexp_match(t, '"done":\s*(\d+)'))[1]::int, 0) $f$;
create table pipeline.platform_issues(id uuid not null default gen_random_uuid() primary key, check_key text not null, severity text not null, area text not null, title text not null, detail jsonb not null default '{}'::jsonb, first_seen timestamp with time zone not null default now(), last_seen timestamp with time zone not null default now(), occurrences integer not null default 1, resolved_at timestamp with time zone, acknowledged_by uuid, acknowledged_at timestamp with time zone, acknowledged_note text);
create unique index platform_issues_open_uq on pipeline.platform_issues (check_key) where resolved_at is null;
create table pipeline.automation_catalogue(jobname text not null primary key, area text not null, sort integer not null default 100, label text not null, description text not null, control_rank integer not null default 5, batch_editable boolean not null default false, layer23_stage text);
create table pipeline.component_register(kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active'::text, replaces text[] not null default '{}'::text[], replaced_by text, introduced_in text, retire_after date, last_used_at timestamp with time zone, usage jsonb not null default '{}'::jsonb, size_bytes bigint, note text, registered_at timestamp with time zone not null default now(), updated_at timestamp with time zone not null default now(), primary key (kind, name));
insert into pipeline.component_register(kind, name, layer) values ('function', 'public.svc_scholarship_listing_record', 'Layer 2');
