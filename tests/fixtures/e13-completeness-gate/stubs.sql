-- E13 completeness gate: isolated fixture database (CF-247 E13, Platform Admin 2 Nov 2026 05:18).
-- The smallest set of schemas, tables and helper functions the course entry reader, the gate and the approval need, with the columns they
-- use. Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is a copy of live data.
create extension if not exists pgcrypto;
create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists security; create schema if not exists auth;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;

create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric,
  unit text, sort int, section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.toolset_setting(p_toolset text, p_key text) returns jsonb language sql stable as
  $f$ select value from pipeline.platform_toolset_settings where toolset_key = p_toolset and key = p_key $f$;
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value, min_value, max_value) values
  ('pipeline', 'entry.max_rows_per_course', 'number', '6', 1, 10), ('pipeline', 'entry.min_confidence', 'number', '0.8', 0.5, 1);

-- the signed-in person (the review screen checks a role)
create table auth.session(uid uuid, rank int);
create function auth.uid() returns uuid language sql stable as $f$ select uid from auth.session limit 1 $f$;
create function security.current_role_rank() returns int language sql stable as $f$ select rank from auth.session limit 1 $f$;

create table catalogue.courses(id uuid primary key, provider_id uuid, canonical_title text);
create table pipeline.evidence_artifacts(id uuid primary key default gen_random_uuid(), captured_at timestamptz default now(), content_hash text);
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid, identity_basis text default 'cricos_code', url text, evidence_id uuid, status text default 'bound');
create function security.coverage_identity_allowed(p_provider uuid, p_basis text, p_field text) returns boolean language sql stable as $f$ select true $f$;
create function security.coverage_country(p_provider uuid) returns text language sql stable as $f$ select 'AU'::text $f$;
create table pipeline.field_enrich_items(id bigserial primary key, job_id uuid, provider_id uuid, course_id uuid, field text default 'entry_requirements',
  state text default 'ai', reason text, value jsonb, quote text, evidence_id uuid, updated_at timestamptz default now());
create table pipeline.layer4_review_items(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid,
  before_value jsonb, proposed_value jsonb, layer2_state jsonb, layer3_state jsonb, status text default 'pending', escalation_reason text, change_control_ref text,
  created_at timestamptz default now());
create table catalogue.course_entry_requirements(id uuid primary key default gen_random_uuid(), course_id uuid, kind text, audience text, description text,
  min_grade text, grade_scale text, min_entry_score numeric, min_entry_score_basis text, benchmark_band text, quote text, source_url text, evidence_id uuid,
  confidence numeric, as_at date, status text, status_reason text, provenance jsonb, created_at timestamptz default now(), updated_at timestamptz default now());
-- what the review screen reads besides the course rows (provider tables are not part of these fixtures)
create table pipeline.entry_matrix_runs(id uuid primary key, review_item_id uuid);
create table catalogue.provider_entry_matrix(id uuid primary key, run_id uuid, status text, status_reason text, country_code text, level_label text,
  qualification_name text, benchmark_band text, min_grade text, grade_scale text, quote text, evidence_id uuid, content_hash text, provenance jsonb);
create table pipeline.layer4_decisions(id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, reason text, final_value jsonb, created_at timestamptz default now());
create function security.aer_review_kinds_v1() returns text[] language sql stable as $f$ select array['entry_matrix_first_run', 'course_entry_first_read'] $f$;
create function security.aer_review_lineage_v1(p_item uuid) returns jsonb language sql stable as $f$ select '{}'::jsonb $f$;
