-- CF-247 IQ-00111 fee reader units and holds: isolated fixture database (scratch PostgreSQL only; never a Supabase project). The tables the
-- 20261104140000 migration and the live reader functions read or write, with the live columns they use (information_schema, read-only, 3 Nov
-- 2026 21:2x AEDT), and the helpers they call as small stand-ins. The four live definitions are loaded from live/ by run.sh and checked
-- against their live md5s. Nothing here is live data.
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
create schema if not exists search; create schema if not exists ref; create schema if not exists fx;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
create extension if not exists pgcrypto;

create table fx.caller(id int primary key default 1, role text);
insert into fx.caller values (1, 'service_role');
create function auth.role() returns text language sql stable as $f$ select role from fx.caller where id = 1 $f$;

-- settings (live columns) and the reader's live fee settings
create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, label text, help text, kind text, value jsonb, min_value numeric,
  max_value numeric, unit text, sort int, section text, used_by text, reason text, updated_by text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
 ('pipeline', 'fees.auto_admit_confidence', 'number', '0.85'), ('pipeline', 'fees.min_title_similarity', 'number', '0.6'), ('pipeline', 'fees.outlier_ratio', 'number', '4'),
 ('pipeline', 'fees.max_pages_per_provider', 'number', '12'), ('pipeline', 'fees.course_pages', 'number', '1'), ('pipeline', 'fees.course_pages_per_tick', 'number', '200'),
 ('pipeline', 'fees.countries', 'list', '["NZ", "CA", "AU"]');

-- registers and A's contract prerequisites (live columns used)
create table pipeline.component_register(kind text not null, name text not null, layer text not null, area text, purpose text, status text not null default 'active',
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, last_used_at timestamptz, usage jsonb not null default '{}'::jsonb,
  size_bytes bigint, note text, registered_at timestamptz not null default now(), updated_at timestamptz not null default now(), primary key (kind, name));
create table pipeline.integration_issues(id bigserial primary key, issue_ref text, fingerprint text, status text default 'open');
create table pipeline.admin_jobs(id uuid primary key default gen_random_uuid(), state text);

-- reference and catalogue
create table ref.countries(id uuid primary key, iso_alpha2 text);
create table catalogue.providers(id uuid primary key, country_id uuid, canonical_name text, display_name text);
create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text, duration_value numeric, duration_unit text, lifecycle_status text default 'active');
create table catalogue.course_fees(id uuid primary key default gen_random_uuid(), course_id uuid, fee_year int, audience text default 'international', fee_type text,
  amount numeric, currency_code text, basis text, notes text, source_id uuid, evidence_id uuid, status text default 'active', valid_to date,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table pipeline.manual_locks(entity text, entity_id uuid, field text);

-- the reader's tables (live columns, before this change)
create table pipeline.fee_country_profiles(country_code text primary key, currency_code text, usual_unit text, full_time_units_a_year numeric, unit_name text,
  terms_a_year numeric, notes text, reason text, updated_by uuid, updated_at timestamptz default now());
insert into pipeline.fee_country_profiles(country_code, currency_code, usual_unit, full_time_units_a_year, unit_name, terms_a_year, notes, reason) values
 ('NZ', 'NZD', 'per_year', 120, 'points (credits)', 2, 'Universities publish a yearly fee per qualification; a full-time year is 120 points (1 EFTS); some list a fee per paper or point.', 'CF-247 21 Oct 2026'),
 ('CA', 'CAD', 'per_credit', 30, 'credits', 2, 'Universities often publish per credit or per term; a full-time year is about 30 credits (two terms of 15).', 'CF-247 21 Oct 2026'),
 ('AU', 'AUD', 'per_year', 8, 'units (subjects)', 2, 'Universities publish a yearly or per-unit fee; a full-time year is about 8 units (48 credit points).', 'CF-247 21 Oct 2026');
create table pipeline.coverage_admission_countries(country_id uuid, currency_code text);
create table pipeline.fee_reader_queue(id uuid primary key default gen_random_uuid(), fact_source_id uuid, provider_id uuid, content_hash text, state text default 'queued',
  leased_until timestamptz, attempts int default 0, rows_found int, cost_usd numeric, model text, error text, created_at timestamptz default now(), finished_at timestamptz,
  course_id uuid, evidence_id uuid, priority int default 0, unique (fact_source_id, content_hash));
create unique index fee_reader_queue_course_hash on pipeline.fee_reader_queue (course_id, content_hash) where course_id is not null;
create table pipeline.fee_reader_rows(id uuid primary key default gen_random_uuid(), queue_id uuid, fact_source_id uuid, provider_id uuid, qualification text, subject text,
  level text, amount_min numeric, amount_max numeric, currency_code text, unit text, audience text, fee_year int, quote text, yearly numeric, yearly_basis text,
  course_id uuid, match_confidence numeric, title_similarity numeric, outcome text, note text, created_at timestamptz default now(), units_covered int);
create table pipeline.fee_reader_findings(id uuid primary key default gen_random_uuid(), provider_id uuid, fact_source_id uuid, kind text, key text default '',
  detail jsonb default '{}', times int default 1, first_seen timestamptz default now(), last_seen timestamptz default now(), resolved_at timestamptz, unique (provider_id, kind, key));
create table pipeline.fee_reader_recipes(provider_id uuid primary key, notes text, version int default 1, history jsonb default '[]', updated_at timestamptz default now(), updated_by text default 'fee_ai');
create table pipeline.provider_fact_sources(id uuid primary key default gen_random_uuid(), provider_id uuid, kind text, url text, title text, rank int, found_via text,
  status text, linked_from uuid, evidence_id uuid, content_hash text, unique (provider_id, kind, url));
create table pipeline.evidence_artifacts(id uuid primary key, source_url text, storage_path text, content_hash text);
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, url text, status text, read_status text, read_at timestamptz,
  identity_basis text, evidence_id uuid, candidates jsonb);
