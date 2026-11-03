#!/usr/bin/env bash
# CF-247 workstream D: job lifecycle, explicit outcomes and self-healing (P0 mandate 3 Nov 2026 15:37 §7) on isolated fixtures. Needs a scratch
# PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the Release A and v2.15.426 stubs (../plan-step-lane-hold, ../orchestration-followups) and their v2.15.424 live definitions, then the
#     v2.15.426 migration itself, so the definitions this change edits are the live v2.15.426 ones (each checked against its live md5, read
#     3 Nov 2026 15:43 AEDT);
#   2 workstream A's contract (stub-ops-contract.sql, or A's migration when OPS_A_MIGRATION names it), stubs-extra.sql and the live
#     definitions in live/ (security.admin_job_close_v1, security.enrich_plan_auto_v1, security.enrich_plan_inputs_v1; md5 checked);
#   3 fixtures-before.sql (the defects reproduced on the live definitions); the 20261104020000 migration (md5 guards, after-md5 checks);
#     fixtures-off.sql (the switches off: as before); the migration again (already applied, nothing changed); fixtures.sql (every case).
# Drops the database at the end (OPSD_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OPSD_DB:-ops_lifecycle_fixtures}
MIG=../../../supabase/migrations/20261104020000_cf247_ops_job_lifecycle.sql
MIG426=../../../supabase/migrations/20261103230000_cf247_orchestration_followups.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $1 -Atc "select md5(pg_get_functiondef('$2'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
# live v2.15.426, read 3 Nov 2026 15:43-15:58 AEDT
declare -A LIVE=(
  ["security.admin_job_close_v1(uuid)"]=233236ffc66e438edb21c4f51a6c45a1
  ["security.admin_job_watch_v1(uuid)"]=995f26c437f0abfb3c666271cd622fec
  ["security.enrich_plan_tick_v1(uuid)"]=77705c2b34e13801f4d7ccc5773bd4c1
  ["security.enrich_plan_v1(uuid)"]=a63146c23989eb64ee2248e3f32eade6
  ["security.plan_outcomes_v1()"]=0f127f0241764413fb87278f403a2e14
  ["security.enrich_plan_auto_v1()"]=14d4769267f827736a0d4e2f013c4dad
  ["security.enrich_plan_inputs_v1(uuid)"]=a546c58cfc4897ef7cf1a19f2041a2ae
  ["security.plan_run_outcome_v1(jsonb)"]=fa05333f110034b24f2a799f275e3a7f
  ["security.admin_jobs_tick_v1(integer)"]=e5f4881ca7423c8aa0df0923a5057806
  ["security.admin_job_slice_v1(uuid,integer)"]=88f82c974b0ecde708a0550413791d86
  ["security.plan_step_work_v1(uuid,text)"]=47f76698820b07824d444eae704b544b
)
declare -A AFTER
for s in "security.admin_job_close_v1(uuid)" "security.admin_job_watch_v1(uuid)" "security.enrich_plan_tick_v1(uuid)" "security.enrich_plan_v1(uuid)" \
         "security.plan_outcomes_v1()" "security.enrich_plan_auto_v1()"; do
  e=$(printf '%s' "$s" | sed 's/[.]/\\./g; s/[(]/[(]/g; s/[)]/[)]/g')
  AFTER["$s"]=$(sed -n "s/^--   $e *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
done
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPSD_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
# 1 the live v2.15.426 state
$P -d $DB -f ../plan-step-lane-hold/stubs.sql
$P -d $DB -f ../plan-step-lane-hold/helpers.sql
$P -d $DB -f ../orchestration-followups/stubs-extra.sql
for f in ../orchestration-followups/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
$P -d $DB -f ../orchestration-followups/fixtures-helpers.sql
OUT=$($P -d $DB -1 -At -f $MIG426 2>&1) || { echo "$OUT" | tail -5; exit 1; }
# 2 workstream A's contract, the shapes read here, the other live definitions
if [ -n "${OPS_A_MIGRATION:-}" ]; then $P -d $DB -1 -f "$OPS_A_MIGRATION"; else $P -d $DB -f stub-ops-contract.sql; fi
$P -d $DB -f stubs-extra.sql
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of $DB "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of $DB "$s")"; exit 1; }; done
echo "before (loaded = live v2.15.426): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-helpers.sql
# 3 the defects, the change, the switches, idempotence, every case
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 6 ] || { echo "the migration did not apply its six guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "after md5 of $s: $(md5of $DB "$s")"; exit 1; }; echo "after: $s ${AFTER[$s]}"; done
for k in ops.lease_orphan_close_on ops.lane_orphan_release_on ops.task_dedupe_on ops.retry_cost_pause_on ops.answer_replay_on plans.step_dependency_on; do
  [ "$(q "select (value #>> '{}') from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = '$k'")" = 0 ] || { echo "$k must ship off"; exit 1; }; done
for k in ops.outcome_on plans.lane_backlog_wait_on plans.retry_ignores_min_days; do
  [ "$(q "select (value #>> '{}') from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = '$k'")" = 1 ] || { echo "$k must ship on"; exit 1; }; done
[ "$(q "select (value #>> '{}') from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'plans.empty_cycles_max'")" = 3 ] || { echo "plans.empty_cycles_max ships 3"; exit 1; }
$P -d $DB -f fixtures-off.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 6 ] || { echo "a second run changed something"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "a second run changed $s"; exit 1; }; done
[ "$(q "select count(*) from cron.job where jobname = 'ops-job-lifecycle'")" = 1 ] || { echo "job scheduled twice"; exit 1; }
[ "$(q "select count(*) from pipeline.platform_toolset_settings where key like 'ops.%' or key in ('plans.empty_cycles_max', 'plans.empty_cycles_quiet_days', 'plans.lane_backlog_wait_on', 'plans.step_dependency_on', 'plans.retry_ignores_min_days')")" = 25 ] || { echo "settings added twice"; exit 1; }
[ "$(q "select count(*) from pipeline.automation_catalogue where description like '%enrich_plan_auto_runs%enrich_plan_auto_runs%'")" = 0 ] || { echo "catalogue line added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all ops lifecycle fixtures passed"
