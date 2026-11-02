-- CF-247 Workstream C (course description and application deadline): the tables and helpers the guarded and new functions use, cut to the
-- columns they use (shapes as live, 3 Nov 2026; pipeline.field_enrich_items with its live constraints and gate trigger). Nothing here is a
-- Supabase project. Helpers this change neither edits nor reads against are stubs.
create extension if not exists pgcrypto;
do $r$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; create role authenticated; create role service_role; end if; end $r$;
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists ref;
create schema if not exists search; create schema if not exists auth; create schema if not exists scholarship; create schema if not exists net;
-- Supabase auth: a signed-in person is simulated with the settings fx.uid, fx.role and fx.rank
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fx.uid', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('fx.role', true), '') $$;
create table auth.users (id uuid primary key, email text);
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fx.rank', true), '')::int $$;
create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null, kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null, reason text, updated_by uuid, updated_at timestamptz not null default now(), section text not null, used_by text,
  primary key (toolset_key, key));
create table pipeline.platform_toolsets (key text primary key, enforcement text);
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable security definer set search_path = '' as $$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $$;
create function security.pdesc_words_v1(p text) returns text[] language sql immutable set search_path = '' as $$
  select coalesce(array_agg(distinct w), '{}') from regexp_split_to_table(lower(coalesce(p, '')), '[^a-z0-9]+') w where length(w) >= 3 $$;

create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text, name text);
create table ref.study_levels (id uuid primary key default gen_random_uuid(), short_code text, name text, sort_order int);
create table ref.fields_of_study (id uuid primary key default gen_random_uuid(), code text, name text);
create table ref.subdivisions (id uuid primary key default gen_random_uuid(), country_id uuid, name text);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), country_id uuid, canonical_name text, display_name text, lifecycle_status text default 'active',
  address_line1 text, postcode text, primary_city text, website text, enrols_international boolean, stable_key text, description text, updated_at timestamptz);
create table catalogue.courses (id uuid primary key default gen_random_uuid(), provider_id uuid, course_code text, canonical_title text, display_title text, lifecycle_status text default 'active',
  description text, duration_value numeric, duration_unit text, study_level_id uuid, primary_field_id uuid, delivery_mode text, open_to_international boolean, updated_at timestamptz);
create table catalogue.course_intakes (id uuid primary key default gen_random_uuid(), course_id uuid, intake_year int, intake_label text, start_date date, application_deadline date,
  campus_id uuid, status text default 'active', source_id uuid, evidence_id uuid, confidence numeric, source_intake_key text);
create table catalogue.course_campuses (course_id uuid, campus_id uuid, delivery_mode text, is_primary boolean, evidence_id uuid);
create table catalogue.campuses (id uuid primary key default gen_random_uuid(), provider_id uuid, name text, city text, status text default 'active', subdivision_id uuid, country_id uuid, updated_at timestamptz);
create table catalogue.course_english_requirements (course_id uuid, status text);
create table catalogue.course_fees (course_id uuid, audience text, status text, fee_type text);
create table catalogue.course_registrations (course_id uuid, scheme text, status text);
create table catalogue.provider_identifiers (provider_id uuid, scheme text, identifier text);

create table pipeline.admin_jobs (id uuid primary key default gen_random_uuid(), kind text, lane text, state text, title text, args jsonb, progress jsonb, result jsonb,
  requested_by uuid, reason text, scope text, created_at timestamptz default now(), finished_at timestamptz, updated_at timestamptz default now());
create table pipeline.admin_job_events (id bigserial primary key, job_id uuid, note text, detail jsonb, created_at timestamptz default now());
create table pipeline.field_gap_queue_control (id int primary key, enabled boolean, owner uuid, reason text);
create table pipeline.field_enrich_items (id bigserial primary key, job_id uuid references pipeline.admin_jobs(id) on delete cascade,
  provider_id uuid references catalogue.providers(id) on delete cascade, course_id uuid references catalogue.courses(id) on delete cascade,
  field text, state text default 'queued', source text, tried text[] default '{}', value jsonb, quote text, reason text, evidence_id uuid, storage_path text,
  attempts int default 0, leased_until timestamptz, cost_usd numeric default 0, created_at timestamptz default now(), updated_at timestamptz default now(),
  constraint field_enrich_items_state_check check (state = any (array['queued', 'waiting', 'ai', 'leased', 'filled', 'review', 'skipped', 'failed'])),
  unique nulls not distinct (job_id, provider_id, course_id, field));
