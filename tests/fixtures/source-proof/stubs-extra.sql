-- Live shapes for the source-proof lane and field backlog fixtures (CF-247 mandate 3 Nov 2026 12:04 §5, §6), added to the lanes fixture's own
-- stubs (../lanes-gap-queue/stubs.sql). Only the columns the definitions under test read or write; read-only from production on 3 Nov 2026
-- (information_schema). Never a Supabase project.
set check_function_bodies = off;
alter table catalogue.courses add column course_code text;
alter table catalogue.providers add column country_id uuid, add column provider_type_id uuid, add column publication_status text default 'published', add column description text;
alter table pipeline.course_link_search add column stage text, add column query text, add column req_id bigint, add column attempts int not null default 0, add column results jsonb,
  add column candidates jsonb, add column cand_idx int, add column bound_url text, add column queued_at timestamptz, add column done_at timestamptz, add column requested_at timestamptz;
alter table pipeline.layer4_review_items add column entity_type text, add column entity_id uuid, add column field_code text, add column created_at timestamptz default now();
alter table pipeline.provider_description_reads add column provider_id uuid, add column evidence_id uuid, add column updated_at timestamptz default now(), add column published_at timestamptz;
alter table pipeline.fee_reader_queue add column provider_id uuid, add column course_id uuid, add column finished_at timestamptz;
alter table pipeline.scholarship_page_candidates add column provider_id uuid, add column admit_status text, add column read_at timestamptz, add column admitted_at timestamptz;
alter table scholarship.scholarships add column lifecycle_status text default 'active';
create schema if not exists ref;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table ref.provider_types (id uuid primary key default gen_random_uuid(), code text);
create table ref.ranking_sources (id uuid primary key default gen_random_uuid(), code text, status text);
create table catalogue.provider_rankings (id uuid primary key default gen_random_uuid(), provider_id uuid, verified_at timestamptz);
create table catalogue.course_entry_requirements (id uuid primary key default gen_random_uuid(), course_id uuid, status text, created_at timestamptz default now(), updated_at timestamptz default now());
create table catalogue.course_fees (id uuid primary key default gen_random_uuid(), course_id uuid, basis text, status text, created_at timestamptz default now());
create table pipeline.course_relink (course_id uuid primary key, provider_id uuid, old_url text, candidates jsonb, sources jsonb, pattern text, state text, reason text, result_url text,
  started_at timestamptz, decided_at timestamptz, rule int);
create table pipeline.coverage_provider_urls (provider_id uuid, url text, primary key (provider_id, url));
create table pipeline.provider_discovery_links (provider_id uuid, url text, primary key (provider_id, url));
create table pipeline.course_link_recipes (provider_id uuid primary key, search_domain text, active boolean);
create table pipeline.provider_priority (provider_id uuid primary key, rank int);
create table pipeline.course_page_blocks (course_id uuid, url text);
create table pipeline.course_attribute_coverage (course_id uuid, provider_id uuid, attribute text, state text, tier text, computed_at timestamptz default now(), country_code text, primary key (course_id, attribute));
create table pipeline.aer_course_outcomes (course_id uuid primary key, outcome text);
create table pipeline.scholarship_discovery_providers (provider_id uuid primary key, status text);
create or replace function security.page_refind_settle_v1() returns void language sql as $$ select $$;
-- the binding a relink candidate gets (live: security.course_link_bind_v1 binds the page for the reader to read)
create or replace function security.course_link_bind_v1(p_course uuid, p_provider uuid, p_url text, p_basis text) returns void language sql as $$
  update pipeline.coverage_course_pages set url = p_url, status = 'bound', read_status = null, identity_basis = null, evidence_id = null where course_id = p_course $$;
create or replace function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint language sql as $$
  insert into cron.job(jobname, schedule, command) values (p_name, p_schedule, p_command) returning jobid $$;
