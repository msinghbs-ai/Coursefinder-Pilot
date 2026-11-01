-- E16 course page check: isolated fixture database (CF-247 E16, Platform Admin 2 Nov 2026 07:21).
-- The smallest set of schemas, tables and helper functions the binding guard, the award-link lane, the AI reader's page choice and the
-- search projection need, with the columns they use. Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh.
-- Nothing here is a copy of live data. Helper functions that are not changed by E16 are simple stand-ins.
create schema if not exists extensions; create extension if not exists pgcrypto schema extensions;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists search;
create schema if not exists ref; create schema if not exists scholarship; create schema if not exists auth;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role service_role; exception when duplicate_object then null; end $$;
create function auth.role() returns text language sql stable as $f$ select 'service_role'::text $f$;

create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create table pipeline.component_register(kind text, name text, layer text, area text, purpose text, status text, replaces text[], introduced_in text, unique (kind, name));

-- catalogue
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 text);
create table ref.study_levels(id uuid primary key default gen_random_uuid(), code text unique, name text, short_code text, sort_order int);
insert into ref.study_levels(code, name) values ('graduate_certificate', 'Graduate Certificate'), ('graduate_diploma', 'Graduate Diploma'), ('masters_coursework', 'Masters Degree (Coursework)'),
  ('bachelor', 'Bachelor'), ('bachelor_honours', 'Bachelor Honours Degree'), ('diploma', 'Diploma'), ('certificate_iv', 'Certificate IV'), ('senior_secondary_certificate', 'Senior Secondary'),
  ('non_aqf_award', 'Non AQF Award');
create table catalogue.providers(id uuid primary key, canonical_name text, display_name text, website text, country_id uuid);
create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text, display_title text, course_code text, study_level_id uuid, course_url text,
  lifecycle_status text default 'active', open_to_international boolean default true, open_to_domestic boolean, delivery_mode text, updated_at timestamptz default now());
create table catalogue.course_identifiers(id uuid primary key default gen_random_uuid(), course_id uuid, provider_id uuid, scheme text, identifier text);
create table catalogue.course_regulatory_observations(id uuid primary key default gen_random_uuid(), course_id uuid, vet_national_code text);
create table catalogue.campuses(id uuid primary key default gen_random_uuid(), provider_id uuid, name text, status text default 'active');
create table catalogue.course_campuses(course_id uuid, campus_id uuid, primary key (course_id, campus_id));
create table pipeline.sources(id uuid primary key default gen_random_uuid(), source_type text, provider_id uuid, label text);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), storage_path text, content_hash text, source_url text);
create table catalogue.course_links(id uuid primary key default gen_random_uuid(), course_id uuid, link_type text default 'official_course', url text, audience text, label text,
  is_primary boolean default false, status text default 'active', valid_from date, valid_to date, source_id uuid, evidence_id uuid, confidence numeric, last_verified_at timestamptz,
  updated_at timestamptz default now(), unique (course_id, link_type, url));
create table catalogue.course_fees(id uuid primary key default gen_random_uuid(), course_id uuid, status text, fee_type text, audience text, amount numeric, fee_year int, currency_code text,
  basis text, load_basis text, campus_id uuid, valid_from date, valid_to date, last_verified_at timestamptz, source_id uuid, updated_at timestamptz);
create table catalogue.course_intakes(id uuid primary key default gen_random_uuid(), course_id uuid, intake_label text, intake_year int, start_date date, application_deadline date,
  campus_id uuid, status text, source_id uuid);
create table ref.english_tests(id uuid primary key, code text, name text);
create table catalogue.course_english_requirements(id uuid primary key, course_id uuid, english_test_id uuid, overall_score numeric, component_scores jsonb, notes text,
  valid_from date, valid_to date, last_verified_at timestamptz, source_id uuid, status text);