create index field_enrich_items_course_field_idx on pipeline.field_enrich_items (course_id, field);
create table pipeline.field_source_rules (country_code text, field text, sources text[], reason text, updated_by uuid, updated_at timestamptz, primary key (country_code, field));
create table pipeline.field_register (field text primary key, level text, label text, grp text, sort int, reader text, fills text, target_pct numeric, active boolean,
  reason text, updated_by uuid, updated_at timestamptz);
create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, status text, read_status text, identity_basis text, evidence_id uuid,
  read_at timestamptz, candidates jsonb default '{}', basis text, next_read_at timestamptz);
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_id uuid, evidence_type text, source_url text, storage_path text, content_hash text,
  mime_type text, metadata jsonb, capture_version int, evidence_group_key text, captured_at timestamptz default now(), created_at timestamptz default now());
create table pipeline.sources (id uuid primary key default gen_random_uuid(), provider_id uuid);
create table pipeline.manual_locks (entity text, entity_id uuid, field text);
create table pipeline.enrichment_flags (id bigserial primary key, entity text, entity_key text, provider_id uuid, field text, state text, reason_code text, reason text,
  flagged_at timestamptz default now(), input_mark text, evidence jsonb);
create table pipeline.coverage_admission_countries (country_id uuid, active boolean, identities jsonb, updated_at timestamptz);
create table pipeline.uni_adapters (provider_id uuid, enabled boolean, admit boolean, admit_fields text[]);
create table pipeline.uni_adapter_results (course_id uuid, fields jsonb, at timestamptz);
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid, layer3_interpretation_id uuid,
  before_value jsonb, proposed_value jsonb, layer2_state jsonb default '{}', layer3_state jsonb default '{}', status text default 'pending', assigned_to uuid, escalation_reason text,
  change_control_ref text, created_at timestamptz default now(), decided_at timestamptz, claimed_at timestamptz,
  check (status = any (array['pending', 'approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded'])));
create table pipeline.layer4_decisions (id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, actor_id uuid, reason text, before_value jsonb, proposed_value jsonb,
  final_value jsonb, evidence_id uuid, layer2_state jsonb, layer3_state jsonb, scalar_resolution_id uuid, change_control_ref text);
create table pipeline.search_refresh_signals (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, review_decision_id uuid, reason text, change_control_ref text);
create table pipeline.refresh_requests (id uuid primary key default gen_random_uuid(), requested_layer int, source_id uuid, entity_type text, entity_id uuid, evidence_id uuid,
  layer3_profile_id uuid, revalidation_ref text, reason text, trigger_type text, requested_by uuid, change_control_ref text);
