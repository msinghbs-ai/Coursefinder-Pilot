#!/usr/bin/env bash
# CF-247 AER technical holds (migrations 20261107130000, 20261107130100, 20261107130200; mandate 7 Nov 2026 21:57) on isolated fixtures. Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it.
#   suite A: the E13 / D-R2 / D-R3 chain rebuilt from this repository (live md5s checked), the old (live) reader seeded with production shapes, part 1 applied
#            (reader edit, stored-read recovery), then fixtures.sql;
#   suite B: tests/fixtures/aer-technical-holds/rule (the shared recovery rule's row-limit clause) on the AER selector database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
P="psql -v ON_ERROR_STOP=1 -q -X"
FX=tests/fixtures/aer-technical-holds
DB=${AERTH_DB:-aer_technical_holds_a}
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${AERTH_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
$P -d $DB -f tests/fixtures/e13-completeness-gate/stubs.sql >/dev/null
$P -d $DB -f tests/fixtures/aer-dr2-dr3/stubs.sql >/dev/null
node tests/fixtures/e13-completeness-gate/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql
node tests/fixtures/aer-dr2-dr3/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261103070000_cf247_aer_dr2_dr3_supersede_and_matrix_gate.sql
q() { $P -d $DB -Atc "$1"; }
[ "$(q "select md5(pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure))")" = 7faf2de4c2afe0a671f8f54c4a140fe4 ] || { echo "rebuilt enrich_entry_record_v1 differs from live"; exit 1; }
[ "$(q "select md5(pg_get_functiondef('security.course_entry_gate_v1(uuid,uuid[])'::regprocedure))")" = 4fc06c081e451f2d0fb0a504a4fbe10f ] || { echo "rebuilt course_entry_gate_v1 differs from live"; exit 1; }
[ "$(q "select md5(pg_get_functiondef('security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure))")" = 2e93bd9b3bc0c2ca7628f3a407b8f57f ] || { echo "rebuilt correction check differs from live"; exit 1; }
echo "suite A: rebuilt definitions = live (7 Nov 2026)"
$P -d $DB -f $FX/stubs-extra.sql >/dev/null
$P -d $DB -f $FX/seed.sql >/dev/null
OUT=$($P -d $DB -f $FX/fixtures.sql 2>&1) || { echo "$OUT" | tail -15; echo "suite A failed"; exit 1; }
echo "$OUT" | grep -E "PASS" ; echo "$OUT" | grep -qE "FAIL|ERROR" && { echo "$OUT" | grep -E "FAIL|ERROR"; exit 1; } || true
# the migration applied a second time changes nothing
AGAIN=$($P -d $DB -At -f supabase/migrations/20261107130000_cf247_aer_stored_read_recovery.sql 2>&1)
echo "$AGAIN" | grep -q "already applied" || { echo "a second run did not report already applied: $AGAIN"; exit 1; }
echo "PASS migration applied twice: already applied"

# suite B: the shared recovery rule on the AER selector database (live rule b194475a loaded by that fixture), with E13's row-limit function from suite A
DB2=${AERTH_DB_B:-aer_technical_holds_b}
$P -d postgres -c "drop database if exists $DB2" >/dev/null 2>&1
AERS_KEEP=1 AERS_DB=$DB2 bash tests/fixtures/aer-recovery-selector/run.sh >/dev/null 2>&1 || { echo "the selector fixture database did not build"; exit 1; }
trap '$P -d postgres -c "drop database if exists '$DB'" -c "drop database if exists '$DB2'" >/dev/null 2>&1' EXIT
$P -d $DB -Atc "select pg_get_functiondef('security.course_entry_max_rows_v1(uuid)'::regprocedure)" | $P -d $DB2 >/dev/null
[ "$($P -d $DB2 -Atc "select md5(pg_get_functiondef('security.aer_recovery_rule_v1(uuid)'::regprocedure))")" = b194475a46186bc674a3364816a8b06b ] || { echo "loaded rule differs from live"; exit 1; }
PGOPTIONS="-c aerth.phase=before" $P -d $DB2 -f $FX/rule.sql 2>&1 | sed 's/psql:[^ ]* NOTICE:  //' | grep -E "PASS|FAIL|ERROR"
$P -d $DB2 -o /dev/null -f supabase/migrations/20261107130100_cf247_aer_row_limit_rule.sql
PGOPTIONS="-c aerth.phase=after" $P -d $DB2 -f $FX/rule.sql 2>&1 | sed 's/psql:[^ ]* NOTICE:  //' | grep -E "PASS|FAIL|ERROR"
$P -d $DB2 -At -f supabase/migrations/20261107130100_cf247_aer_row_limit_rule.sql | grep -q "already applied" || { echo "rule migration second run changed something"; exit 1; }
echo "PASS rule migration applied twice: already applied"
echo "suite B: passed"
