-- AER QUT matrix route and shared-page rule (migrations 20261108030000, 20261108030100): the tables and helpers they read or write, as live has them (columns, NOT NULL, defaults,
-- checks read from information_schema / pg_constraint on 8 Nov 2026; behaviour, not data). Scratch PostgreSQL only (never a Supabase project): see run.sh.
do $r$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; end $r$;
create schema if not exists security; create schema if not exists catalogue; create schema if not exists pipeline; create schema if not exists ref;
create table ref.countries(id uuid primary key default gen_random_uuid(), iso_alpha2 text unique);
create table catalogue.providers(id uuid primary key, canonical_name text);
create table catalogue.courses(id uuid primary key default gen_random_uuid(), provider_id uuid not null references catalogue.providers(id), canonical_title text not null, lifecycle_status text not null default 'active');
create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, label text not null, help text not null default '', kind text not null check (kind in ('number', 'text', 'boolean', 'list')),
  value jsonb not null, min_value numeric, max_value numeric, unit text, sort int not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(),
  section text not null default 'Notices', used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path = '' as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable security definer set search_path = '' as
  $f$ select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key $f$;
-- the AI stop (fixture switch: setting fixture.ai_stopped = 1)
create function security.ai_use_allowed_v1(p_area text) returns boolean language sql stable security definer set search_path = '' as
  $f$ select security.pipeline_num_v1('fixture.ai_stopped', 0) < 1 $f$;
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), entity_id uuid, source_id uuid, job_id uuid, evidence_type text not null, source_url text, storage_path text,
  content_hash text, mime_type text, captured_at timestamptz not null default now(), metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null, field_code text not null, evidence_id uuid,
  layer3_interpretation_id uuid, before_value jsonb, proposed_value jsonb, layer2_state jsonb not null default '{}'::jsonb, layer3_state jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded')),
  assigned_to uuid, escalation_reason text, change_control_ref text not null default 'CF-CHG-20260825-038', created_at timestamptz not null default now(), decided_at timestamptz, claimed_at timestamptz);
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid not null, url text, score numeric, runner_up numeric, basis text, status text not null,
  bound_at timestamptz not null default now(), read_status text, read_at timestamptz, http_status int, fetched_via text, identity_basis text, evidence_id uuid, candidates jsonb,
  leased_until timestamptz, read_attempts int not null default 0, next_read_at timestamptz, l3_work_item_id uuid, l3_handoff_at timestamptz);
create table pipeline.manual_locks(entity text not null check (entity in ('course', 'provider', 'campus', 'scholarship')), entity_id uuid not null, field text not null,
  mode text not null check (mode in ('value', 'removed')), set_at timestamptz not null default now(), primary key (entity, entity_id, field));
create table pipeline.admin_control_events(id bigint generated always as identity primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb,
  actor uuid, created_at timestamptz not null default now());
create table pipeline.entry_matrix_sources(id uuid primary key default gen_random_uuid(), provider_id uuid not null references catalogue.providers(id), url text not null check (url ~ '^https?://'),
  title text, rank int not null default 1, found_via text not null check (found_via in ('search', 'manual')),
  status text not null default 'found' check (status in ('found', 'reading', 'read', 'failed', 'robots_disallowed', 'pdf_step_b', 'inactive')),
  read_via text check (read_via in ('stored', 'direct', 'firecrawl')), http_status int, evidence_id uuid references pipeline.evidence_artifacts(id), content_hash text,
  attempts int not null default 0, read_at timestamptz, error text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (provider_id, url));
create table catalogue.provider_entry_matrix(id uuid primary key default gen_random_uuid(), provider_id uuid not null, course_id uuid references catalogue.courses(id), course_label text,
  matrix_kind text not null default 'provider_minimum' check (matrix_kind in ('provider_minimum', 'band_ladder', 'course_minimum', 'rank_band')),
  country_id uuid not null, country_code text not null, qualification_name text not null, conditions jsonb not null default '{}'::jsonb, audience text not null default 'international',
  quote text not null, source_url text not null, source_id uuid references pipeline.entry_matrix_sources(id), as_at date not null default current_date,
  status text not null default 'proposed', provenance jsonb not null default '{}'::jsonb, row_hash text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
-- the live identity trigger sets the row hash from the course among other things (stub: course and qualification), named so it sorts after the route trigger as live's does
create function security.entry_matrix_identity_tg() returns trigger language plpgsql as $f$ begin new.row_hash := md5(coalesce(new.course_id::text, '-') || '|' || new.country_code || '|' || new.qualification_name); return new; end $f$;
create trigger provider_entry_matrix_identity before insert or update on catalogue.provider_entry_matrix for each row execute function security.entry_matrix_identity_tg();
