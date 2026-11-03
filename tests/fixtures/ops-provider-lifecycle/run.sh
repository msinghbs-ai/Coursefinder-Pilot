#!/usr/bin/env bash
# CF-247 ops workstream G (provider identity and lifecycle; 3 Nov 2026) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (the live shapes the migration reads, cut to the columns used),
# the live definitions in live/ (v2.15.426, as pg_get_functiondef gives them, each checked against its live md5, read 3 Nov 2026 15:51 AEDT),
# stub-ops-contract.sql (workstream A's contract, exact names from the ops brief; replace with A's migration once pushed); the 20261104060000
# migration unchanged (guards, after-md5 check); the migration again (already applied, nothing added); fixtures.sql (every case). Drops the
# database at the end (OPSG_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OPSG_DB:-ops_provider_lifecycle_fixtures}
MIG=../../../supabase/migrations/20261104060000_cf247_ops_provider_identity_lifecycle.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $1 -Atc "select md5(pg_get_functiondef('$2'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
declare -A LIVE=(
  ["security.provider_onboarding_tick_v1()"]=181fc3dd2d78930c32e70cc24fb0adbd
  ["security.website_refusal_v1(text)"]=2bf77cfa3474619d71b33c3e7877ae0d
  ["security.site_host_v1(text)"]=04938c208412f46735c7a3f99348612c
  ["security.provider_archive_apply_v1(uuid,text,text,uuid,boolean)"]=5a2af698d6de7e5e3bf5ef3a860236c8
  ["security.provider_restore_v1(uuid,text,uuid,boolean)"]=a5e479c7ebc5060f710da1ffb95dd60d
)
AFTER=$(sed -n "s/^--   security.provider_onboarding_tick_v1() *[0-9a-f]* -> \([0-9a-f]*\)$/\1/p" $MIG)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${OPSG_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f stubs.sql
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of $DB "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of $DB "$s")"; exit 1; }; done
echo "before (loaded = live v2.15.426): ${#LIVE[@]} definitions"
# without workstream A the migration refuses to start
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) && { echo "the migration ran without workstream A's contract"; exit 1; }
echo "$OUT" | grep -q "workstream A (20261104010000) has not landed" || { echo "$OUT" | tail -3; exit 1; }
echo "guard: refuses before workstream A"
$P -d $DB -f stub-ops-contract.sql
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 1 ] || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
[ "$(md5of $DB 'security.provider_onboarding_tick_v1()')" = "$AFTER" ] || { echo "after md5 of the tick: $(md5of $DB 'security.provider_onboarding_tick_v1()')"; exit 1; }
echo "after: security.provider_onboarding_tick_v1() $AFTER"
for k in identity.check_on identity.issue_on identity.investigate_on lifecycle.propose_on; do [ "$(q "select value #>> '{}' from pipeline.platform_toolset_settings where key = '$k'")" = 1 ] || { echo "$k must ship on"; exit 1; }; done
for k in identity.candidate_check_on lifecycle.cascade_on; do [ "$(q "select value #>> '{}' from pipeline.platform_toolset_settings where key = '$k'")" = 0 ] || { echo "$k must ship off"; exit 1; }; done
[ "$(q "select count(*) from pipeline.platform_toolset_settings where (key like 'identity.%' or key like 'lifecycle.%') and (label = '' or unit is null or used_by is null)")" = 0 ] || { echo "a setting lacks a label, unit or used_by"; exit 1; }
[ "$(q "select count(*) from cron.job where jobname = 'provider-identity-check' and command !~ '(\(|,)\s*[0-9]'")" = 1 ] || { echo "job missing or has a number"; exit 1; }
echo "settings: four on (record and diagnose), two off (spend, remove work); job scheduled without a number"
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 1 ] || { echo "a second run changed something"; echo "$OUT" | tail -5; exit 1; }
[ "$(md5of $DB 'security.provider_onboarding_tick_v1()')" = "$AFTER" ] || { echo "a second run changed the tick"; exit 1; }
[ "$(q "select count(*) from pipeline.platform_toolset_settings where key like 'identity.%' or key like 'lifecycle.%'")" = 15 ] || { echo "settings added twice"; exit 1; }
[ "$(q "select count(*) from cron.job where jobname = 'provider-identity-check'")" = 1 ] || { echo "job scheduled twice"; exit 1; }
[ "$(q "select count(*) from pipeline.automation_catalogue where description like '%temporarily unavailable%temporarily unavailable%'")" = 0 ] || { echo "catalogue line added twice"; exit 1; }
[ "$(q "select count(*) from pipeline.ops_remedies")" = 5 ] || { echo "remedies added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all ops provider identity and lifecycle fixtures passed"
