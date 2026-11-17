#!/usr/bin/env bash
# Guards: REQ-76 API v3 field dictionary sync (Platform Admin 15 Nov 2026, combined build item 1) and G4 database-backed tests:
# migration 20261116110000, then the newest reviewed list (20261117140000), on top of 20261115190000 runs on an isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: the
# reviewed list loads every field; a second load changes nothing; only a changed field is written; a field dropped from the list is marked
# deprecated and never deleted, and comes back un-deprecated; a bad list writes nothing; the drift check finds a missing path, a type change and a
# null where the dictionary says not nullable, and is empty for a matching response.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (FD_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${FD_DB:-g_api_field_dictionary}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/api-field-dictionary
S=supabase/migrations/20261115190000_api_v3_additive_schema.sql; M0=supabase/migrations/20261116110000_cf247_api_field_dictionary_sync.sql
M=supabase/migrations/20261117140000_cf247_api_field_dictionary_campus_locality.sql  # the newest reviewed list, on top of the functions of M0
N=$(node -e "console.log(JSON.parse(require('fs').readFileSync('docs/api/v3/field-dictionary.json','utf8')).fields.length)")
# a fingerprint of the reviewed list: the loaded table must carry exactly the same values (the compact form decodes losslessly)
FP=$(node -e "const c=require('crypto');const d=JSON.parse(require('fs').readFileSync('docs/api/v3/field-dictionary.json','utf8'));console.log(c.createHash('md5').update(d.fields.map(f=>[f.api_surface,f.endpoint,f.field_path,f.data_type,f.is_nullable,f.description,(f.allowed_values?JSON.stringify(f.allowed_values).replace(/,/g,', '):'null'),(f.req_ids||[]).slice().sort().join(',')].join('|')).sort().join('\\n')).digest('hex'))")
trap '[ -n "${FD_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P -f $F/stubs.sql
$P -1 -f $S >/dev/null
echo "loaded: stubs and $S"
$P -1 -f $M0 >/dev/null 2>&1
$P -1 -f $M >/dev/null 2>&1; $P -1 -f $M >/dev/null 2>&1
echo "migration: $M0, then the newest list applied twice without error"

