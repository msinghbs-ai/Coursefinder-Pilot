#!/usr/bin/env bash
# CF-247 IQ-00067 (coverage admission: a course locked by hand aborted the whole batch; Platform Admin mandate 3 Nov 2026 15:52 §9) on isolated
# fixtures. Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: the integration queue
# stubs and queue (as workstream A's fixture does), stubs-extra.sql, workstream A's contract (stub-ops-contract.sql, copied byte for byte from
# origin/cf247-ops-a d8b11de1), then the four live definitions in live/ (pg_get_functiondef, 3 Nov 2026 15:57 AEDT), each checked against its
# live md5. fixtures-before.sql reproduces the 13:53 failure on the live definitions; the migration is refused without A's contract, applied, then
# applied again (already applied, nothing changed); fixtures.sql proves the batch goes on past the locked item.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${IQ67_DB:-iq67_coverage_admit_fixtures}
MIG=$ROOT/supabase/migrations/20261104080000_cf247_iq67_coverage_admit_lock_isolation.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
declare -A LIVE=(
  ["security.coverage_admission_apply_v1(integer,text,text[])"]=2e85e6cbb5d2e64ea1b50fe490c4da76
  ["security.coverage_admission_gated_v1(text,integer,text,text[])"]=4e4e7f9ae2bb5e177774f1e394fdfe0d
  ["security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)"]=75a53dbbcd5e20e1018a05b61f6763aa
  ["security.course_page_rule_v1(text,text)"]=b441e4c76d9bc401dd1604c23456e952
)
APPLY='security.coverage_admission_apply_v1(integer,text,text[])'
GATED='security.coverage_admission_gated_v1(text,integer,text,text[])'
after_of() { grep -F "select pg_temp.edit_once('$1', '$2', '" $MIG | sed -n "s/.*', '$2', '\([0-9a-f]\{32\}\)'.*/\1/p"; }
declare -A AFTER=(["$APPLY"]=$(after_of "$APPLY" 2e85e6cbb5d2e64ea1b50fe490c4da76) ["$GATED"]=$(after_of "$GATED" 4e4e7f9ae2bb5e177774f1e394fdfe0d))
for s in "${!AFTER[@]}"; do [ ${#AFTER[$s]} = 32 ] || { echo "after md5 for $s not found in the migration"; exit 1; }; done
trap '[ -n "${IQ67_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
$P -d $DB -f $ROOT/tests/fixtures/integration-queue/stubs.sql
$P -d $DB -1 -o /dev/null -f $ROOT/supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f stubs-extra.sql
for f in live/*.def; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "live definitions loaded (= live md5): ${#LIVE[@]}"
# without workstream A's contract the migration refuses to run and changes nothing
# Integration Controller 3 Nov 2026: the fix ships before A's contract; it applies inside a rolled-back transaction and only notes the missing contract
OUT=$( { echo 'begin;'; cat $MIG; echo 'rollback;'; } | $P -d $DB -At 2>&1 ) || { echo "$OUT" | tail -3; exit 1; }
echo "$OUT" | grep -q "operations contract is not deployed yet" || { echo "$OUT" | tail -3; exit 1; }
[ "$(md5of "$APPLY")" = 2e85e6cbb5d2e64ea1b50fe490c4da76 ] || { echo "a refused run changed the apply"; exit 1; }
echo "without A's contract: applies (checked in a rolled-back transaction) and registers nothing"
$P -d $DB -f stub-ops-contract.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
for s in "$APPLY" "$GATED"; do echo "$OUT" | grep -qxF "$s: applied" || { echo "the guarded edit of $s did not apply"; exit 1; }; done
for s in "${!LIVE[@]}"; do
  if [ -n "${AFTER[$s]:-}" ]; then [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "$s after md5 $(md5of "$s"), expected ${AFTER[$s]}"; exit 1; }
  else [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "the migration changed $s"; exit 1; }; fi
done
echo "applied: coverage_admission_apply_v1 2e85e6cbb5d2e64ea1b50fe490c4da76 -> ${AFTER[$APPLY]}, coverage_admission_gated_v1 4e4e7f9ae2bb5e177774f1e394fdfe0d -> ${AFTER[$GATED]}; link apply and page rule unchanged"
snap() { q "select md5(string_agg(x, '|' order by x)) from (select 'r:' || r::text x from pipeline.ops_root_causes r union all select 'm:' || m::text from pipeline.ops_remedies m
  union all select 's:' || s.toolset_key || s.key || s.value::text from pipeline.platform_toolset_settings s union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security'
  union all select 'h:' || h.course_id || h.attribute || h.seen_count from pipeline.coverage_admission_holds h) z"; }
S1=$(snap)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 2 ] || { echo "second run did not report both edits already applied"; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed functions, settings, registers or holds"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all IQ-00067 fixtures passed"
