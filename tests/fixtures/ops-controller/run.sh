#!/usr/bin/env bash
# CF-247 P0 workstream A (AI Operations Controller, migration 20261104010000) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the integration queue stubs (../integration-queue/stubs.sql) and the
# queue itself from repository migration 20261102120000, checked against the live md5s of the three queue functions this change calls (read
# 3 Nov 2026 15:48 AEDT); stubs-extra.sql (the other live shapes read or guarded here). Checks that stub-ops-contract.sql is the contract
# section of the migration byte for byte, applies the migration (the queue functions must be unchanged by it), applies it again (nothing
# changes), then runs fixtures-contract.sql and, when the controller is present, fixtures.sql. Drops the database at the end (OPS_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${OPS_DB:-ops_controller_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104010000_cf247_ops_controller.sql
FX=tests/fixtures/ops-controller
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
# the contract stub other workstreams load is the migration's contract section, byte for byte
diff <(awk '/^-- >>> contract/{f=1} f{print} /^-- <<< contract/{f=0}' $MIG) <(sed -n '/^-- >>> contract/,$p' $FX/stub-ops-contract.sql) >/dev/null \
  || { echo "stub-ops-contract.sql differs from the migration's contract section"; exit 1; }
echo "stub-ops-contract.sql = the migration's contract section"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPS_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f $FX/stubs-extra.sql
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=f292f65689a35e213a3d12a539c11b1d
  ["security.integration_issue_transition_v1(bigint,text,text,text,jsonb)"]=3e8fc63663e5120c50f0859da97dd7a8
  ["security.integration_issue_close_v1(bigint,text,jsonb)"]=4cae8eaee7444e0aa942b2702eb10bc6
)
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "queue functions (repository = live): ${#LIVE[@]}"
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | show
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "the migration changed $s"; exit 1; }; done
snap() { q "select md5(string_agg(x, '|' order by x)) from (select 'r:' || r::text x from pipeline.ops_root_causes r union all select 'm:' || m::text from pipeline.ops_remedies m
  union all select 's:' || s.key || s.value::text from pipeline.platform_toolset_settings s union all select 'j:' || j.jobname || j.schedule || j.command || j.active from cron.job j
  union all select 'c:' || c.jobname from pipeline.automation_catalogue c union all select 'o:' || o.code from pipeline.ops_outcome_codes o
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 't:' || t.tgname from pg_trigger t where not t.tgisinternal) z"; }
S1=$(snap)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed the registers, settings, jobs or triggers"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f $FX/fixtures-contract.sql 2>&1 | show
if [ -f $FX/fixtures.sql ]; then $P -d $DB -f $FX/fixtures.sql 2>&1 | show; fi
echo "all ops controller fixtures passed"
