#!/usr/bin/env bash
# IQ-00064 (P0) plan step lane hold (CF-247 Agent D, Release A, 3 Nov 2026) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes) and helpers.sql; the six live
# definitions in live/ (v2.15.423, as pg_get_functiondef gives them; each checked against its live md5, re-read 3 Nov 2026 13:20 AEDT);
# fixtures-before.sql (the defect reproduced on the live definitions); seed-reconcile.sql (the 18 measured steps, their real ids); the
# 20261103200000 migration unchanged (md5 guards, after-md5 checks, the reconciliation guard); the reconciliation checked; fixtures-off.sql
# (with the switch set off the edited definitions behave as before); the migration again (already applied, nothing changed); fixtures.sql
# (every case with the switch on). A second database checks that the reconciliation refuses a set that no longer matches. Drops both at the
# end (PLANHOLD_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")"
DB=${PLANHOLD_DB:-plan_step_lane_hold_fixtures}
MIG=../../../supabase/migrations/20261103200000_cf247_plan_step_lane_hold.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $1 -Atc "select md5(pg_get_functiondef('$2'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
declare -A LIVE=(
  ["security.flag_jobs_v1()"]=22fa89f4c0c3c238b3d281bd481309b2
  ["security.admin_job_watch_v1(uuid)"]=ad21305f89ee441bde462cc35e5a8a98
  ["security.admin_jobs_tick_v1(integer)"]=e760363a6af21d850f7e6e1c86bca0cb
  ["security.enrich_plan_tick_v1(uuid)"]=613782d4a04d3e6ce123c8837339d5e0
  ["security.integration_yield_checks_v1()"]=2bcba102aa776a21c888bae711fd3374
  ["security.admin_job_slice_v1(uuid,integer)"]=88f82c974b0ecde708a0550413791d86
)
declare -A AFTER=(
  ["security.flag_jobs_v1()"]=668251ec6027c1e9e6dd7d7a9b340bb9
  ["security.admin_job_watch_v1(uuid)"]=34a1cfd57b367d0e60ccb4a85f56e228
  ["security.admin_jobs_tick_v1(integer)"]=fc698f9912cffd90a7b8ae32e33dd09e
  ["security.enrich_plan_tick_v1(uuid)"]=cab734df6715e25014935bd22058343b
  ["security.integration_yield_checks_v1()"]=265d5fa8637185016018b3b81dad1b39
)
build() {
  $P -d postgres -c "drop database if exists $1" -c "create database $1" >/dev/null 2>&1
  $P -d $1 -f stubs.sql
  $P -d $1 -f helpers.sql
  for f in live/*.sql; do $P -d $1 -c "set check_function_bodies = off" -f "$f"; done
  for s in "${!LIVE[@]}"; do [ "$(md5of $1 "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of $1 "$s")"; exit 1; }; done
}
[ -n "${PLANHOLD_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_refuse" >/dev/null 2>&1' EXIT
build $DB
echo "before (loaded = live v2.15.423): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -f seed-reconcile.sql
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || true
[ "$(echo "$OUT" | grep -c ': applied')" = 5 ] || { echo "the migration did not apply its five guarded edits"; echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -q 'IQ-00064 reconciliation: 18 step(s) set failed' || { echo "reconciliation did not run"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "after md5 of $s: $(md5of $DB "$s")"; exit 1; }; echo "after: $s ${AFTER[$s]}"; done
[ "$(q "select (value #>> '{}') from pipeline.platform_toolset_settings where key = 'tasks.lane_hold_on'")" = 1 ] || { echo "tasks.lane_hold_on must ship on"; exit 1; }
# the reconciliation: 18 steps failed with the reason and the remaining items; restart eligibility kept; one event; nothing removed
[ "$(q "select count(*) from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) x where x->>'status' = 'failed' and x->>'note' ~ '^ended done with [0-9]+ items unprocessed \(IQ-00064\)$' and (x->'restart'->>'retry_on')::boolean and x ? 'remaining'")" = 18 ] || { echo "reconciliation: 18 failed steps expected"; exit 1; }
[ "$(q "select sum((x->>'remaining')::numeric) from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) x where x ? 'reconciled'")" = 314 ] || { echo "reconciliation: 314 items expected"; exit 1; }
[ "$(q "select note from (select x->>'note' note from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) x where x->'ref'->>'id' = '8c12b05c-b9b7-4f5b-9b74-c1ced82b7088') z")" = 'ended done with 111 items unprocessed (IQ-00064)' ] || { echo "reconciliation note"; exit 1; }
[ "$(q "select count(*) from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) x where x->>'status' = 'done'")" = 35 ] || { echo "reconciliation touched other steps"; exit 1; }
[ "$(q "select count(*)||':'||max(detail->>'count')||':'||max(detail->>'id_md5') from pipeline.admin_control_events where action = 'iq64_plan_step_reconcile'")" = '1:18:effa0dc2788015cfbef9c66247d5bade' ] || { echo "reconciliation event"; exit 1; }
[ "$(q "select count(*) from pipeline.admin_jobs")" = 18 ] && [ "$(q "select count(*) from pipeline.enrich_plan_runs")" = 18 ] || { echo "rows removed"; exit 1; }
[ "$(q "select count(*) from security.plan_unfinished_done_v1()")" = 0 ] || { echo "the reconciled steps are still listed as unfinished"; exit 1; }
echo "ok reconciliation: 18 measured steps failed with the reason (314 items), restart eligibility kept, 35 other steps unchanged, one event, nothing removed"
$P -d $DB -f fixtures-off.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || true
[ "$(echo "$OUT" | grep -c '^security\..*: already applied$')" = 5 ] && echo "$OUT" | grep -q 'reconciliation: already applied' || { echo "a second run changed something"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "a second run changed $s"; exit 1; }; done
[ "$(q "select count(*) from pipeline.platform_toolset_settings where key like 'tasks.%' and key <> 'tasks.stall_seconds'")" = 4 ] || { echo "settings added twice"; exit 1; }
[ "$(q "select count(*) from pipeline.admin_control_events where action = 'iq64_plan_step_reconcile'")" = 1 ] || { echo "reconciled twice"; exit 1; }
[ "$(q "select count(*) from pipeline.automation_catalogue where description like '%lane_task_waiting_v1%lane_task_waiting_v1%' or description like '%lane_hold_on%lane_hold_on%lane_hold_on%' or description like '%plan_unfinished_done%plan_unfinished_done%'")" = 0 ] || { echo "catalogue lines added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
# refusal: one measured step no longer matches (its task now reports every item done): the migration refuses and changes nothing
build ${DB}_refuse
$P -d ${DB}_refuse -f seed-reconcile.sql
$P -d ${DB}_refuse -c "update pipeline.admin_jobs set result = result || '{\"done\": 1}' where id = '316bf0b2-1e98-48bb-816f-62fedb32733e'"
if $P -d ${DB}_refuse -1 -f $MIG >/dev/null 2>&1; then echo "refusal: a changed set was reconciled"; exit 1; fi
[ "$($P -d ${DB}_refuse -Atc "select count(*) from pipeline.admin_control_events")" = 0 ] && [ "$(md5of ${DB}_refuse 'security.flag_jobs_v1()')" = 22fa89f4c0c3c238b3d281bd481309b2 ] \
  && [ "$($P -d ${DB}_refuse -Atc "select count(*) from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) x where x->>'status' = 'failed'")" = 0 ] || { echo "refusal: something changed"; exit 1; }
echo "ok refusal: 17 of the 18 measured steps still match, the migration is refused as one transaction and nothing changes"
