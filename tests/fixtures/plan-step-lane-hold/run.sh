#!/usr/bin/env bash
# IQ-00064 (P1) plan step lane hold (CF-247 Agent D, 3 Nov 2026) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes); the five live definitions in live/ (v2.15.423, as
# pg_get_functiondef gives them; each checked against its live md5, read 3 Nov 2026 12:49 AEDT); fixtures-before.sql (the defect reproduced on
# the live definitions); the 20261103200000 migration unchanged (its md5 guards and after-md5 checks run); fixtures-off.sql (with the switch
# off the edited definitions behave as before); the migration again (already applied, nothing changed); fixtures.sql (every case with the
# switch on). Drops the database at the end (PLANHOLD_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${PLANHOLD_DB:-plan_step_lane_hold_fixtures}
MIG=../../../supabase/migrations/20261103200000_cf247_plan_step_lane_hold.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${PLANHOLD_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
$P -d $DB -f helpers.sql
declare -A LIVE=(
  ["security.flag_jobs_v1()"]=22fa89f4c0c3c238b3d281bd481309b2
  ["security.admin_job_watch_v1(uuid)"]=ad21305f89ee441bde462cc35e5a8a98
  ["security.admin_jobs_tick_v1(integer)"]=e760363a6af21d850f7e6e1c86bca0cb
  ["security.enrich_plan_tick_v1(uuid)"]=613782d4a04d3e6ce123c8837339d5e0
  ["security.admin_job_slice_v1(uuid,integer)"]=88f82c974b0ecde708a0550413791d86
)
declare -A AFTER=(
  ["security.flag_jobs_v1()"]=668251ec6027c1e9e6dd7d7a9b340bb9
  ["security.admin_job_watch_v1(uuid)"]=5025e03969c4ac41f06980936aa14741
  ["security.admin_jobs_tick_v1(integer)"]=fc698f9912cffd90a7b8ae32e33dd09e
  ["security.enrich_plan_tick_v1(uuid)"]=bdd7e639295c5c1acb35a7da39273f79
)
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live v2.15.423): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 4 || { echo "the migration did not apply its four guarded edits"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "after md5 of $s: $(md5of "$s")"; exit 1; }; echo "after: $s ${AFTER[$s]}"; done
$P -d $DB -f fixtures-off.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 4 || { echo "a second run changed something"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "a second run changed $s"; exit 1; }; done
[ "$($P -d $DB -Atc "select count(*) from pipeline.platform_toolset_settings where key like 'tasks.lane_hold%'")" = 2 ] || { echo "settings added twice"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.automation_catalogue where description like '%tasks.lane_hold_on%' or description like '%lane_task_waiting_v1%'")" = 2 ] || { echo "catalogue lines"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.automation_catalogue where description like '%lane_task_waiting_v1%lane_task_waiting_v1%' or description like '%lane_hold_on%lane_hold_on%lane_hold_on%'")" = 0 ] || { echo "catalogue lines added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