create table pipeline.admin_control_events (id bigserial primary key, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table search.refresh_requests (id bigserial primary key, requested_at timestamptz default now(), requested_by text, processed_at timestamptz, result jsonb);
create table pipeline.component_register (kind text, name text, layer text, area text, purpose text, status text, replaces text[], replaced_by text, introduced_in text,
  retire_after date, note text, updated_at timestamptz, primary key (kind, name));
create table pipeline.field_coverage_daily (snapshot_date date, country_code text, field text, total int, filled int, computed_at timestamptz, primary key (snapshot_date, country_code, field));
create table pipeline.course_attribute_coverage (course_id uuid, provider_id uuid, attribute text, state text, tier text, computed_at timestamptz, country_code text);
create table pipeline.enrich_coverage_snapshots (at timestamptz, country_code text, field text, courses int, filled int, primary key (at, country_code, field));
create table pipeline.central_ai_settings (id int primary key, model_identifier text, model_code text);
-- Layer 4 inbox sources (shapes only)
create table pipeline.provider_onboarding (id uuid primary key default gen_random_uuid(), provider_id uuid, status text, stop_reason text, note text, created_at timestamptz, updated_at timestamptz);
create table pipeline.adapter_builds (provider_id uuid, wave text);
create table scholarship.scholarships (id uuid primary key, provider_id uuid, name text);
create table pipeline.scholarship_ai_extractions (id bigint primary key, answer jsonb);
create table pipeline.scholarship_ai_reviews (id bigint primary key, provider_id uuid, url text, reason text, recheck jsonb, extraction_ids bigint[], status text, created_at timestamptz);
create table pipeline.data_flags (id uuid primary key, entity_type text, entity_id uuid, field_code text, detail jsonb, flag_code text, status text, created_at timestamptz);
create table pipeline.layer1_provider_departures (id bigint primary key, provider_id uuid, courses_retired int, note text, status text, created_at timestamptz);

-- helpers the guarded functions call that this change does not touch (stubs)
create view security.provider_hidden_v1 as select p.id provider_id from catalogue.providers p where p.lifecycle_status = 'hidden';
create function security.catalogue_country_codes_v1() returns text[] language sql stable as $$ select array['AU', 'CA', 'NZ'] $$;
create function security.field_crosscheck_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;
create function security.campus_regions_apply_v1() returns int language sql as $$ select 0 $$;
create function security.coverage_sweep_source(uuid) returns uuid language sql as $$ select null::uuid $$;
create function security.enrich_fallback_v1(bigint) returns boolean language sql as $$ select false $$;
create function security.enrich_apply_v1(bigint) returns text language sql as $$ select 'stub' $$;
create function security.enrich_entry_record_v1(bigint, jsonb) returns text language sql as $$ select 'entry_stub' $$;
create function security.enrich_campus_list_apply_v1(bigint) returns void language sql as $$ select $$;
create function security.enrich_parse_duration_v1(text) returns jsonb language sql as $$ select null::jsonb $$;
create function security.enrich_parse_english_v1(text, text) returns jsonb language sql as $$ select null::jsonb $$;
create function security.enrich_parse_intakes_v1(text, text) returns jsonb language sql as $$ select null::jsonb $$;
create function security.enrich_parse_intake_periods_v1(uuid, text, text) returns jsonb language sql as $$ select null::jsonb $$;
create function security.flag_raise_v1(text, text, uuid, text, text, text, text, text, text, jsonb, text, text) returns void language sql as $$ select $$;
create function security.aer_review_kinds_v1() returns text[] language sql immutable as $$ select array['course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change'] $$;
create function security.layer4_course_scalar_resolve_impl(uuid, uuid, text, jsonb, text) returns jsonb language sql as $$ select jsonb_build_object('scalar_stub', true) $$;
create function security.layer4_provider_description_apply_impl(uuid, uuid, jsonb, text) returns jsonb language sql as $$ select jsonb_build_object('pdesc_stub', true) $$;
create function security.ai_spend_today_v1() returns table(use text, spent numeric) language sql as $$ select 'enrich_fields', 0::numeric $$;
-- the live triggers on field_enrich_items that decide what is queued and what raises a flag (gate as live; flag trigger as live, its flag call stubbed)
create function security.field_enrich_items_gate_v1() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.course_id is null then return new; end if;
  if security.enrich_item_held_v1(new.course_id, new.field) then return null; end if;
  return new;
end $$;
create table pipeline.fx_flags (course_id uuid, field text, reason text);
create function security.field_enrich_items_flag_v1() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.course_id is null or new.state is not distinct from old.state then return null; end if;
  if new.state = 'skipped' and coalesce(new.reason, '') ~* '(does not state|names no campus|quote is not on the page|site-wide line|no allowed source|not classified)' then
    insert into pipeline.fx_flags values (new.course_id, new.field, new.reason);
  end if;
  return null;
end $$;
-- v2.15.419 helpers admin_enrich_fields calls (stubs: the in-flight rule as the standing queue's, an empty estimate)
create function security.enrich_item_in_flight_v1(p_provider uuid, p_course uuid, p_field text) returns boolean language sql stable as $$
  select exists (select 1 from pipeline.field_enrich_items e where e.provider_id = p_provider and e.course_id is not distinct from p_course and e.field = p_field
                    and e.state in ('queued', 'waiting', 'ai', 'leased', 'review')) $$;
create function security.enrich_fields_estimate_v1(text[], uuid[], text[], boolean, boolean) returns jsonb language sql stable as $$ select '{}'::jsonb $$;
