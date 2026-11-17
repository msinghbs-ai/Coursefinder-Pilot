#!/usr/bin/env bash
# Guards: Reference data › API field dictionary and Grade scale conversions (Platform Admin 17 Nov 2026 23:05) and G4 database-backed tests: migration
# 20261118005000 runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: the migration applies twice; the read is
# Curator and above; search matches typed text literally; filters and paging follow the page-size setting; nothing is written.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (ART_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${ART_DB:-g_admin_reference_tables}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations/20261118005000_cf247_admin_reference_tables_read.sql
trap '[ -n "${ART_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; end \$\$"
$P <<'SQL'
create schema pipeline; create schema security; create schema auth; create schema ref;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fixture.uid', true), '')::uuid $$;
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fixture.rank', true), '')::int $$;
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 text unique, name text);
insert into ref.countries(iso_alpha2, name) values ('AU', 'Australia'), ('IN', 'India');
create table pipeline.platform_toolset_settings (toolset_key text, key text, label text, help text, kind text, value jsonb, min_value numeric, max_value numeric, unit text, sort int, reason text, section text, used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$ select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create table ref.api_field_dictionary (id uuid primary key default gen_random_uuid(), api_surface text, version text, endpoint text, field_path text, data_type text, is_nullable boolean, allowed_values jsonb, req_ids text[],
  source_table text, source_column text, description text, example_value jsonb, introduced_in text, deprecated_in text, created_at timestamptz default now(), updated_at timestamptz default now());
create table ref.grade_scale_conversions (id uuid primary key default gen_random_uuid(), country_id uuid, qualification_code text, qualification_name text, board_or_stream text, scale_code text, raw_min_value numeric, raw_max_value numeric,
  raw_grade_label text, normalized_0_100 numeric, is_active boolean, source_url text, notes text, created_at timestamptz default now(), updated_at timestamptz default now());
insert into ref.api_field_dictionary(api_surface, version, endpoint, field_path, data_type, is_nullable, req_ids, source_table, source_column, description)
select case when i % 2 = 0 then 'website' else 'zoho' end, case when i <= 100 then 'v3' else 'v2' end, 'course', 'course.field_' || i, 'text', true, array['REQ-' || i], 'catalogue.courses', 'col_' || i, 'Field number ' || i from generate_series(1, 120) i;
insert into ref.api_field_dictionary(api_surface, version, endpoint, field_path, data_type, is_nullable, req_ids, source_table, source_column, description)
values ('website', 'v3', 'course', 'course.study_load', 'text', true, array['R33', 'REQ-76'], 'catalogue.courses', 'study_load', '100% literal_text here');
insert into ref.grade_scale_conversions(country_id, qualification_code, qualification_name, board_or_stream, scale_code, raw_min_value, raw_max_value, raw_grade_label, normalized_0_100, is_active)
values ((select id from ref.countries where iso_alpha2 = 'IN'), 'IN-XII', 'Higher Secondary Certificate', 'CBSE', 'percent', 60, 100, '60%+', 60, true),
       ((select id from ref.countries where iso_alpha2 = 'AU'), 'AU-ATAR', 'ATAR', null, 'atar', 0, 99.95, 'ATAR', 50, false);
SQL
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
echo "migration: applied twice without error (post-check included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; begin
  perform pg_temp.ok(pg_temp.err($$select public.admin_reference_table_read('api_fields')$$) = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', '44444444-4444-4444-4444-444444444444', true); perform set_config('fixture.rank', '2', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_reference_table_read('api_fields')$$) like 'Curator (rank 3)%', 'a Counsellor cannot read the reference tables');
  perform set_config('fixture.rank', '3', true);
  r := public.admin_reference_table_read('api_fields');
  perform pg_temp.ok((r->>'total')::int = 121 and (r->>'all_rows')::int = 121 and (r->>'page_rows')::int = 50 and jsonb_array_length(r->'rows') = 50
    and r#>'{filters,surfaces}' = '["website", "zoho"]'::jsonb and r#>'{filters,versions}' = '["v2", "v3"]'::jsonb, 'a Curator reads the dictionary: 50 rows a page from the setting, with its filter values');
  r := public.admin_reference_table_read('api_fields', '{"offset": 100}');
  perform pg_temp.ok(jsonb_array_length(r->'rows') = 21, 'the last page holds the remainder');
  r := public.admin_reference_table_read('api_fields', '{"surface": "zoho", "version": "v2"}');
  perform pg_temp.ok((r->>'total')::int = 10 and (r->>'all_rows')::int = 121, 'surface and version filters narrow the list; the full count stays');
  r := public.admin_reference_table_read('api_fields', '{"query": "study_load"}');
  perform pg_temp.ok((r->>'total')::int = 1 and r#>>'{rows,0,field_path}' = 'course.study_load' and r#>'{rows,0,req_ids}' = '["R33", "REQ-76"]'::jsonb, 'search finds a field by its path or source column');
  perform pg_temp.ok((public.admin_reference_table_read('api_fields', '{"query": "R33"}')->>'total')::int = 1, 'search finds a field by its request number');
  perform pg_temp.ok((public.admin_reference_table_read('api_fields', '{"query": "col_"}')->>'total')::int = 120 and (public.admin_reference_table_read('api_fields', '{"query": "100% literal_text"}')->>'total')::int = 1
    and (public.admin_reference_table_read('api_fields', '{"query": "%"}')->>'total')::int = 1, 'typed % and _ are matched as text, not as wildcards');
  update pipeline.platform_toolset_settings set value = to_jsonb(10) where key = 'admin.reference_table_page_rows';
  perform pg_temp.ok(jsonb_array_length(public.admin_reference_table_read('api_fields')->'rows') = 10, 'the page size follows the setting');
  r := public.admin_reference_table_read('grade_scales');
  perform pg_temp.ok((r->>'total')::int = 2 and r#>>'{rows,0,country_name}' = 'Australia' and jsonb_array_length(r#>'{filters,countries}') = 2, 'grade scale conversions list with the country name');
  perform pg_temp.ok((public.admin_reference_table_read('grade_scales', '{"country": "in"}')->>'total')::int = 1 and (public.admin_reference_table_read('grade_scales', '{"active": "false"}')->>'total')::int = 1
    and (public.admin_reference_table_read('grade_scales', '{"query": "cbse"}')->>'total')::int = 1, 'country, active and search filters work on grade scales');
  perform pg_temp.ok(pg_temp.err($$select public.admin_reference_table_read('courses')$$) like 'unknown reference table%' and pg_temp.err(format($$select public.admin_reference_table_read('api_fields', %L)$$, jsonb_build_object('query', repeat('x', 121)))) like 'the search text is too long%', 'an unknown table and an over-long search are refused');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_reference_table_read(text, jsonb)', 'execute') and (select provolatile from pg_proc where proname = 'admin_reference_table_read') = 's', 'anon cannot run it; the function is read-only (stable)');
end $t$;
SQL
echo "admin reference tables: all checks passed"
