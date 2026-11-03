#!/usr/bin/env bash
# CF-247 IQ-00111 (fee reader units and holds, migration 20261104140000) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql, the four live definitions in live/ (pg_get_functiondef, 3 Nov 2026
# 21:2x AEDT), each checked against its live md5; seed.sql; fixtures-before.sql reproduces the 2 Nov defects on the live definitions; the
# migration is refused without workstream A's contract, then applied with it (stub-ops-contract.sql, A's contract section byte for byte), then
# applied again (already applied, nothing changed); fixtures.sql proves every case. Also runs the containment paste test (run-paste-test.sh).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${FEE_UNITS_DB:-cf_fee_units_holds_fixtures}
MIG=$ROOT/supabase/migrations/20261104140000_cf247_fee_units_holds.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
declare -A LIVE=(
  ["public.svc_fee_ai_record(uuid,jsonb,numeric,text)"]=0fb74c639ca69349ef18813282b0f987
  ["security.fee_course_pages_enqueue_v1()"]=91b2591e44bf9755950619006bf78e32
  ["security.fee_row_units_v1(jsonb)"]=8d534a87af685cfd5d0d8a7bd54f6388
  ["security.uni_adapter_excluded(uuid,text)"]=7359e28cc207833c658be6f169aa695c
)
REC='public.svc_fee_ai_record(uuid,jsonb,numeric,text)'; ENQ='security.fee_course_pages_enqueue_v1()'
after_of() { grep -F "select pg_temp.edit_once('$1', '$2', '" $MIG | sed -n "s/.*', '$2', '\([0-9a-f]\{32\}\)'.*/\1/p"; }
declare -A AFTER=(["$REC"]=$(after_of "$REC" 0fb74c639ca69349ef18813282b0f987) ["$ENQ"]=$(after_of "$ENQ" 91b2591e44bf9755950619006bf78e32))
trap '[ -n "${FEE_UNITS_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
$P -d $DB -f stubs.sql
for f in live/*.def; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "live definitions loaded (= live md5): ${#LIVE[@]}"
$P -d $DB -f seed.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
# without workstream A's contract the migration refuses and changes nothing
if OUT=$($P -d $DB -1 -At -f $MIG 2>&1); then echo "the migration ran without A's contract"; exit 1; fi
echo "$OUT" | grep -q "operations contract (migration 20261104010000) must be applied" || { echo "$OUT" | tail -3; exit 1; }
[ "$(md5of "$REC")" = 0fb74c639ca69349ef18813282b0f987 ] || { echo "a refused run changed the reader"; exit 1; }
echo "without A's contract: refused, nothing changed"
$P -d $DB -f stub-ops-contract.sql
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
for s in "$REC" "$ENQ"; do echo "$OUT" | grep -qxF "$s: applied" || { echo "the guarded edit of $s did not apply"; echo "$OUT" | tail -3; exit 1; }; done
for s in "${!LIVE[@]}"; do
  if [ -n "${AFTER[$s]:-}" ]; then [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "$s after md5 $(md5of "$s"), expected ${AFTER[$s]}"; exit 1; }
  else [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "the migration changed $s"; exit 1; }; fi
done
echo "applied: svc_fee_ai_record 0fb74c639ca69349ef18813282b0f987 -> ${AFTER[$REC]}, fee_course_pages_enqueue_v1 91b2591e44bf9755950619006bf78e32 -> ${AFTER[$ENQ]}; read-only helpers unchanged"
snap() { q "select md5(string_agg(x, '|' order by x)) from (select 'r:' || r::text x from pipeline.ops_root_causes r union all select 'm:' || m::text from pipeline.ops_remedies m
  union all select 's:' || s.toolset_key || s.key || s.value::text from pipeline.platform_toolset_settings s union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 'p:' || p::text from pipeline.fee_country_profiles p
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public')) z"; }
S1=$(snap)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 2 ] || { echo "second run did not report both edits already applied"; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed functions, settings, profiles or registers"; exit 1; }
echo "applied twice: the second run changed nothing"
[ "$(q "select count(*) from pipeline.ops_root_causes where code in ('fee_reader_units_misread','fee_reader_hold_bypass')")" = 2 ] || { echo "root causes not registered"; exit 1; }
[ "$(q "select count(*) from pipeline.ops_remedies where code in ('fee_integrity_recheck','fee_reader_units_holds_release','fee_wrong_value_withdraw')")" = 3 ] || { echo "remedies not registered"; exit 1; }
echo "root causes 2 and remedies 3 registered through A's contract"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "cases: $(grep -c "fx.ok(" fixtures.sql) after, $(grep -c "fx.ok(" fixtures-before.sql) before"
./run-paste-test.sh ${DB}_paste | sed 's/^/paste: /'