create table pipeline.fee_course_requests(course_id uuid primary key, requested_at timestamptz default now(), requested_by uuid, reason text, queued_at timestamptz, outcome text);
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid, before_value jsonb,
  proposed_value jsonb, layer2_state jsonb, layer3_state jsonb, status text, escalation_reason text, change_control_ref text);
create table pipeline.uni_adapter_exclusions(course_id uuid, field text, provider_id uuid, active boolean default true, reason text, set_by uuid, set_at timestamptz default now(),
  primary key (course_id, field));
create table pipeline.uni_adapter_delivery_exclusions(course_id uuid, active boolean);
create table pipeline.enrichment_flags(id bigserial primary key, entity text, entity_key text, provider_id uuid, field text default '', reason_code text, reason text,
  source text, flagged_at timestamptz default now(), state text default 'raised', released_at timestamptz, release_reason text);
create table search.enrichment_source_gates(projection_code text, domain_code text, source_id uuid, gate_status text, approval_ref text, approved_at timestamptz,
  created_at timestamptz, updated_at timestamptz);
create table search.refresh_requests(id bigserial primary key, requested_at timestamptz default now(), requested_by text);
create view security.provider_hidden_v1 as select null::uuid provider_id where false;

-- helpers as small stand-ins (their live behaviour is not what this change is about)
create function security.coverage_sweep_source(p uuid) returns uuid language sql immutable as $f$ select '00000000-0000-0000-0000-00000000005e'::uuid $f$;
create function security.fee_title_similarity_v1(a text, b text) returns numeric language sql immutable as $f$ select 1::numeric $f$;
create function security.fee_below_floor_v1(c uuid, y numeric, b text) returns numeric language sql stable as $f$ select null::numeric $f$;
create function security.coverage_identity_allowed(p uuid, b text, f text) returns boolean language sql stable as $f$ select true $f$;
create function security.coverage_tuition_target_v1(j jsonb) returns numeric language sql immutable as $f$ select nullif(j->>'value', '')::numeric $f$;
create function security.fee_reader_finding_v1(p_provider uuid, p_source uuid, p_kind text, p_key text, p_detail jsonb) returns void language sql as $f$
  insert into pipeline.fee_reader_findings(provider_id, fact_source_id, kind, key, detail) values (p_provider, p_source, p_kind, coalesce(p_key, ''), p_detail)
  on conflict (provider_id, kind, key) do update set times = pipeline.fee_reader_findings.times + 1, last_seen = now() $f$;
-- admission: writes the active provider fee, as the live apply does for a fee
create function security.coverage_apply_course_v1(p_course uuid, p_src uuid, p_ev uuid, p_url text, p_hash text, p_vals jsonb) returns jsonb language sql as $f$
  insert into catalogue.course_fees(course_id, fee_year, fee_type, amount, currency_code, basis, notes, source_id, evidence_id)
  values (p_course, (p_vals->>'fee_year')::int, 'provider_current_tuition', (p_vals->>'fee_amount')::numeric, p_vals->>'currency_code', p_vals->>'fee_basis', p_vals->>'fee_notes', p_src, p_ev)
  returning jsonb_build_object('ok', true) $f$;
