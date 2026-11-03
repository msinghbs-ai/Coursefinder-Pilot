#!/usr/bin/env bash
# CF-247 workstream F cost and yield (P0 AI operations §11 and §16; 3 Nov 2026) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (the live shapes these definitions read);
# stub-ops-contract.sql (workstream A's shared contract, exactly its names); the live definitions in live/ (as pg_get_functiondef gives them,
# each checked against its live md5, read 3 Nov 2026 15:42 AEDT); fixtures-before.sql (the waste paid for and unmeasured on the live
# definitions); the 20261104050000 migration unchanged (md5 guards, after-md5 checks); the migration again (already applied, nothing added);
# fixtures.sql (every case). Drops the database at the end (OPSF_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OPSF_DB:-ops_cost_fixtures}
MIG=../../../supabase/migrations/20261104050000_cf247_ops_cost_yield.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $1 -Atc "select md5(pg_get_functiondef('$2'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
declare -A LIVE=(
  ["public.svc_fc_spend(numeric,text,uuid,text)"]=d418c451d681ffd95134f5f4dcf7c504
  ["security.waste_guard_v1()"]=101d6fbf97e3c7d3e5830f762c33107b
)
declare -A AFTER=(
  ["public.svc_fc_spend(numeric,text,uuid,text)"]=$(sed -n "s/^--   public.svc_fc_spend(numeric,text,uuid,text) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["security.waste_guard_v1()"]=$(sed -n "s/^--   security.waste_guard_v1() *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPSF_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f stubs.sql
# A's contract is absent: the migration refuses to run
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) && { echo "the migration ran without workstream A's contract"; exit 1; }
echo "$OUT" | grep -q "workstream A's shared contract (migration 20261104010000) must be applied first" || { echo "$OUT" | tail -3; exit 1; }
echo "without A's contract: refused"
$P -d $DB -f stub-ops-contract.sql
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of $DB "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of $DB "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -f helpers.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 2 ] || { echo "the migration did not apply its two guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "after md5 of $s: $(md5of $DB "$s")"; exit 1; }; echo "after: $s ${AFTER[$s]}"; done
SNAP="select (select count(*) from pipeline.platform_toolset_settings), (select count(*) from pipeline.ops_root_causes), (select count(*) from pipeline.ops_remedies),
  (select count(*) from pipeline.component_register), (select md5(description) from pipeline.automation_catalogue where jobname = 'waste-guard')"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 2 ] || { echo "a second run changed something"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "a second run changed $s"; exit 1; }; done
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run added settings, registry rows, register rows or a catalogue line: $S1 / $(q "$SNAP")"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all cost and yield fixtures passed"