$P -v n="$N" -v fp="$FP" <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
select set_config('fd.n', :'n', false), set_config('fd.fp', :'fp', false);
do $t$ declare r jsonb; m text; v_at text; f jsonb; n int := current_setting('fd.n')::int; begin
  perform pg_temp.ok((select count(*) from ref.api_field_dictionary where version = 'v3' and deprecated_in is null) = n, format('the reviewed list loaded all %s fields', n));
  perform pg_temp.ok((select count(distinct api_surface) from ref.api_field_dictionary) = 2, 'both the website and the Zoho surface are registered');
  perform pg_temp.ok(not exists (select 1 from ref.api_field_dictionary where coalesce(btrim(description), '') = ''), 'every field has a description');
  perform pg_temp.ok((select md5(string_agg(concat_ws('|', api_surface, endpoint, field_path, data_type, is_nullable::text, description, coalesce(allowed_values::text, 'null'),
                       array_to_string(req_ids, ',')), E'\n' order by concat_ws('|', api_surface, endpoint, field_path, data_type, is_nullable::text, description, coalesce(allowed_values::text, 'null'), array_to_string(req_ids, ',')) collate "C"))
                       from ref.api_field_dictionary where version = 'v3') = current_setting('fd.fp'), 'the table holds exactly the reviewed list (every value of every field)');

  f := '[{"api_surface":"website","endpoint":"course","field_path":"course_id","data_type":"string","is_nullable":false,"description":"Key","req_ids":["REQ-76"],"example_value":"c1"},
         {"api_surface":"website","endpoint":"course","field_path":"study_load","data_type":"string","is_nullable":true,"allowed_values":["full_time","part_time"],"description":"Load"},
         {"api_surface":"zoho","endpoint":"search","field_path":"items","data_type":"array<object>","is_nullable":false,"description":"Items"}]';
  r := security.api_field_dictionary_sync_v1('vtest', 'vtest.0', f);
  perform pg_temp.ok((r->>'inserted')::int = 3 and (r->>'deprecated')::int = 0, 'a new list inserts every field');
  select string_agg(ctid::text, ',' order by field_path) into v_at from ref.api_field_dictionary where version = 'vtest';
  r := security.api_field_dictionary_sync_v1('vtest', 'vtest.0', f);
  perform pg_temp.ok((r->>'unchanged')::int = 3 and (r->>'inserted')::int = 0 and (r->>'updated')::int = 0, 'the same list again changes nothing');
  perform pg_temp.ok((select string_agg(ctid::text, ',' order by field_path) from ref.api_field_dictionary where version = 'vtest') = v_at, 'an unchanged load writes no row (no new row versions)');
  r := security.api_field_dictionary_sync_v1('vtest', 'vtest.0', jsonb_set(f, '{1,description}', '"Study load"'));
  perform pg_temp.ok((r->>'updated')::int = 1 and (r->>'unchanged')::int = 2, 'a changed description updates only its field');
  r := security.api_field_dictionary_sync_v1('vtest', 'vtest.1', (f - 1));
  perform pg_temp.ok((r->>'deprecated')::int = 1 and (select deprecated_in from ref.api_field_dictionary where version = 'vtest' and field_path = 'study_load') = 'vtest.1',
                     'a field dropped from the list is marked deprecated in the release');
  perform pg_temp.ok((select count(*) from ref.api_field_dictionary where version = 'vtest') = 3, 'nothing is deleted');
  r := security.api_field_dictionary_sync_v1('vtest', 'vtest.2', jsonb_build_array(f->2));
  perform pg_temp.ok((select deprecated_in from ref.api_field_dictionary where version = 'vtest' and field_path = 'course_id') is null
                     and (select deprecated_in from ref.api_field_dictionary where version = 'vtest' and field_path = 'study_load') = 'vtest.1',
                     'a list for one surface leaves the other surface alone and keeps an earlier deprecation release');
  r := security.api_field_dictionary_sync_v1('vtest', 'vtest.3', f);
  perform pg_temp.ok((select count(*) from ref.api_field_dictionary where version = 'vtest' and deprecated_in is null) = 3, 'a field that comes back is un-deprecated');
  perform pg_temp.ok((select count(*) from ref.api_field_dictionary where version = 'v3' and deprecated_in is null) = n, 'another version is never touched');

  m := pg_temp.err($$select security.api_field_dictionary_sync_v1('vtest', 'x', '[{"api_surface":"website","endpoint":"course","field_path":"a","data_type":"array<number>","is_nullable":true,"description":"d"}]')$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: entry 1: data_type array<number> is not allowed%', 'an unknown type is refused');
  m := pg_temp.err($$select security.api_field_dictionary_sync_v1('vtest', 'x', '[{"api_surface":"website","endpoint":"course","field_path":"a","data_type":"string","is_nullable":true,"description":"d"},{"api_surface":"website","endpoint":"course","field_path":"a","data_type":"string","is_nullable":true,"description":"d"}]')$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: website course a is listed twice%', 'a field listed twice is refused');
  m := pg_temp.err($$select security.api_field_dictionary_sync_v1('vtest', 'x', '[{"api_surface":"website","endpoint":"course","field_path":"new_field","data_type":"string","is_nullable":true,"description":"d"},{"api_surface":"crm","endpoint":"course","field_path":"a","data_type":"string","is_nullable":true,"description":"d"}]')$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: entry 2: api_surface%' and not exists (select 1 from ref.api_field_dictionary where field_path = 'new_field'), 'a bad list writes nothing');
  m := pg_temp.err($$select security.api_field_dictionary_sync_v1('vtest', 'x', '[{"api_surface":"website","endpoint":"course","field_path":"a","data_type":"string","is_nullable":true}]')$$);
  perform pg_temp.ok(m like 'INVALID_INPUT: entry 1: description is required%', 'a field without a description is refused');

  perform pg_temp.ok(not exists (select 1 from security.api_field_dictionary_drift_v1('website', 'course', '{"course_id":"c1","study_load":null}', 'vtest')),
                     'a response that matches the dictionary has no drift');
  perform pg_temp.ok((select issue from security.api_field_dictionary_drift_v1('website', 'course', '{"course_id":"c1","extra":1}', 'vtest') where field_path = 'extra') = 'not in dictionary',
                     'a path the dictionary does not hold is reported');
  perform pg_temp.ok((select issue from security.api_field_dictionary_drift_v1('website', 'course', '{"course_id":7}', 'vtest') where field_path = 'course_id') = 'type differs',
                     'a type change is reported');
  perform pg_temp.ok((select issue from security.api_field_dictionary_drift_v1('website', 'course', '{"course_id":null}', 'vtest') where field_path = 'course_id') = 'null where the dictionary says not nullable',
                     'a null where the dictionary says not nullable is reported');
  perform pg_temp.ok(not exists (select 1 from security.api_field_dictionary_drift_v1('zoho', 'search', '{"items":[]}', 'vtest')), 'an empty list matches array<object>');
  perform pg_temp.ok(not exists (select 1 from security.api_field_dictionary_drift_v1('zoho', 'search', '{"items":[{}, {}]}', 'vtest')), 'array elements are described by the array''s type, not listed');
  perform pg_temp.ok((select string_agg(field_path, ',') from security.api_field_dictionary_drift_v1('zoho', 'search', '{"items":[{"extra":1}]}', 'vtest')) = 'items[].extra', 'a field inside list items is checked');

  perform pg_temp.ok(not has_function_privilege('anon', 'security.api_field_dictionary_sync_v1(text, text, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'security.api_field_dictionary_drift_v1(text, text, jsonb, text)', 'execute'), 'only the service role can sync or check');
end $t$;
SQL
echo "behaviour: all field dictionary checks passed"
