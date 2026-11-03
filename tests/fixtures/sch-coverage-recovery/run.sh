#!/usr/bin/env bash
# CF-247 scholarship coverage recovery (mandate 4 Nov 2026 05:08 §2-§5, §9; Integration Controller "Read again" item) on isolated fixtures.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes; the
# helpers australian_university, url_on_provider_sites and scholarship_admission_provider_ok_v1 carry their live text), workstream A's contract
# (stub-ops-contract.sql), the work-continuity contract taken from its migration (20261104170000: settings, policies, work items, the report
# function), the three live definitions this change edits (live/, each checked against its live md5), seed.sql, fixtures-before.sql (the defects
# on the live definitions), the 20261104390000 migration, then again (nothing changes), fixtures.sql. Drops the database at the end
# (SCHCOV_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${SCHCOV_DB:-sch_coverage_recovery_fixtures}
ROOT=../../..
MIG=$ROOT/supabase/migrations/20261104390000_cf247_sch_coverage_recovery.sql
WC=$ROOT/supabase/migrations/20261104170000_cf247_work_continuity.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
UNI='security.scholarship_university(uuid)'; COV='security.scholarship_coverage_v1(uuid[])'; RN='public.svc_scholarship_read_next(integer)'
declare -A LIVE=( ["$UNI"]=00ca2485d894ae4542b643a112c2b764 ["$COV"]=cf9a3828b285791bd3d2dd1e8015d481 ["$RN"]=b30f59a20dff4c874c9fbed2659586c7
  ["security.australian_university(uuid)"]=4525429ae4085b67d9851ed2899329cb ["security.scholarship_admission_provider_ok_v1(uuid)"]=269f74a985acbc37f1f3b8615efa6254
  ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e )
declare -A FILE=( ["$UNI"]=security.scholarship_university ["$COV"]=security.scholarship_coverage_v1 ["$RN"]=public.svc_scholarship_read_next )
after() { sed -n "s/^--   $1 *[0-9a-f]\{32\} -> \([0-9a-f]\{32\}\)$/\1/p" $MIG | head -1; }
A_UNI=$(after 'security.scholarship_university(uuid)'); A_COV=$(after 'security.scholarship_coverage_v1(uuid\[\])'); A_RN=$(after 'public.svc_scholarship_read_next(integer)')
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${SCHCOV_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -f stubs.sql >/dev/null
$P -d $DB -f stub-ops-contract.sql >/dev/null
# the work-continuity contract as on main: settings, policy table, work items (sections 1-3) and its functions up to work_item_eligible_v1 (section 5)
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 4 review categories/' $WC; awk '/^-- 5 functions/,/^create or replace function security.work_review_room_v1/' $WC | sed '$d'; } \
  | $P -d $DB >/dev/null
for s in "${!FILE[@]}"; do $P -d $DB -c "set check_function_bodies = off" -f "live/${FILE[$s]}.def" >/dev/null; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 4 Nov 2026): ${#LIVE[@]} definitions"
$P -d $DB -f seed.sql >/dev/null
$P -d $DB -1 -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 3 ] || { echo "the migration did not apply its three guarded edits"; echo "$OUT" | tail -5; exit 1; }
check() { [ "$(md5of "$UNI")" = "$A_UNI" ] && [ "$(md5of "$COV")" = "$A_COV" ] && [ "$(md5of "$RN")" = "$A_RN" ] \
  || { echo "after md5s: $(md5of "$UNI") $(md5of "$COV") $(md5of "$RN")"; exit 1; }; }
check; echo "after: scholarship_university $A_UNI, scholarship_coverage_v1 $A_COV, svc_scholarship_read_next $A_RN"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select code || coalesce(verify_fn::text, '') || coalesce(action_fn::text, '') || authority from pipeline.ops_remedies
      union all select code || class from pipeline.ops_root_causes union all select jobname || command from cron.job union all select jobname from pipeline.automation_catalogue
      union all select code || owner from pipeline.scholarship_coverage_state_codes) s"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 3 ] || { echo "a second run changed an edited function"; exit 1; }
check; [ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed settings, remedies, root causes, states or jobs"; exit 1; }
echo "second run: already applied, unchanged"
# the v2.15.460 production defect (06:29 AEDT 4 Nov 2026) on the released definition, then the fix 20261104430000 (twice)
FIX=$ROOT/supabase/migrations/20261104430000_cf247_sch_coverage_classify_fix.sql
[ "$(md5of 'security.scholarship_coverage_classify_v1(uuid[])')" = a268ce816990d71ef545dbdc0ae28a5e ] || { echo "classify differs from live v2.15.460"; exit 1; }
$P -d $DB -f fixtures-dup-before.sql 2>&1 | show
A_FIX=$(sed -n "s/^--   security.scholarship_coverage_classify_v1(uuid\[\]) *[0-9a-f]\{32\} -> \([0-9a-f]\{32\}\)$/\1/p" $FIX)
OUT=$($P -d $DB -1 -At -f $FIX 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 1 ] && [ "$(md5of 'security.scholarship_coverage_classify_v1(uuid[])')" = "$A_FIX" ] || { echo "fix not applied: $OUT"; exit 1; }
OUT=$($P -d $DB -1 -At -f $FIX 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 1 ] || { echo "a second run of the fix changed the function"; exit 1; }
echo "fix: scholarship_coverage_classify_v1 a268ce816990d71ef545dbdc0ae28a5e -> $A_FIX; second run already applied"
$P -d $DB -f fixtures.sql 2>&1 | show
$P -d $DB -f fixtures-fix.sql 2>&1 | show
echo "all scholarship coverage recovery fixtures passed"
