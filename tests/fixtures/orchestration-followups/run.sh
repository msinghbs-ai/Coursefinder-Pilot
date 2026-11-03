#!/usr/bin/env bash
# CF-247 orchestration follow-ups (IQ-00066, IQ-00053 residual, IQ-00063; 3 Nov 2026) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the Release A stubs and helpers (../plan-step-lane-hold),
# stubs-extra.sql (the live shapes these definitions read); the live definitions in live/ (v2.15.424, as pg_get_functiondef gives them, each
# checked against its live md5, read 3 Nov 2026 13:53-14:12 AEDT); fixtures-before.sql (the three defects reproduced on the live definitions,
# and the description check's answers recorded); the 20261103230000 migration unchanged (md5 guards, after-md5 checks); fixtures-off.sql (with
# the switches off the edited definitions behave as before); the migration again (already applied, nothing changed); fixtures.sql (every case
# with the switches on, and the description check gives the same answers as before). Drops the database at the end (ORCH2_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${ORCH2_DB:-orchestration_followups_fixtures}
MIG=../../../supabase/migrations/20261103230000_cf247_orchestration_followups.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $1 -Atc "select md5(pg_get_functiondef('$2'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
declare -A LIVE=(
  ["security.enrich_plan_v1(uuid)"]=818ef130484e567c35a7a2cf5a99d7c8
  ["security.enrich_plan_tick_v1(uuid)"]=cab734df6715e25014935bd22058343b
  ["security.admin_job_watch_v1(uuid)"]=34a1cfd57b367d0e60ccb4a85f56e228
  ["security.admin_jobs_tick_v1(integer)"]=fc698f9912cffd90a7b8ae32e33dd09e
  ["public.admin_pipeline_yield(jsonb)"]=34617ad96ea43189509c3f4dd536d50e
  ["security.course_description_check_v1(uuid,jsonb)"]=4822f66ee262cdfa1c4cd798cfc3dd26
  ["security.provider_onboarding_tick_v1()"]=01c5659bb4c364e80b0544fa60bca0ee
  ["security.admin_job_slice_v1(uuid,integer)"]=88f82c974b0ecde708a0550413791d86
  ["security.fc_sch_held_v1(uuid,boolean)"]=f8d6fb4bf9196dfa596b8274819670a6
  ["security.provider_sch_search_off_v1(uuid)"]=99185af92169668ac0437857467e4d3c
  ["security.pdesc_words_v1(text)"]=1a18bd60d2978c1885a25085b688afc7
  ["security.pdesc_similarity_v1(text,text)"]=357a9ebfde1c68a286ad4f685445cf9b
)
declare -A AFTER=(
  ["security.enrich_plan_v1(uuid)"]=$(sed -n "s/^--   security.enrich_plan_v1(uuid) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["security.enrich_plan_tick_v1(uuid)"]=$(sed -n "s/^--   security.enrich_plan_tick_v1(uuid) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["security.admin_job_watch_v1(uuid)"]=$(sed -n "s/^--   security.admin_job_watch_v1(uuid) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["security.admin_jobs_tick_v1(integer)"]=$(sed -n "s/^--   security.admin_jobs_tick_v1(integer) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["public.admin_pipeline_yield(jsonb)"]=$(sed -n "s/^--   public.admin_pipeline_yield(jsonb) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["security.course_description_check_v1(uuid,jsonb)"]=$(sed -n "s/^--   security.course_description_check_v1(uuid,jsonb) *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
  ["security.provider_onboarding_tick_v1()"]=$(sed -n "s/^--   security.provider_onboarding_tick_v1() *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${ORCH2_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f ../plan-step-lane-hold/stubs.sql
$P -d $DB -f ../plan-step-lane-hold/helpers.sql
$P -d $DB -f stubs-extra.sql
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of $DB "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of $DB "$s")"; exit 1; }; done
echo "before (loaded = live v2.15.424): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-helpers.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 7 ] || { echo "the migration did not apply its seven guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "after md5 of $s: $(md5of $DB "$s")"; exit 1; }; echo "after: $s ${AFTER[$s]}"; done
for k in plans.step_needs_work_on onboarding.website_check_on; do [ "$(q "select (value #>> '{}') from pipeline.platform_toolset_settings where key = '$k'")" = 1 ] || { echo "$k must ship on"; exit 1; }; done
[ "$(q "select value ? 'needs_source_discovery' from pipeline.platform_toolset_settings where key = 'plans.retry_waits_for_change'")" = t ] || { echo "retry waits list"; exit 1; }
$P -d $DB -f fixtures-off.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 7 ] || { echo "a second run changed something"; echo "$OUT" | tail -5; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of $DB "$s")" = "${AFTER[$s]}" ] || { echo "a second run changed $s"; exit 1; }; done
[ "$(q "select count(*) from pipeline.platform_toolset_settings where key in ('plans.step_needs_work_on', 'plans.outcome_window_hours', 'onboarding.website_check_on')")" = 3 ] || { echo "settings added twice"; exit 1; }
[ "$(q "select jsonb_array_length(value) from pipeline.platform_toolset_settings where key = 'plans.retry_waits_for_change'")" = 8 ] || { echo "retry waits list grew twice"; exit 1; }
[ "$(q "select count(*) from pipeline.automation_catalogue where description like '%step_needs_work_on%step_needs_work_on%' or description like '%website_check_on%website_check_on%'")" = 0 ] || { echo "catalogue lines added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all orchestration follow-up fixtures passed"
