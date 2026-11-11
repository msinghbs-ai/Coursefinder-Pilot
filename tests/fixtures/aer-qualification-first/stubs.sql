-- Only what migration 20261112060000 and the two edited bodies read or write (the bodies themselves are loaded from live/ unchecked).
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue; create schema if not exists ref; create schema if not exists auth;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text unique);
create table catalogue.providers (id uuid primary key default gen_random_uuid(), canonical_name text, display_name text);
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int,
  section text, used_by text, reason text, updated_at timestamptz, primary key (toolset_key, key));
create table pipeline.entry_matrix_sources (id uuid primary key default gen_random_uuid(), provider_id uuid, url text, status text, read_via text, evidence_id uuid);
create table pipeline.entry_matrix_runs (id uuid primary key default gen_random_uuid(), source_id uuid, provider_id uuid, state text default 'leased', attempts int default 1,
  model_code text default 'pinned/model', content_hash text default 'h', leased_until timestamptz, error text, cost_usd numeric default 0, previous_results jsonb default '[]'::jsonb,
  done_at timestamptz, rows_admitted int, rows_dropped int, slices int, result jsonb, review_item_id uuid, updated_at timestamptz);
create table catalogue.provider_entry_matrix (id uuid primary key default gen_random_uuid(), provider_id uuid, course_label text, matrix_kind text, benchmark_band text, level_label text,
  study_level_id uuid, country_id uuid, country_code text not null, qualification_name text not null, min_grade text, min_value numeric, grade_scale text, conditions jsonb, edition text,
  intake_year int, quote text, source_url text, source_id uuid, evidence_id uuid, content_hash text, run_id uuid, confidence numeric, status text, status_reason text, provenance jsonb,
  row_hash text generated always as (md5(coalesce(country_code,'') || '|' || coalesce(level_label,'') || '|' || coalesce(qualification_name,'') || '|' || coalesce(benchmark_band,''))) stored,
  updated_at timestamptz default now());
create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text, evidence_id uuid, before_value jsonb,
  proposed_value jsonb, layer2_state jsonb, layer3_state jsonb, status text, escalation_reason text, change_control_ref text);
create table pipeline.component_register (kind text, name text, layer text, purpose text, status text, replaces text[], introduced_in text, primary key (kind, name));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.toolset_setting(p_tool text, p_key text) returns jsonb language sql stable as $$ select value from pipeline.platform_toolset_settings where toolset_key = p_tool and key = p_key $$;
create function security.entry_level_map_v1(p text) returns uuid language sql immutable as $$ select null::uuid $$;
create function security.entry_completeness_required_v1(p uuid) returns boolean language sql stable as $$ select false $$;
create function security.entry_matrix_gate_v1(p uuid, x uuid[]) returns jsonb language sql stable as $$ select null::jsonb $$;
create function security.entry_rendered_note_v1(p uuid) returns uuid language sql as $$ select null::uuid $$;
create function security.current_role_rank() returns int language sql stable as $$ select 7 $$;
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create function auth.role() returns text language sql stable as $$ select null::text $$;
insert into ref.countries(iso_alpha2) values ('IN'), ('NP'), ('GB');
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'reading.entry_country_aliases_on', '0');
