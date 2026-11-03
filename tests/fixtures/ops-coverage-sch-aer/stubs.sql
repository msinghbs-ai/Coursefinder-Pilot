-- Workstream C fixtures: the live shapes the scholarship and coverage functions read, added to the AER Phase B fixture database
-- (../aer-phase-b/stubs.sql, whose AER tables carry their live columns). Columns read on fxcwkweaxjtknorudmwp, 3 Nov 2026 15:43-15:56 AEDT.
-- Helpers with their live semantics: provider_hidden_v1 (view, 20261010006800), third_party_host_v1 (directory hosts), provider_sch_search_off_v1,
-- fc_sch_eligible_v1 (the live rule: outside AU, or at least scholarship_min_courses active courses), scholarship_flag_v1 (live text).
create schema if not exists scholarship;
insert into pipeline.platform_toolsets values ('firecrawl') on conflict do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('firecrawl', 'daily_budget_on', 'Firecrawl daily budget', 'boolean', 'true'),
  ('firecrawl', 'scholarship_min_courses', 'Scholarship minimum courses', 'number', '30'),
  ('pipeline', 'retry.scholarship_discovery_held_hours', 'Held discovery retry', 'number', '6'),
  ('pipeline', 'reread.scholarship_discovery_days', 'Discovery re-read', 'number', '30')
on conflict do nothing;
alter table ref.countries add column if not exists scholarship_ingestion_enabled boolean not null default true;
alter table catalogue.providers add column if not exists website text;

create or replace view security.provider_hidden_v1 as
  select p.id as provider_id from catalogue.providers p where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';
create table if not exists pipeline.provider_scholarship_search(provider_id uuid primary key, enabled boolean not null default true);
create or replace function security.provider_sch_search_off_v1(p uuid) returns boolean language sql stable as
  $f$ select exists (select 1 from pipeline.provider_scholarship_search s where s.provider_id = p and not s.enabled) $f$;
create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable as
  $f$ select coalesce(p_url, '') ~* '(studymelbourne|acir\.com\.au|topaustraliauniversities)' $f$;
create or replace function security.fc_setting_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = p_key), p_default) $f$;
create or replace function security.scholarship_flag_v1(p_key text, p_default boolean) returns boolean language sql stable security definer set search_path to '' as $function$
  select coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;

create table pipeline.scholarship_discovery_providers(provider_id uuid primary key references catalogue.providers(id), website text, site_origin text, priority int,
  reason text, status text, method text, url_count int, kept_count int, matched_count int, attempts int not null default 0, leased_until timestamptz,
  discovered_at timestamptz, last_error text, updated_at timestamptz default now(), allowed_hosts text[], tier smallint, next_discover_at timestamptz, sources_mapped jsonb);
create table pipeline.scholarship_listing_pages(id bigserial primary key, provider_id uuid, url text, url_norm text, source text, active boolean default true, status text,
  http_status int, read_at timestamptz, next_read_at timestamptz, items jsonb, item_hash text, error text, added_by uuid, added_at timestamptz, page_state text,
  pages_read int, total_stated int, next_url text, paging jsonb, completed_at timestamptz);
create table pipeline.scholarship_listing_members(listing_id bigint, provider_id uuid, item_key text, name text, url text, code text, kind text, candidate_id bigint,
  held_scholarship_id uuid, first_seen timestamptz, last_seen timestamptz, present boolean default true);
create table pipeline.scholarship_page_candidates(id bigserial primary key, provider_id uuid, url text, url_norm text, title text, source text, found_at timestamptz default now(),
  matched_scholarship_id uuid, match_basis text, matched_at timestamptz, read_status text, http_status int, fetched_via text, final_url text, read_at timestamptz,
  attempts int default 0, leased_until timestamptz, next_read_at timestamptz, storage_path text, content_hash text, facts jsonb, admit_status text, admit_reasons text[],
  admitted_scholarship_id uuid, admitted_at timestamptz, requested_at timestamptz, evidence_id uuid);
create table pipeline.scholarship_publication_holds(scholarship_id uuid, reason text, held_by text, held_at timestamptz default now(), released_at timestamptz, release_note text);
create table scholarship.scholarships(id uuid primary key default gen_random_uuid(), stable_key text, provider_id uuid, name text, scholarship_type text, description text,
  audience text, award_value_text text, application_required boolean, application_open_date date, application_close_date date, academic_year int, source_url text,
  lifecycle_status text default 'active', publication_status text default 'published', source_id uuid, evidence_id uuid, confidence numeric,
  created_at timestamptz default now(), updated_at timestamptz default now(), award_value_type text, award_percentage numeric, award_amount numeric,
  award_currency_code character(3), award_applies_to_fee_type text, award_fee_basis text, award_duration_basis text, award_value_is_maximum boolean,
  nationalities text[], application_open_precision text, application_close_precision text, study_start_label text, study_start_date date);
create table scholarship.scopes(id uuid primary key default gen_random_uuid(), scholarship_id uuid, scope_type text, provider_id uuid, course_id uuid, course_collection_id uuid,
  study_level_id uuid, field_id uuid, country_id uuid, campus_id uuid, include_exclude text, source_id uuid, evidence_id uuid, created_at timestamptz default now(), cycle_id uuid);
create table scholarship.criteria(id uuid primary key default gen_random_uuid(), scholarship_id uuid, criterion_type text, operator text, value_text text, value_number numeric,
  value_codes text[], value_json jsonb, human_text text, is_mandatory boolean, machine_evaluable boolean, status text, source_id uuid, evidence_id uuid, confidence numeric,
  created_at timestamptz default now(), cycle_id uuid, criterion_group_id uuid);
create table scholarship.award_tiers(id uuid primary key default gen_random_uuid(), scholarship_id uuid, tier_code text, label text, amount numeric);
create table scholarship.application_windows(id uuid primary key default gen_random_uuid(), scholarship_id uuid, cycle_id uuid, round_code text, label text,
  opens_at timestamptz, closes_at timestamptz, application_method text, application_url text, status text);
create table scholarship.register_listings(register_code text, listing_id text, country_code character(2), url text, name text, provider_ref text, provider_name text,
  provider_cricos text, provider_id uuid, level_text text, award_text text, closing_text text, nationality_text text, website_url text, content_hash text,
  scholarship_id uuid, match_basis text, candidate_id bigint, handoff_status text, detail_hash text, detail_read_at timestamptz, detail_error text,
  detail_evidence_id uuid, evidence_id uuid, first_seen_at timestamptz default now(), last_seen_at timestamptz default now(), departed_at timestamptz, last_run_id uuid);
create table catalogue.course_intakes(id uuid primary key default gen_random_uuid(), course_id uuid, intake_year int, intake_label text, start_date date,
  application_deadline date, campus_id uuid, status text default 'active', source_id uuid, evidence_id uuid, confidence numeric, source_intake_key text);
-- the scholarship admission rule as live with both proposals off: universities only (security.scholarship_university)
create or replace function security.scholarship_admission_provider_ok_v1(p uuid) returns boolean language sql stable as
  $f$ select exists (select 1 from catalogue.providers x join ref.provider_types t on t.id = x.provider_type_id where x.id = p and t.code in ('university')) $f$;
