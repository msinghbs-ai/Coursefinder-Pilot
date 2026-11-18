-- S741 fixture stubs (invented structure only; columns are the ones the matrix machine exclusions read). Never a Supabase project.
create schema if not exists security; create schema if not exists catalogue; create schema if not exists pipeline; create schema if not exists ref; create schema if not exists t;
create table pipeline.platform_toolset_settings(toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int,
  section text, used_by text, reason text, updated_at timestamptz default now(), primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as
  $f$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $f$;
create table pipeline.admin_control_events(id bigserial, area text, action text, target text, detail jsonb, actor uuid, created_at timestamptz default now());
create table ref.study_levels(id uuid primary key default gen_random_uuid(), code text unique, short_code text);
insert into ref.study_levels(code, short_code) values ('diploma','diploma'),('advanced_diploma','advanced_diploma'),('bachelor','bachelor'),('masters','masters'),('certificate_iii','certificate_iii'),
  ('certificate_iv','certificate_iv'),('doctorate','doctorate'),('foundation','foundation'),('graduate_diploma','graduate_diploma'),('graduate_certificate','graduate_certificate'),('associate_degree','associate_degree');
create table pipeline.entry_matrix_sources(id uuid primary key default gen_random_uuid(), url text);
create table pipeline.entry_matrix_runs(id uuid primary key default gen_random_uuid(), source_id uuid, result jsonb default '{}');
create table catalogue.courses(id uuid primary key default gen_random_uuid(), provider_id uuid, canonical_title text, display_title text, lifecycle_status text default 'active', study_level_id uuid);
create table catalogue.entry_course_links(provider_id uuid, label_key text, course_label text, course_id uuid, state text, method text default 'person');
create table catalogue.provider_entry_matrix(id uuid primary key default gen_random_uuid(), run_id uuid, source_id uuid, provider_id uuid, course_id uuid, course_label text, level_label text,
  study_level_id uuid, country_code text, benchmark_band text, qualification_name text, conditions jsonb default '[]', min_grade text, min_value numeric, grade_scale text default 'none',
  quote text, confidence numeric default 1, status text default 'proposed', row_hash text, provenance jsonb default '{}', updated_at timestamptz default now());
create table catalogue.provider_qualification_requirements(id uuid primary key default gen_random_uuid(), run_id uuid, source_id uuid, provider_id uuid, course_id uuid, course_label text,
  level_label text, study_level_id uuid, qualification_code text, applicability text default 'resolved', min_grade text, min_value numeric, grade_scale text default 'none', quote text,
  confidence numeric default 1, status text default 'proposed', provenance jsonb default '{}', updated_at timestamptz default now());
-- the live values of the S671 settings on 19 Nov 2026 (read 05:50 AEDT): the rules this change builds on are on
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'aer.matrix_completion_only_on', '1'), ('pipeline', 'aer.matrix_level_inherit_on', '1'),
  ('pipeline', 'aer.course_link_on', '1'), ('pipeline', 'aer.matrix_machine_min_confidence', '0.9'), ('pipeline', 'aer.machine_min_quote_chars', '8'),
  ('pipeline', 'aer.matrix_level_inherit_codes', '["bachelor", "masters", "doctorate", "foundation"]');
