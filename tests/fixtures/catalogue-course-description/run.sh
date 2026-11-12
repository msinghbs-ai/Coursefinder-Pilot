#!/usr/bin/env bash
# Guards: Platform Admin 12 Nov 2026 20:50 (Course catalogue: filter for updated course descriptions; the description shown as wrapped text). Isolated PostgreSQL only
# (never a Supabase project). Builds the course-catalogue-columns fixture (production parity, 35,700 courses, the live page functions md5-checked), then checks that
# the three bodies migration 20261112210000 edits are live; applies it (only those three change, to the stated md5), applies it again (no change), refuses a
# changed live body with nothing applied, restores the bodies from the held recovery (twice) and brings them back; runs scenarios.sql on the migrated database and
# shows its first REGRESSION check failing on the database from before. CCD_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${CCD_DB:-c_ccd_fixture}
M=supabase/migrations/20261112210000_cf247_catalogue_course_description.sql
HELD=supabase/held/catalogue_course_description_forward_recovery.sql
F=tests/fixtures/catalogue-course-description
q() { psql -X -d "$1" -Atc "$2"; }
cleanup() { local code=$?; trap - EXIT; if [ -z "${CCD_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_t" "${DB}_rf" "${DB}_s"; do psql -X -q -d postgres -c "drop database if exists $d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
OUT=$(CCOL_KEEP=1 CCOL_DB=$DB bash tests/fixtures/course-catalogue-columns/run.sh 2>&1) || { echo "$OUT" | tail -15; echo 'FAIL the course-catalogue-columns fixture'; exit 1; }
echo "PASS base: the course-catalogue-columns fixture ($(echo "$OUT" | grep -c '^PASS\|PASS ') checks)"
declare -A LIVE=( ['security.admin_course_page_fast(jsonb)']=c4d2eb53d5ffb893217f3e408dd01fd0 ['security.admin_course_page_fast_base(jsonb)']=56bcf191ba8dd6da8f84c170c7c3c5f9 ['security.course_list_with_extras_v1(jsonb)']=91e88067d293f13cf99a95fa2faa8f93 )
for sig in "${!LIVE[@]}"; do
  [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "FAIL the fixture's $sig is not live ${LIVE[$sig]}"; exit 1; }
  grep -qF -- "--   $sig  ${LIVE[$sig]} -> " $M || { echo "FAIL the header does not record $sig"; exit 1; }
done
echo 'PASS the three bodies the migration edits are the live ones (body md5 read 12 Nov 2026)'
psql -X -q -d postgres -c "drop database if exists ${DB}_old" -c "create database ${DB}_old template $DB" >/dev/null
FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue', 'search') and p.prokind = 'f' order by 1"
q $DB "$FNS" | sort > /tmp/ccd0.$$
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null
q $DB "$FNS" | sort > /tmp/ccd1.$$
[ "$(comm -23 /tmp/ccd0.$$ /tmp/ccd1.$$ | sed 's/ .*//' | sort | tr '\n' ' ')" = "$(printf '%s\n' "${!LIVE[@]}" | sort | tr '\n' ' ')" ] || { echo 'FAIL the changed functions are not exactly the three'; comm -3 /tmp/ccd0.$$ /tmp/ccd1.$$; exit 1; }
[ "$(comm -13 <(sed 's/ .*//' /tmp/ccd0.$$) <(sed 's/ .*//' /tmp/ccd1.$$) | tr '\n' ' ')" = "security.course_completeness_v1(uuid) " ] || { echo 'FAIL the functions added are not exactly security.course_completeness_v1'; exit 1; }
for sig in "${!LIVE[@]}"; do A=$(grep -oP -- "--   \Q$sig\E  ${LIVE[$sig]} -> \K[0-9a-f]{32}" $M); grep -qF "$sig $A" /tmp/ccd1.$$ || { echo "FAIL $sig is not at $A"; exit 1; }; done
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null; q $DB "$FNS" | sort | cmp -s - /tmp/ccd1.$$ || { echo 'FAIL the second run changed a function'; exit 1; }
echo 'PASS applied: only the three bodies changed, each to its stated md5, and security.course_completeness_v1 was added; applied again: no change'
psql -X -q -d postgres -c "drop database if exists ${DB}_t" -c "create database ${DB}_t template ${DB}_old" >/dev/null
psql -X -q -d ${DB}_t -c "create or replace function security.course_list_with_extras_v1(p_page jsonb) returns jsonb language sql as \$\$ select p_page \$\$"
if O=$(psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_t -1 -At -f $M 2>&1); then echo 'FAIL applied over a changed live body'; exit 1; fi
grep -qF 'differs from the definition this change replaces' <<<"$O" || { echo "FAIL unexpected refusal: $O"; exit 1; }
[ "$(q ${DB}_t "select md5(prosrc) from pg_proc where oid = 'security.admin_course_page_fast(jsonb)'::regprocedure")" = "${LIVE['security.admin_course_page_fast(jsonb)']}" ] && [ "$(q ${DB}_t "select to_regprocedure('security.course_completeness_v1(uuid)') is null")" = t ] || { echo 'FAIL the refused migration left an edit behind'; exit 1; }
echo 'PASS refused: a changed live body stops the migration and nothing is applied'
psql -X -q -d postgres -c "drop database if exists ${DB}_rf" -c "create database ${DB}_rf template $DB" >/dev/null
psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_rf -At -f $HELD >/dev/null; psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_rf -At -f $HELD >/dev/null
for sig in "${!LIVE[@]}"; do [ "$(q ${DB}_rf "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "FAIL the recovery did not restore $sig"; exit 1; }; done
psql -X -q -v ON_ERROR_STOP=1 -d ${DB}_rf -1 -At -f $M >/dev/null; q ${DB}_rf "$FNS" | sort | cmp -s - /tmp/ccd1.$$ || { echo 'FAIL the migration did not come back after the recovery'; exit 1; }
echo 'PASS forward recovery: the held file restores the three bodies byte for byte (twice); the migration brings the edits back'
rm -f /tmp/ccd0.$$ /tmp/ccd1.$$
psql -X -q -d postgres -c "drop database if exists ${DB}_s" -c "create database ${DB}_s template $DB" >/dev/null
O=$(psql -X -d ${DB}_s -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p')
echo "$O" | sed 's/^NOTICE //'
! echo "$O" | grep -q '^ERROR' || { echo 'FAIL scenarios'; exit 1; }
O=$(psql -X -d ${DB}_old -f $F/scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p') || true  # it is expected to stop
echo "$O" | grep -q '^ERROR FAIL REGRESSION' || { echo 'FAIL the scenarios did not fail on a REGRESSION check before the migration'; echo "$O" | tail -3; exit 1; }
echo "PASS regression: before the migration the scenarios stop at: $(echo "$O" | grep '^ERROR FAIL' | head -1 | sed 's/^ERROR FAIL //')"
echo 'PASS catalogue course description fixture'
