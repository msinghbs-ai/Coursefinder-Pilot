#!/usr/bin/env bash
# Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: isolated PostgreSQL only (never a Supabase project).
# 1 schema.sql: the 39 tables the change touches, then parity.sql compared with production-parity.txt (columns, constraints, foreign keys, indexes,
#   triggers, RLS, policies, grants), table by table;
# 2 the live definitions the change reads or edits, each md5-checked against production (read 5 Nov 2026 19:17-19:25 AEDT);
# 3 reference rows, the production-volume data (seed.sql) and the named cases (named.sql);
# 4 courses_page as it is today for 13 argument sets (the baseline), then the migration, then the migration again (no change);
# 5 the same 13 argument sets: same rows, same order, same fields, same totals (backward compatibility), plus the new fields;
# 6 cases.sql (layouts, roles, cities, adapter status, timestamps, field states, server-side sort across pages);
# 7 the benchmark at production volume (bench.sql). Keeps the database when CCOL_KEEP=1 (the browser test uses it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
FX=tests/fixtures/course-catalogue-columns
DB=${CCOL_DB:-c_ccol_fixture}
MIG=supabase/migrations/20261106300000_cf247_course_catalogue_columns.sql
P="psql -X -q -v ON_ERROR_STOP=1 -d $DB"
psql -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${CCOL_KEEP:-}" ] || trap 'psql -X -q -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -f $FX/schema.sql >/dev/null
TABLES=$(grep -o '^[a-z_]*\.[a-z0-9_]*' $FX/production-parity.txt | paste -sd, -)
$P -At -v tables="$TABLES" -f $FX/parity.sql > /tmp/ccol-parity.$$ || true
if ! diff -u $FX/production-parity.txt /tmp/ccol-parity.$$; then echo 'FAIL schema differs from production'; rm -f /tmp/ccol-parity.$$; exit 1; fi
rm -f /tmp/ccol-parity.$$
echo "PASS production-schema parity: $(wc -l < $FX/production-parity.txt) tables (columns, constraints, foreign keys, indexes, triggers, RLS, policies, grants)"
for f in live-functions.sql live-page-base.sql live-page-unfiltered.sql; do PGOPTIONS='-c check_function_bodies=off' $P -f $FX/$f >/dev/null; done
md5of() { $P -At -c "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($1) with ordinality t(f, o)"; }
LIVE="array['public.admin_read(text,jsonb)','security.admin_course_page_fast(jsonb)','security.admin_course_page_fast_base(jsonb)','security.admin_course_page_unfiltered_fast(jsonb)','security.current_role_rank()','security.pipeline_num_v1(text,numeric)','security.provider_university_groups(uuid)','security.university_group_provider_ids(text)']"
WANT="6b1bb9d569bd13390f76803f9a710053 2dc6ee8ba523afeec04d862f3a2ced8a afbef16111a09e3680061547bbb1329a 5db669272a3fa612b1268ef8502a9b7c d709d92dbd7a648ccf78e594d68ca980 09f9b1551daf42b4a0c9795e6f30c6d4 6debe54efc9feaf959c68d9fbb2cf644 180e86128f2fa29d36ff01e7d7fd5847"
[ "$(md5of "$LIVE")" = "$WANT" ] || { echo "FAIL live definitions differ: $(md5of "$LIVE")"; exit 1; }
echo 'PASS the 8 live definitions rebuilt byte for byte (md5 = production)'
$P -c "grant execute on all functions in schema public, security to authenticated" >/dev/null
$P -f $FX/stubs.sql >/dev/null
$P -f $FX/seed.sql >/dev/null
$P -f $FX/named.sql >/dev/null
echo "PASS data: $($P -At -c "select count(*) from catalogue.courses") courses, $($P -At -c "select count(*) from pipeline.field_enrich_items") field items, $($P -At -c "select count(*) from pipeline.course_attribute_coverage") field states"
# 4 baseline
$P -f $FX/compat.sql -v phase=before >/dev/null
$P -1 -o /dev/null -f $MIG
AFTER=$(md5of "array['security.admin_course_page_fast(jsonb)','security.admin_course_page_fast_base(jsonb)','public.admin_read(text,jsonb)']")
$P -1 -o /dev/null -f $MIG 2>/tmp/ccol-second.$$
grep -c 'already applied' /tmp/ccol-second.$$ | grep -qx 2 || { cat /tmp/ccol-second.$$; echo 'FAIL second run did not find the edits applied'; exit 1; }
rm -f /tmp/ccol-second.$$
[ "$(md5of "array['security.admin_course_page_fast(jsonb)','security.admin_course_page_fast_base(jsonb)','public.admin_read(text,jsonb)']")" = "$AFTER" ] || { echo 'FAIL a second run changed a definition'; exit 1; }
[ "$($P -At -c "select count(*) from pipeline.admin_table_columns")" = 36 ] && [ "$($P -At -c "select count(*) from pipeline.platform_toolset_settings where key like 'catalogue_layout.%'")" = 4 ] || { echo 'FAIL rows added twice'; exit 1; }
echo "PASS migration applied, then applied again unchanged (after: $AFTER; admin_read unchanged)"
# 5 backward compatibility
$P -f $FX/compat.sql -v phase=after 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
# 6 cases
$P -f $FX/cases.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p' | tee /tmp/ccol-cases.$$
! grep -q '^ERROR' /tmp/ccol-cases.$$ || { rm -f /tmp/ccol-cases.$$; exit 1; }
echo "PASS $(grep -c '^NOTICE PASS' /tmp/ccol-cases.$$) database cases"; rm -f /tmp/ccol-cases.$$
# 7 benchmark
$P -f $FX/bench.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
# the browser test signs in as these people; their layouts start empty
$P -c "update pipeline.admin_table_layouts set layout = null, previous = null" >/dev/null
echo 'PASS Course Catalogue columns isolated PostgreSQL fixture'
