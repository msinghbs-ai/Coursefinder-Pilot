#!/usr/bin/env bash
# CF-247 scholarship sources and ownership (handover 3 Nov 2026 Priority 3 items 9-12) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes), workstream A's contract as on main
# (stub-ops-contract.sql), the live definitions in live/ (svc_scholarship_ai_next and scholarship_ai_has_copy_v1 rebuilt by the lanes fixture
# from 20261103160000; svc_scholarship_ai_record from 20261014013200; scholarship_ai_review_open_v1 and scholarship_ai_enqueue_v1 read 3 Nov 2026), each checked against its
# live md5; seed.sql; fixtures-before.sql (the defects on the live definitions); the 20261104250000 migration, then again (already applied,
# nothing changed); fixtures.sql. Drops the database at the end (SCHRO_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${SCHRO_DB:-sch_reads_ownership_fixtures}
MIG=../../../supabase/migrations/20261104250000_cf247_sch_reads_ownership.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
SAI='public.svc_scholarship_ai_next(integer)'; HAS='security.scholarship_ai_has_copy_v1(bigint)'; OPEN='security.scholarship_ai_review_open_v1(bigint,text)'
ENQ='security.scholarship_ai_enqueue_v1(text,uuid[],uuid,boolean)'
REC='public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)'
declare -A LIVE=( ["$SAI"]=18e76dbc9984be55370434ca27066c7b ["$HAS"]=08db702a7e4231ea00acf36da80c04d4 ["$REC"]=aa337a9fb30a75452a7b54bddbf8d00f ["$OPEN"]=0f10b0a35109fd6a6c6be36e4d4ea26d ["$ENQ"]=04a9aa8c56fc0d5593c813da3ecd270d
  ["security.ops_remedy_register_v1(text,jsonb)"]=cec6cd2f6518b453fbc8ec3137ce39bd ["security.ops_root_cause_register_v1(text,jsonb)"]=591616a6a0bd60d607f65c41c18e2968 )
declare -A FILE=( ["$SAI"]=public.svc_scholarship_ai_next ["$HAS"]=security.scholarship_ai_has_copy_v1 ["$REC"]=public.svc_scholarship_ai_record ["$OPEN"]=security.scholarship_ai_review_open_v1 ["$ENQ"]=security.scholarship_ai_enqueue_v1 )
after() { sed -n "s/^--.*$1.* \([0-9a-f]\{32\}\) -> \([0-9a-f]\{32\}\)$/\2/p" $MIG | head -1; }
A_SAI=$(after 'svc_scholarship_ai_next(integer)'); A_HAS=$(after 'scholarship_ai_has_copy_v1(bigint)'); A_ENQ=$(after 'scholarship_ai_enqueue_v1(text,uuid\[\],uuid,boolean)'); A_REC=$(sed -n 's/^--  *aa337a9fb30a75452a7b54bddbf8d00f -> \([0-9a-f]\{32\}\)$/\1/p' $MIG)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${SCHRO_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f stubs.sql >/dev/null
$P -d $DB -f stub-ops-contract.sql >/dev/null
for s in "${!FILE[@]}"; do $P -d $DB -c "set check_function_bodies = off" -f "live/${FILE[$s]}.def" >/dev/null; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 3 Nov 2026): ${#LIVE[@]} definitions"
$P -d $DB -f seed.sql >/dev/null
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -f seed.sql >/dev/null  # seed.sql resets the rows the before cases touched
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 4 ] || { echo "the migration did not apply its four guarded edits"; echo "$OUT" | tail -5; exit 1; }
check() { [ "$(md5of "$SAI")" = "$A_SAI" ] && [ "$(md5of "$HAS")" = "$A_HAS" ] && [ "$(md5of "$REC")" = "$A_REC" ] && [ "$(md5of "$ENQ")" = "$A_ENQ" ] && [ "$(md5of "$OPEN")" = "${LIVE[$OPEN]}" ] \
  || { echo "after md5s: $(md5of "$SAI") $(md5of "$HAS") $(md5of "$REC")"; exit 1; }; }
check; echo "after: svc_scholarship_ai_next $A_SAI, scholarship_ai_has_copy_v1 $A_HAS, svc_scholarship_ai_record $A_REC, scholarship_ai_enqueue_v1 $A_ENQ; review_open_v1 unchanged"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select code || coalesce(verify_fn::text, '') || coalesce(action_fn::text, '') || authority from pipeline.ops_remedies
      union all select code || class from pipeline.ops_root_causes union all select jobname || command from cron.job union all select jobname from pipeline.automation_catalogue) s"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 4 ] || { echo "a second run changed an edited function"; exit 1; }
check; [ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed settings, remedies, root causes or jobs"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all scholarship sources and ownership fixtures passed"
