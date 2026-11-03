#!/usr/bin/env bash
# Enrichment-plan lifecycle (CF-247 Agent A, Platform Admin P0 mandate 3 Nov 2026 10:44 §3) on isolated fixtures. Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the v2.15.419 harness stubs
# (../enrich-plan-continuity/stubs.sql) and stubs-extra.sql; the live definitions (../enrich-plan-continuity/live/ and live/ here, read with
# pg_get_functiondef on 3 Nov 2026), each checked against its live md5; the v2.15.419 migration 20261103120000 (this change is written
# against its result); then the 20261103150000 migration unchanged (its md5 guards and after-md5 checks run), then again (already applied,
# nothing added twice); then fixtures.sql. Drops the database.
set -euo pipefail
cd "$(dirname "$0")"
DB=${PLANLIFE_DB:-enrich_plan_lifecycle_fixtures}
BASE=../enrich-plan-continuity
MIG419=../../../supabase/migrations/20261103120000_cf247_enrich_plan_continuity.sql
MIG=../../../supabase/migrations/20261103150000_cf247_plan_lifecycle.sql
TMPMIG=$(mktemp)
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${PLANLIFE_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
$P -d $DB -f $BASE/stubs.sql
$P -d $DB -f stubs-extra.sql
declare -A LIVE=(
  ["public.admin_enrich_fields(text,jsonb)"]=184f74ae316051ec0cb4dd62c22b190d
  ["public.admin_enrich_plan(text,jsonb)"]=bd460fcd0e5b4e1dfd41ec1065c2a60c
  ["security.enrich_plan_auto_v1()"]=f9409768bf82bbb29f17ce514c8f9b11
  ["security.field_crosscheck_v1()"]=1023e1373007f09773d2d529d489e9ba
  ["security.enrich_plan_priority_v1()"]=366ff12040bac05d4e494956319a2b76
  ["security.enrich_plan_start_step_v1(uuid,text)"]=4e240fab607122eff455ea3c57b5447f
  ["security.enrich_unit_costs_v1()"]=9ffc69020b6f84c3b4b0af11650b634f
  ["security.enrich_plan_tick_v1(uuid)"]=0ba546e23715c8d3244e840c49e61e9b
)
for f in $BASE/live/*.sql live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 3 Nov 2026): ${#LIVE[@]} definitions"
# security.enrich_plan_v1 is a fixture stub here (the plan's steps come from security.fx_plan_steps); the migration's guard on its live md5
# (818ef130...) is checked against production, so the stub is given that guard's expectation by skipping the dependency block below
$P -d $DB -1 -At -f $MIG419 | grep -c ': applied' | grep -qx 4 || { echo "v2.15.419 did not apply"; exit 1; }
declare -A V419=(
  ["security.enrich_plan_auto_v1()"]=2d8944d7624b90cbbefb9925d602c92b
  ["public.admin_enrich_plan(text,jsonb)"]=0c9d3ec1b7d043e2d9f3ac83f9d99e1d
  ["security.enrich_plan_cancel_steps_v1(uuid,text)"]=60ec6f01a645eae5e246daa3e721deac
)
for s in "${!V419[@]}"; do [ "$(md5of "$s")" = "${V419[$s]}" ] || { echo "v2.15.419: $s is $(md5of "$s")"; exit 1; }; done
echo "v2.15.419 applied: auto, plan and cancel at the md5 this change is written against"
# the dependency guard names security.enrich_plan_v1's live md5; the fixture's stub differs, so the guard is pointed at the stub for the run
sed "s/818ef130484e567c35a7a2cf5a99d7c8/$(md5of 'security.enrich_plan_v1(uuid)')/" $MIG > $TMPMIG
grep -q "('security.enrich_plan_v1(uuid)', '818ef130484e567c35a7a2cf5a99d7c8')" $MIG || { echo "the migration no longer guards enrich_plan_v1 at its live md5"; exit 1; }
$P -d $DB -1 -At -f $TMPMIG | grep -c ': applied' | grep -qx 5 || { echo "the migration did not apply all five guarded changes"; exit 1; }
declare -A AFTER=(
  ["security.enrich_plan_auto_v1()"]=14d4769267f827736a0d4e2f013c4dad
  ["security.enrich_plan_start_step_v1(uuid,text)"]=50b4ea8f613389062efc2116ece62db7
  ["security.enrich_plan_tick_v1(uuid)"]=613782d4a04d3e6ce123c8837339d5e0
  ["public.admin_enrich_plan(text,jsonb)"]=dab650c5adefd9b0b9c006b0c5db4d5d
  ["security.enrich_plan_cancel_steps_v1(uuid,text)"]=209ac4e0a45fa307e3efb81f1e541598
)
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "after: $s is $(md5of "$s")"; exit 1; }; done
echo "after: five definitions at their expected md5"
SETTINGS=$(q "select count(*) from pipeline.platform_toolset_settings"); REG=$(q "select count(*) from pipeline.component_register"); CMD=$(q "select command from cron.job where jobname = 'integration-validate'")
$P -d $DB -1 -At -f $TMPMIG 2>/dev/null | grep -c 'already applied' | grep -qx 5 || { echo "a second run changed something"; exit 1; }
rm -f $TMPMIG
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "second run changed $s"; exit 1; }; done
[ "$(q "select count(*) from pipeline.platform_toolset_settings")" = "$SETTINGS" ] && [ "$(q "select count(*) from pipeline.component_register")" = "$REG" ] \
  && [ "$(q "select command from cron.job where jobname = 'integration-validate'")" = "$CMD" ] || { echo "second run added rows or changed the job"; exit 1; }
[ "$CMD" = "select security.integration_validate_v1(), security.integration_yield_checks_v1(), security.enrich_plan_orphans_issue_v1()" ] || { echo "job command: $CMD"; exit 1; }
[ "$(q "select string_agg(key || '=' || value::text, ',' order by key) from pipeline.platform_toolset_settings where key in ('plans.replan_on_evidence', 'plans.replan_on_retry', 'plans.fair_order', 'plans.replan_per_hour', 'plans.run_now_supersedes_auto')")" \
  = "plans.fair_order=0,plans.replan_on_evidence=0,plans.replan_on_retry=0,plans.replan_per_hour=0,plans.run_now_supersedes_auto=1" ] || { echo "shipped settings wrong"; exit 1; }
echo "second run: already applied, unchanged; evidence/retry re-plans, fair order and re-planning ship off; supersede on; integration-validate runs the orphan check"
$P -d $DB -f fixtures.sql 2>&1 | show
