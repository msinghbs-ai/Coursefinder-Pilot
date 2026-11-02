-- CF-247 pipeline yield checks (Platform Admin direction 2 Nov 2026 23:24 §3): the tables the 20261103040000 migration reads, on top of the
-- integration-queue fixture database (tests/fixtures/integration-queue/stubs.sql and migration 20261102120000). Columns as live (read from
-- information_schema on production, read-only, 2 Nov 2026 23:36-23:57 AEDT), the ones the checks and the yield view use. Nothing here is live data.
create table pipeline.edge_request_log(slot int primary key, request_id bigint, function_name text, mode text, created_at timestamptz default now());
create table pipeline.mode_outcome_ledger(id bigint generated always as identity primary key, run_at timestamptz not null default now(), mode text not null, status int not null default 200,
  ms int, items int not null default 0, ok int not null default 0, failed int not null default 0, wait_ms int, landed jsonb not null default '{}', worker text, detail jsonb);
create table fx.waiting(mode text primary key);
create function security.worker_mode_waiting_v1(p_mode text) returns boolean language sql stable as $f$ select exists (select 1 from fx.waiting w where w.mode = p_mode) $f$;
create view security.provider_hidden_v1 as select id provider_id from catalogue.providers p where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
create table pipeline.provider_course_lists(id uuid primary key default gen_random_uuid(), provider_id uuid, url text, status text, http_status int, fetched_via text, pages_read int,
  links_found int, links_new int, read_attempts int, read_at timestamptz, next_read_at timestamptz, leased_until timestamptz, reason text, added_by uuid,
  created_at timestamptz default now(), updated_at timestamptz default now(), link_pattern text, child_pattern text, read_via text);
create table pipeline.entry_matrix_sources(id uuid primary key default gen_random_uuid(), provider_id uuid, url text, title text, rank int, found_via text, status text, read_via text,
  http_status int, evidence_id uuid, content_hash text, attempts int, read_at timestamptz, error text, created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.scholarship_discovery_providers(provider_id uuid primary key, website text, site_origin text, priority int, reason text, status text, method text, url_count int,
  kept_count int, matched_count int, attempts int, leased_until timestamptz, discovered_at timestamptz, last_error text, updated_at timestamptz, allowed_hosts text[]);
create table pipeline.scholarship_listing_pages(id bigserial primary key, provider_id uuid, url text, url_norm text, source text, active boolean, status text, http_status int,
  read_at timestamptz, next_read_at timestamptz, items jsonb, item_hash text, error text, added_by uuid, added_at timestamptz);
create table pipeline.scholarship_page_candidates(id bigserial primary key, provider_id uuid, url text, url_norm text, title text, source text, found_at timestamptz default now(),
  matched_scholarship_id uuid, match_basis text, matched_at timestamptz, read_status text, http_status int, fetched_via text, final_url text, read_at timestamptz, attempts int,
  leased_until timestamptz, next_read_at timestamptz, storage_path text, content_hash text, facts jsonb, admit_status text, admit_reasons text[], admitted_scholarship_id uuid,
  admitted_at timestamptz, requested_at timestamptz, evidence_id uuid);
create table pipeline.scholarship_pages(scholarship_id uuid primary key, url text, final_url text, read_status text, http_status int, fetched_via text, read_at timestamptz,
  next_read_at timestamptz, attempts int, leased_until timestamptz, evidence_id uuid, facts jsonb, applied_at timestamptz, apply_result jsonb, url_source text, candidate_id bigint,
  name_check jsonb, requested_at timestamptz);
create table pipeline.scholarship_ai_extractions(id bigserial primary key, provider_id uuid, url text, verdict text, error text, at timestamptz default now());
create schema if not exists scholarship;
create table scholarship.scholarships(id uuid primary key default gen_random_uuid(), stable_key text, provider_id uuid, name text, lifecycle_status text, publication_status text,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, url text, score numeric, runner_up numeric, basis text, status text, bound_at timestamptz,
  read_status text, read_at timestamptz, http_status int, fetched_via text, identity_basis text, evidence_id uuid, candidates jsonb, leased_until timestamptz, read_attempts int,
  next_read_at timestamptz, l3_work_item_id uuid, l3_handoff_at timestamptz);
create table catalogue.course_links(id uuid primary key default gen_random_uuid(), course_id uuid, link_type text, url text, audience text, locale text, label text, is_primary boolean,
  status text, valid_from date, valid_to date, source_id uuid, evidence_id uuid, confidence numeric, last_verified_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now());
create table catalogue.provider_entry_matrix(id uuid primary key default gen_random_uuid(), provider_id uuid, course_id uuid, status text, created_at timestamptz default now(), updated_at timestamptz default now());
create table catalogue.course_entry_requirements(id uuid primary key default gen_random_uuid(), course_id uuid, status text, created_at timestamptz default now(), updated_at timestamptz default now());
alter table pipeline.provider_description_reads add column source_url text, add column evidence_id uuid, add column source_captured_at timestamptz, add column proposal jsonb,
  add column published_at timestamptz, add column created_at timestamptz not null default now(), add column updated_at timestamptz not null default now();
-- the provider flag columns the repeated-failures check reads (the integration-queue stubs have no flag table)
create table pipeline.enrichment_flags(id bigserial primary key, entity text not null, entity_key text not null, provider_id uuid, field text not null default '', reason_code text not null,
  reason text, source text, flagged_at timestamptz not null default now(), cleared_at timestamptz, kind text not null default 'hard', state text not null default 'raised', tries int not null default 1);
alter table pipeline.entry_matrix_runs add column error text, add column done_at timestamptz, add column updated_at timestamptz default now();
