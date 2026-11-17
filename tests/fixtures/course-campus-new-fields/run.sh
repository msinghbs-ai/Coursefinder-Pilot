#!/usr/bin/env bash
# Guards: Platform Admin 18 Nov 2026 07:03 (Courses: Study load and Empty reason; Campuses: Primary and Locality). Isolated PostgreSQL only (never a Supabase project).
# Builds the catalogue-course-description fixture (production parity, 35,700 courses, the live page functions md5-checked), adds the columns the migration reads
# (prep.sql), then checks that the four bodies migration 20261118073000 edits are the live ones; applies it (only those four change, to the stated md5, and the
# Campuses read is added), applies it again (no change), refuses a changed live body with nothing applied, restores the bodies from the held recovery (twice) and
# brings them back; runs scenarios.sql on the migrated database and shows its first REGRESSION check failing on the database from before. CCN_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${CCN_DB:-c_ccn_fixture}
M=supabase/migrations/20261118073000_cf247_course_study_load_empty_reason_campus_primary_locality.sql
HELD=supabase/held/course_campus_new_fields_forward_recovery.sql
F=tests/fixtures/course-campus-new-fields
q() { psql -X -d "$1" -Atc "$2"; }
cleanup() { local code=$?; trap - EXIT; if [ -z "${CCN_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_t" "${DB}_rf" "${DB}_s" "${DB}_old_old" "${DB}_t_t" "${DB}_rf_rf"; do psql -X -q -d postgres -c "drop database if exists $d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
OUT=$(CCD_KEEP=1 CCD_DB=$DB bash tests/fixtures/catalogue-course-description/run.sh 2>&1) || { echo "$OUT" | tail -15; echo 'FAIL the catalogue-course-description fixture'; exit 1; }
for d in "${DB}_old" "${DB}_t" "${DB}_rf" "${DB}_s"; do psql -X -q -d postgres -c "drop database if exists $d" >/dev/null 2>&1; done
echo "PASS base: the catalogue-course-description fixture ($(echo "$OUT" | grep -c 'PASS') checks)"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -f $F/prep.sql >/dev/null
declare -A LIVE=( ['security.admin_course_page_fast(jsonb)']=19d7dde7292e5707a7e1bc110c6106d8 ['security.admin_course_page_fast_base(jsonb)']=3b6e10e4212aebc944abaac866e50f7a ['security.course_list_with_extras_v1(jsonb)']=2a0b931a4f8f3673f2dac447ee25dd2e ['admin_read(text,jsonb)']=f4df73816871c19c233d0708f9d44ef6 )
for sig in "${!LIVE[@]}"; do
  [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "FAIL the fixture's $sig is not live ${LIVE[$sig]}"; exit 1; }
  grep -qF -- "${sig#public.}  ${LIVE[$sig]} -> " $M || { echo "FAIL the header does not record $sig"; exit 1; }
done
echo 'PASS the four bodies the migration edits are the live ones (body md5 read 18 Nov 2026)'
psql -X -q -d postgres -c "drop database if exists ${DB}_old" -c "create database ${DB}_old template $DB" >/dev/null
FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue', 'search') and p.prokind = 'f' order by 1"
q $DB "$FNS" | sort > /tmp/ccn0.$$
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null
q $DB "$FNS" | sort > /tmp/ccn1.$$
[ "$(comm -23 /tmp/ccn0.$$ /tmp/ccn1.$$ | sed 's/ .*//' | sort | tr '\n' ' ')" = "$(printf '%s\n' "${!LIVE[@]}" | sort | tr '\n' ' ')" ] || { echo 'FAIL the changed functions are not exactly the four'; comm -3 /tmp/ccn0.$$ /tmp/ccn1.$$; exit 1; }
[ "$(comm -13 <(sed 's/ .*//' /tmp/ccn0.$$) <(sed 's/ .*//' /tmp/ccn1.$$) | tr '\n' ' ')" = "security.admin_campuses_page_v2(jsonb) " ] || { echo 'FAIL the functions added are not exactly security.admin_campuses_page_v2'; exit 1; }
for sig in "${!LIVE[@]}"; do A=$(grep -oP -- "\Q${sig}\E  ${LIVE[$sig]} -> \K[0-9a-f]{32}" $M | head -1); grep -qF "$sig $A" /tmp/ccn1.$$ || { echo "FAIL $sig is not at $A"; exit 1; }; done
[ "$(q $DB "select status || ' ' || replaced_by from pipeline.component_register where kind = 'function' and name = 'security.admin_campus_page_fast(jsonb)'")" = 'retiring security.admin_campuses_page_v2(jsonb)' ] || { echo 'FAIL the earlier Campuses read is not marked retiring'; exit 1; }
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null; q $DB "$FNS" | sort | cmp -s - /tmp/ccn1.$$ || { echo 'FAIL the second run changed a function'; exit 1; }
[ "$(q $DB "select count(*) from pipeline.admin_table_columns where screen = 'courses'")" = 42 ] || { echo 'FAIL the Course catalogue registry does not hold 42 columns after two runs'; exit 1; }
echo 'PASS applied: only the four bodies changed, each to its stated md5; the Campuses read was added and the earlier one marked retiring; applied again: no change'
psql -X -q -d postgres -c "drop database if exists ${DB}_t" -c "create database ${DB}_t template ${DB}_old" >/dev/null
psql -X -q -d ${DB}_t -c "create or replace function security.course_list_with_extras_v1(p_page jsonb) returns jsonb language sql as \$\$ select p_page \$\$"
if O=$(psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_t -1 -At -f $M 2>&1); then echo 'FAIL applied over a changed live body'; exit 1; fi
grep -qF 'differs from the definition this change replaces' <<<"$O" || { echo "FAIL unexpected refusal: $O"; exit 1; }
[ "$(q ${DB}_t "select md5(prosrc) from pg_proc where oid = 'security.admin_course_page_fast(jsonb)'::regprocedure")" = "${LIVE['security.admin_course_page_fast(jsonb)']}" ] && [ "$(q ${DB}_t "select (to_regprocedure('security.admin_campuses_page_v2(jsonb)') is null)::text || (select count(*) from pg_indexes where indexname = 'courses_study_load_idx')")" = true0 ] || { echo 'FAIL the refused migration left a change behind'; exit 1; }
echo 'PASS refused: a changed live body stops the migration and nothing is applied'
psql -X -q -d postgres -c "drop database if exists ${DB}_rf" -c "create database ${DB}_rf template $DB" >/dev/null
psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_rf -At -f $HELD >/dev/null; psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_rf -At -f $HELD >/dev/null
for sig in "${!LIVE[@]}"; do [ "$(q ${DB}_rf "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "FAIL the recovery did not restore $sig"; exit 1; }; done
[ "$(q ${DB}_rf "select status from pipeline.component_register where name = 'security.admin_campus_page_fast(jsonb)'")" = active ] || { echo 'FAIL the recovery did not put the earlier Campuses read back in use'; exit 1; }
psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_rf -1 -At -f $M >/dev/null; q ${DB}_rf "$FNS" | sort | cmp -s - /tmp/ccn1.$$ || { echo 'FAIL the migration did not come back after the recovery'; exit 1; }
echo 'PASS forward recovery: the held file restores the four bodies byte for byte (twice); the migration brings the edits back'
rm -f /tmp/ccn0.$$ /tmp/ccn1.$$
psql -X -q -d postgres -c "drop database if exists ${DB}_s" -c "create database ${DB}_s template $DB" >/dev/null
O=$(psql -X -d ${DB}_s -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p')
echo "$O" | sed 's/^NOTICE //'
! echo "$O" | grep -q '^ERROR' || { echo 'FAIL scenarios'; exit 1; }
O=$(psql -X -d ${DB}_old -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p') || true  # it is expected to stop
echo "$O" | grep -q '^ERROR FAIL REGRESSION' || { echo 'FAIL the scenarios did not fail on a REGRESSION check before the migration'; echo "$O" | tail -3; exit 1; }
echo "PASS regression: before the migration the scenarios stop at: $(echo "$O" | grep '^ERROR FAIL' | head -1 | sed 's/^ERROR FAIL //')"
echo 'PASS course and campus new fields fixture'