-- pipeline
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid not null, url text, score numeric, runner_up numeric, basis text, status text not null,
  bound_at timestamptz not null default now(), read_status text, read_at timestamptz, http_status int, fetched_via text, identity_basis text, evidence_id uuid, candidates jsonb,
  leased_until timestamptz, read_attempts int not null default 0, next_read_at timestamptz, l3_work_item_id uuid, l3_handoff_at timestamptz);
create table pipeline.page_rejections(course_id uuid, url text, provider_id uuid not null, evidence_id uuid, source text not null, reason text not null, signals jsonb not null,
  rejected_at timestamptz not null default now(), rejected_by uuid, primary key (course_id, url));
create table pipeline.course_page_blocks(course_id uuid, url text, reason text, primary key (course_id, url));
create table pipeline.manual_locks(entity text, entity_id uuid, field text);
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid references pipeline.evidence_artifacts(id),
  before_value jsonb, proposed_value jsonb, layer2_state jsonb not null default '{}', layer3_state jsonb not null default '{}', status text not null default 'pending', escalation_reason text,
  change_control_ref text, created_at timestamptz default now(), decided_at timestamptz);
create table pipeline.course_exit_awards(child_course_id uuid primary key, parent_course_id uuid, provider_id uuid, exit_years numeric, page_url text, evidence_id uuid, printed text,
  active boolean default true, set_by text default 'adapter', link_type text default 'nested_award', register_check text default 'pass', applied_at timestamptz, annual_fee numeric,
  fee_year int, total_fee numeric);
create table pipeline.uni_adapters(provider_id uuid, enabled boolean, admit boolean, admit_fields text[]);
create table pipeline.adapter_overwrite_changes(course_id uuid, provider_id uuid, field text, before jsonb, after jsonb, evidence_id uuid, page_url text);
create table pipeline.uni_adapter_results(course_id uuid, fields jsonb, at timestamptz);
create table pipeline.admin_jobs(id uuid primary key, args jsonb default '{}', progress jsonb, result jsonb, updated_at timestamptz);
create table pipeline.field_enrich_items(id bigserial primary key, job_id uuid, provider_id uuid, course_id uuid, field text, state text default 'queued', source text, tried text[] default '{}',
  reason text, value jsonb, quote text, evidence_id uuid, storage_path text, attempts int default 0, leased_until timestamptz, cost_usd numeric, updated_at timestamptz default now());
create table search.refresh_requests(id bigserial primary key, requested_by text);
create table pipeline.course_remediation_holds(course_id uuid, lifted_at timestamptz);

-- helpers the changed functions call (stand-ins; their behaviour is not under test here)
create function security.refused_host(p_url text) returns boolean language sql stable as $f$ select coalesce(p_url, '') ~* '^https?://[^/]*(facebook|seek)\.' $f$;
create function security.not_course_page_v1(p_url text) returns boolean language sql stable as $f$ select coalesce(p_url, '') ~* '/library/' $f$;
create function security.course_held_v1(p_course uuid) returns boolean language sql stable as
  $f$ select exists (select 1 from pipeline.course_remediation_holds h where h.course_id = p_course and h.lifted_at is null) $f$;
create function security.page_refused_v1(p_course uuid, p_url text) returns boolean language sql stable as
  $f$ select exists (select 1 from pipeline.page_rejections r where r.course_id = p_course and r.url = p_url)
         or exists (select 1 from pipeline.course_page_blocks b where b.course_id = p_course and b.url = p_url) $f$;
create function security.course_title_key(p text) returns text language sql immutable set search_path to '' as
  $f$ select btrim(regexp_replace(replace(lower(coalesce(p, '')), '&', ' and '), '[^a-z0-9]+', ' ', 'g')) $f$;
create function security.coverage_sweep_source(p_provider_id uuid) returns uuid language sql as
  $f$ select coalesce((select id from pipeline.sources where source_type = 'provider_course_page_sweep' and provider_id = p_provider_id limit 1),
                      (select id from pipeline.sources where source_type = 'provider_course_page_sweep' limit 1)) $f$;
