-- CF-247 IQ-00111 D12 fee re-check route: isolated fixture database (scratch PostgreSQL only; never a Supabase project). The tables the
-- 20261104230000 migration and the live Layer 4 inbox read or write, with the live columns they use (read-only, 3 Nov 2026 22:0x AEDT); helpers
-- as small stand-ins. security.layer4_inbox_items_v1 is loaded from live/ (live md5), then the Layer 4 owner's 20261104150000 edit (4fc05d14). Nothing here is live data.
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists search;
create schema if not exists scholarship; create schema if not exists fx;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create extension if not exists pgcrypto;

create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, label text, help text, kind text, value jsonb, min_value numeric,
  max_value numeric, unit text, sort int, section text, used_by text, reason text, updated_by text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create table pipeline.component_register(kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, last_used_at timestamptz, usage jsonb not null default '{}'::jsonb,
  size_bytes bigint, note text, registered_at timestamptz not null default now(), updated_at timestamptz not null default now(), primary key (kind, name));
create table pipeline.integration_issues(id bigserial primary key, issue_ref text, fingerprint text, status text default 'open');
create table pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), state text);
create table pipeline.admin_control_events(id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb,
  actor uuid, created_at timestamptz not null default now());
-- the 20261104140000 function this change requires (stand-in)
create function security.fee_reader_hold_v1(p uuid) returns text language sql stable as $f$ select null::text $f$;

create schema if not exists ref;
create table ref.countries(id uuid primary key, iso_alpha2 text);
create table catalogue.providers(id uuid primary key, canonical_name text, display_name text, country_id uuid);
create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text, display_title text, course_code text, lifecycle_status text default 'active');
create table catalogue.course_links(course_id uuid, link_type text, status text);
create table catalogue.course_fees(id uuid primary key default gen_random_uuid(), course_id uuid, fee_year int, audience text default 'international', fee_type text,
  amount numeric, currency_code text, basis text, notes text, evidence_id uuid, status text default 'active', valid_to date,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.manual_locks(entity text, entity_id uuid, field text, mode text, set_by uuid, set_at timestamptz default now());
create table pipeline.evidence_artifacts(id uuid primary key, source_url text, storage_path text, captured_at timestamptz);
create table pipeline.coverage_course_pages(course_id uuid primary key, evidence_id uuid);
create table pipeline.fee_reader_rows(id uuid primary key default gen_random_uuid(), course_id uuid, quote text, outcome text, created_at timestamptz default now());
create table pipeline.uni_adapter_exclusions(course_id uuid, field text, active boolean default true, reason text, set_at timestamptz default now(), primary key (course_id, field));
create table pipeline.enrichment_flags(id bigserial primary key, entity text, entity_key text, provider_id uuid, field text default '', reason_code text, reason text,
  source text, flagged_at timestamptz default now(), cleared_at timestamptz, kind text default 'hard', state text default 'raised', tries int default 1, evidence jsonb default '{}',
  raised_by_kind text default 'auto', released_at timestamptz, released_by text, release_kind text, release_reason text, updated_at timestamptz default now(),
  unique (entity, entity_key, field, reason_code));
create table pipeline.enrichment_flag_events(id bigserial primary key, flag_id bigint, action text check (action in ('raised','counted','re_raised','released','check_failed','requeued')),
  actor text, actor_kind text check (actor_kind in ('auto','person')), reason text, evidence jsonb, at timestamptz default now());
create table search.refresh_requests(id bigserial primary key, requested_at timestamptz default now(), requested_by text);
create table fx.refreshed(course_id uuid);
create function scholarship.refresh_course_financial_calculations(p_course uuid, p_s uuid) returns jsonb language sql as
  $f$ insert into fx.refreshed values (p_course) returning jsonb_build_object('refreshed', 1) $f$;
-- the release a person makes from the card (live security.flag_release_v1: state, release fields; history aside)
create function security.flag_release_v1(p_id bigint, p_actor text, p_kind text, p_reason text, p_ev jsonb, p_keep boolean) returns jsonb language sql as $f$
  update pipeline.enrichment_flags set state = 'released', cleared_at = now(), released_at = now(), released_by = p_actor, release_kind = p_kind, release_reason = p_reason
   where id = p_id and state <> 'released' returning jsonb_build_object('id', id, 'state', 'released') $f$;

-- what the live inbox reads besides flags (empty here)
create table pipeline.provider_onboarding(id uuid, provider_id uuid, status text, stop_reason text, note text, created_at timestamptz, updated_at timestamptz);
create table pipeline.adapter_builds(provider_id uuid, wave text);
create table pipeline.layer4_review_items(id uuid, entity_type text, entity_id uuid, field_code text, evidence_id uuid, before_value jsonb, proposed_value jsonb,
  escalation_reason text, status text, created_at timestamptz);
create function security.aer_review_kinds_v1() returns text[] language sql immutable as $f$ select array['aer']::text[] $f$;
create table scholarship.scholarships(id uuid, provider_id uuid, name text);
create table pipeline.scholarship_ai_extractions(id bigint, answer jsonb);
create table pipeline.scholarship_ai_reviews(id bigint, provider_id uuid, extraction_ids bigint[], url text, reason text, recheck jsonb, created_at timestamptz, status text);
create table pipeline.data_flags(id bigint, entity_type text, entity_id uuid, field_code text, detail jsonb, created_at timestamptz, flag_code text, status text);
create table pipeline.layer1_provider_departures(id uuid, provider_id uuid, courses_retired int, note text, created_at timestamptz, status text);
create table pipeline.course_page_needed(course_id uuid, provider_id uuid, refused int, last_refused_reason text, last_refused_url text, last_refused_lane text,
  last_refused_evidence uuid, converted_items jsonb, searches_requested int, created_at timestamptz, state text);
