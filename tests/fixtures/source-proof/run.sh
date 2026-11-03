#!/usr/bin/env bash
# CF-247 source-proof lane and field backlog (Platform Admin mandate 3 Nov 2026 12:04 §5, §6) on isolated fixtures. Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: the lanes fixture's stubs, live definitions and seed
# (../lanes-gap-queue), the lanes migration 20261103160000 (v2.15.423, which this change builds on), stubs-extra.sql, the live relink definitions
# in live/ (pg_get_functiondef on 3 Nov 2026 12:10 AEDT, each checked against its live md5); fixtures-before.sql (the defect on the live
# definitions); the 20261103190000 migration unchanged, then again (already applied, nothing changed); fixtures.sql.
set -euo pipefail
cd "$(dirname "$0")"
DB=${PROOF_DB:-source_proof_fixtures}
LANES=../lanes-gap-queue
LMIG=../../../supabase/migrations/20261103160000_cf247_lanes_and_gap_queue.sql
MIG=../../../supabase/migrations/20261103190000_cf247_source_proof_lane_field_backlog.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
BEFORE_TICK=cad7fad43c0421d52f76315f28c8fbdf; BEFORE_PROV=c349b4f218c604d2d1937e66ab3a051c; BEFORE_YIELD=a38814324515b163a34129b7a9d01dbd
AFTER_TICK=$(sed -n "s/.*course_relink_tick_v1(integer)', array\['$BEFORE_TICK'\], array\['\([0-9a-f]*\)'\].*/\1/p" $MIG)
AFTER_PROV=$(sed -n "s/.*course_relink_provider_v1(uuid,integer)', array\['$BEFORE_PROV'\], array\['\([0-9a-f]*\)'\].*/\1/p" $MIG)
AFTER_YIELD=$(sed -n "s/.*admin_pipeline_yield(jsonb)', array\['$BEFORE_YIELD'\], array\['\([0-9a-f]*\)'\].*/\1/p" $MIG)
trap '[ -n "${PROOF_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d $DB -f $LANES/stubs.sql
for f in $LANES/live/*.def; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
$P -d $DB -f $LANES/seed.sql
$P -d $DB -1 -At -f $LMIG >/dev/null
[ "$(md5of 'public.admin_pipeline_yield(jsonb)')" = $BEFORE_YIELD ] || { echo "admin_pipeline_yield after the lanes migration: $(md5of 'public.admin_pipeline_yield(jsonb)')"; exit 1; }
$P -d $DB -f stubs-extra.sql
for f in live/security.*.def; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
[ "$(md5of 'security.course_relink_tick_v1(integer)')" = $BEFORE_TICK ] && [ "$(md5of 'security.course_relink_provider_v1(uuid,integer)')" = $BEFORE_PROV ] || { echo "loaded relink definitions differ from live"; exit 1; }
[ "$(md5sum < live/public.admin_pipeline_yield.def | cut -c1-32)" = a9d64bbca63b5e1c587edabf4e1fef59 ] || { echo "live admin_pipeline_yield file differs"; exit 1; }
echo "before (loaded = live): course_relink_tick_v1 $BEFORE_TICK, course_relink_provider_v1 $BEFORE_PROV; admin_pipeline_yield after v2.15.423 $BEFORE_YIELD"
$P -d $DB -f seed.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 3 || { echo "the migration did not apply all three guarded edits"; exit 1; }
check_after() {
  [ "$(md5of 'security.course_relink_tick_v1(integer)')" = "$AFTER_TICK" ] && [ "$(md5of 'security.course_relink_provider_v1(uuid,integer)')" = "$AFTER_PROV" ] \
  && [ "$(md5of 'public.admin_pipeline_yield(jsonb)')" = "$AFTER_YIELD" ] || { echo "after md5 differs"; exit 1; }
}
check_after; echo "after: course_relink_tick_v1 $AFTER_TICK, course_relink_provider_v1 $AFTER_PROV, admin_pipeline_yield $AFTER_YIELD"
SNAP="select md5(string_agg(x, '|' order by x)) from (select jobname || schedule || command || active::text x from cron.job union all select toolset_key || key || value::text from pipeline.platform_toolset_settings
      union all select kind || name from pipeline.component_register union all select jobname || description from pipeline.automation_catalogue) z"
S1=$($P -d $DB -Atc "$SNAP")
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 3 || { echo "a second run changed something"; exit 1; }
check_after; [ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed jobs, settings or registers"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all source-proof and field backlog fixtures passed"