create function security.layer4_entity_or_parent_blocked(p_type text, p_id uuid, p_mode text) returns boolean language sql stable as $f$ select false $f$;
create function security.own_page_value_v1(p_course uuid, p_field text) returns boolean language sql stable as $f$ select false $f$;
create function security.uni_adapter_excluded(p_course uuid, p_field text) returns boolean language sql stable as $f$ select false $f$;
-- the link writer: the same insert the live security.coverage_apply_course_v1 makes for payload course_url
create function security.coverage_apply_course_v1(p_course_id uuid, p_source_id uuid, p_evidence_id uuid, p_url text, p_hash text, p_payload jsonb) returns jsonb language sql as $f$
  insert into catalogue.course_links(course_id, link_type, url, audience, label, is_primary, status, source_id, evidence_id, confidence, last_verified_at, updated_at)
  values (p_course_id, 'official_course', btrim(p_payload->>'course_url'), 'international', 'Official provider course page', false, 'active', p_source_id, p_evidence_id, 1, now(), now())
  on conflict (course_id, link_type, url) do update set status = 'active', source_id = excluded.source_id, evidence_id = excluded.evidence_id, confidence = 1, last_verified_at = now(), updated_at = now()
  returning jsonb_build_object('links_applied', 1) $f$;
create function search.refresh_course_enrichment_scoped_v1(p_ids uuid[], p_apply boolean) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
-- AI reader helpers
create function security.field_sources_for_v1(p_cc text, p_field text) returns text[] language sql stable as $f$ select array['ai_stored'] $f$;
create function security.gap_scraper_room_v1() returns boolean language sql stable as $f$ select true $f$;
create function security.enrich_fallback_v1(p_item bigint) returns boolean language sql as $f$ select false $f$;
create function security.enrich_campus_link_v1(p_job uuid) returns void language sql as $f$ select $f$;
create function security.enrich_ai_fire_v1() returns void language sql as $f$ select $f$;
create function security.campus_regions_apply_v1() returns void language sql as $f$ select $f$;
create function security.enrich_apply_v1(p_item bigint) returns void language sql as $f$ select $f$;
create function security.enrich_parse_duration_v1(p text) returns jsonb language sql as $f$ select null::jsonb $f$;
create function security.enrich_parse_level_v1(p text) returns uuid language sql as $f$ select null::uuid $f$;
create function security.delivery_mode_read_v1(p text, p_provider uuid) returns text language sql as $f$ select null::text $f$;
create function security.third_party_host_v1(p_url text) returns boolean language sql as $f$ select false $f$;
create table catalogue.provider_identifiers(provider_id uuid, scheme text, identifier text);

-- search projection
create table search.enrichment_gates(projection_code text, domain_code text, gate_status text);
create table search.enrichment_source_gates(projection_code text, domain_code text, source_id uuid, gate_status text);
create table search.course_documents(course_id uuid primary key, country_code text, official_course_url text, enrichment_content_hash text);
create table scholarship.scholarships(id uuid primary key, stable_key text, name text, academic_year text, application_close_date date, source_url text, audience text, nationalities text[],
  award_value_is_maximum boolean, lifecycle_status text, publication_status text);
create table scholarship.course_mappings(id uuid primary key, course_id uuid, scholarship_id uuid, mapping_state text);
create table scholarship.course_financial_calculations(mapping_id uuid, calculation_status text, scholarship_saving_amount numeric, currency_code text, fee_basis text);
create function scholarship.value_label(p uuid) returns text language sql as $f$ select null::text $f$;
insert into search.enrichment_gates values ('courses', 'official_course_url', 'approved');

-- the binding guard trigger as it is live before E16 (created 4 Oct 2026)
create trigger coverage_page_refused_host before insert or update of url, status on pipeline.coverage_course_pages
  for each row execute function security.coverage_page_refused_host_guard();
