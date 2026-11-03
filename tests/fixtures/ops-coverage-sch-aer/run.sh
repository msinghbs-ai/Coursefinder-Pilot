#!/usr/bin/env bash
# CF-247 autonomous operations, workstream C (scholarship and AER coverage; IQ-00041/IQ-00058 discovery outcomes) on isolated fixtures.
# Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the AER Phase B fixture
# database (../aer-phase-b: live AER columns, the Phase B definitions rebuilt from this repository and checked against live), the integration
# queue tables and security.integration_issue_upsert_v1 from 20261102120000 (load-iq.mjs), the scholarship and catalogue shapes (stubs.sql),
# security.fc_sch_eligible_v1 as live (fc-sch-eligible-live.sql), workstream A's contract (stub-ops-contract.sql, or A's migration when
# OPS_A_MIGRATION points at it). Checks the live md5s of what the migration edits or reads; fixtures-before.sql reproduces the defects on the live
# definitions; applies 20261104040000 (its own md5 guards and post-check run), applies it again (nothing changes), then fixtures.sql.
# Drops the database at the end (OPSC_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OPSC_DB:-ops_coverage_sch_aer_fixtures}
ROOT=../../..
MIG=$ROOT/supabase/migrations/20261104040000_cf247_ops_c_scholarship_aer_coverage.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
declare -A LIVE=(
  ["security.aer_provider_states_v1()"]=db5fb0c9f75b8bcca91bdcb34a2632d5
  ["security.aer_reconcile_v1(integer)"]=368319701d5998f1d7393dda48920b6d
  ["security.aer_eligible_v1()"]=ffafcedf3dadf707ca96b6b9425d0b3d
  ["security.fc_sch_eligible_v1(uuid)"]=2c44de24ea2d1bda123e1c8679591a9f
  ["security.scholarship_flag_v1(text,boolean)"]=0beb3b60ecf485cffcd3e20bf1948df0
)
AFTER=$(sed -n "s/^--   security.aer_provider_states_v1() *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPSC_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f ../aer-phase-b/stubs.sql >/dev/null
(cd $ROOT && node tests/fixtures/aer-phase-b/before.mjs) | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f $ROOT/supabase/migrations/20261102110000_cf247_aer_phase_b_assurance.sql 2>/dev/null
$P -d $DB -f stubs.sql >/dev/null
node load-iq.mjs | $P -d $DB -o /dev/null
$P -d $DB -f fc-sch-eligible-live.sql >/dev/null 2>&1
if [ -n "${OPS_A_MIGRATION:-}" ]; then $P -d $DB -1 -o /dev/null -f "$OPS_A_MIGRATION"; else $P -d $DB -f stub-ops-contract.sql >/dev/null; fi
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 3 Nov 2026): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-data.sql >/dev/null
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 1 ] || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
[ "$(md5of 'security.aer_provider_states_v1()')" = "$AFTER" ] || { echo "after md5: $(md5of 'security.aer_provider_states_v1()')"; exit 1; }
echo "after: security.aer_provider_states_v1() $AFTER"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select code || coalesce(verify_fn::text, '') from pipeline.ops_remedies union all select code from pipeline.ops_root_causes union all select jobname || schedule || command || active from cron.job union all select jobname || description from pipeline.automation_catalogue union all select kind || name from pipeline.component_register) s"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 1 ] || { echo "a second run changed the edited function"; exit 1; }
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed settings, remedies, jobs or the register"; exit 1; }
[ "$(md5of 'security.aer_provider_states_v1()')" = "$AFTER" ] || { echo "a second run changed the edit"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all workstream C fixtures passed"
