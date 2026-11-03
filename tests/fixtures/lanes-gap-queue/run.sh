#!/usr/bin/env bash
# CF-247 lanes and gap queue (P0 mandate 3 Nov 2026 10:44 §3 Agent C, §6) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes), the live definitions in live/ (read with
# pg_get_functiondef on 3 Nov 2026 10:47-11:00 AEDT, base64, each checked against its live md5), seed.sql; fixtures-before.sql (the defects on
# the live definitions); the 20261103160000 migration unchanged, then again (already applied, nothing changed); fixtures.sql. A second database
# loads the tick as branch cf247-course-description-reader leaves it (md5 387f8edb...) and applies the migration to it.
set -euo pipefail
cd "$(dirname "$0")"
DB=${LANES_DB:-lanes_gap_queue_fixtures}
MIG=../../../supabase/migrations/20261103160000_cf247_lanes_and_gap_queue.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
declare -A LIVE=(
  ["public.svc_worker_report_v1(text,integer,integer,jsonb,text)"]="public.svc_worker_report_v1:6f3b816265f1a517b9d79140041669bb"
  ["security.field_gap_queue_tick_v1()"]="security.field_gap_queue_tick_v1:d909e54d6b6de0f8d2893fbb2d8553bd"
  ["public.svc_scholarship_ai_next(integer)"]="public.svc_scholarship_ai_next:ddef1e3dd794e26f3588f73e9d51e6b5"
  ["public.svc_scholarship_recheck_next(integer)"]="public.svc_scholarship_recheck_next:f35fa04f98a32d0ca4eb4064ea7db6eb"
  ["public.admin_pipeline_yield(jsonb)"]="public.admin_pipeline_yield:a9d64bbca63b5e1c587edabf4e1fef59"
  ["security.fc_budget_left_v1(text)"]="security.fc_budget_left_v1:e979d2e3d7319d845a5149e40abe6987"
  ["security.fc_month_refusal_v1(numeric)"]="security.fc_month_refusal_v1:8c1419332ff503abd69539ccbad1121d"
  ["security.fc_purpose_group_v1(text)"]="security.fc_purpose_group_v1:348bbb9ec1db966755e532f23e376897"
  ["security.worker_call_outcome_v1(integer,jsonb,integer,integer,integer)"]="security.worker_call_outcome_v1:8b256a6f7f9a9350927b4773c8a80304"
  ["security.ai_use_refusal_v1(text)"]="security.ai_use_refusal_v1:60c782e5aec7eb218c1149a3ad85dde2"
  ["security.fc_day_start_v1()"]="security.fc_day_start_v1:f5113f936c0c2a473e0d74cca51b5d97"
)
AFTER_REPORT=b110a648a8149eede42cbc69cce43a77; AFTER_TICK=200f3210c75a71e6e5f5f0eceb37ea66; AFTER_TICK_DESC=9bb80b419ee26a049b99a35fb278e272
AFTER_SAI=18e76dbc9984be55370434ca27066c7b; AFTER_REC=ccfaf9a9c6bbba4ce5fde64a3d7738af; AFTER_YIELD=a38814324515b163a34129b7a9d01dbd
build() {  # $1 database, $2 tick definition file
  $P -d postgres -c "drop database if exists $1" -c "create database $1" >/dev/null
  $P -d $1 -f stubs.sql
  for s in "${!LIVE[@]}"; do f=${LIVE[$s]%%:*}; [ "$f" = security.field_gap_queue_tick_v1 ] && file=$2 || file=live/$f.def
    $P -d $1 -c "set check_function_bodies = off" -f "$file"; done
  $P -d $1 -f seed.sql
}
md5of() { $P -d $1 -Atc "select md5(pg_get_functiondef('$2'::regprocedure))"; }
trap '[ -n "${LANES_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_desc" >/dev/null' EXIT
build $DB live/security.field_gap_queue_tick_v1.def
for s in "${!LIVE[@]}"; do m=${LIVE[$s]##*:}; [ "$(md5of $DB "$s")" = "$m" ] || { echo "loaded $s differs from live: $(md5of $DB "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 5 || { echo "the migration did not apply all five guarded edits"; exit 1; }
check_after() {
  [ "$(md5of $DB 'public.svc_worker_report_v1(text,integer,integer,jsonb,text)')" = $AFTER_REPORT ] && [ "$(md5of $DB 'security.field_gap_queue_tick_v1()')" = $AFTER_TICK ] \
  && [ "$(md5of $DB 'public.svc_scholarship_ai_next(integer)')" = $AFTER_SAI ] && [ "$(md5of $DB 'public.svc_scholarship_recheck_next(integer)')" = $AFTER_REC ] \
  && [ "$(md5of $DB 'public.admin_pipeline_yield(jsonb)')" = $AFTER_YIELD ] || { echo "after md5 differs"; exit 1; }
}
check_after; echo "after: report $AFTER_REPORT, tick $AFTER_TICK, scholarship_ai_next $AFTER_SAI, recheck_next $AFTER_REC, admin_pipeline_yield $AFTER_YIELD"
SNAP="select md5(string_agg(x, '|' order by x)) from (select jobname || command || active::text x from cron.job union all select toolset_key || key || value::text from pipeline.platform_toolset_settings
      union all select kind || name from pipeline.component_register union all select jobname || description from pipeline.automation_catalogue union all select mode || lane from pipeline.worker_mode_lanes) z"
S1=$($P -d $DB -Atc "$SNAP")
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 5 || { echo "a second run changed something"; exit 1; }
check_after; [ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed jobs, settings or registers"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
# the tick as the course-description branch leaves it: the same edit applies, with its own after md5
build ${DB}_desc desc-branch.field_gap_queue_tick_v1.def
[ "$(md5of ${DB}_desc 'security.field_gap_queue_tick_v1()')" = 387f8edbe3363ea52317e024d96f2369 ] || { echo "description-branch tick not as expected"; exit 1; }
$P -d ${DB}_desc -1 -At -f $MIG >/dev/null
[ "$(md5of ${DB}_desc 'security.field_gap_queue_tick_v1()')" = $AFTER_TICK_DESC ] || { echo "description-branch after md5: $(md5of ${DB}_desc 'security.field_gap_queue_tick_v1()')"; exit 1; }
$P -d ${DB}_desc -Atc "select pg_get_functiondef('security.field_gap_queue_tick_v1()'::regprocedure)" | grep -q 'enrich_course_text_gaps_v1' || { echo "description-branch line lost"; exit 1; }
echo "after the course-description branch: tick 387f8edb... -> $AFTER_TICK_DESC, its line kept"
echo "all lanes and gap queue fixtures passed"
