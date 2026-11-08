#!/usr/bin/env bash
# CF-247 SCH / DISC (lane G, 8 Nov 2026): honest scholarship coverage states, suggested listings of eligible providers, no weekly re-read of an unchanged
# catalogue, and park-and-recover for transient page failures (IQ-00129), on isolated fixtures.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the scholarship coverage path as released
# (../sch-coverage-recovery stubs, workstream A's contract, the work-continuity contract, the real migrations 20261104390000 and 20261104430000), the shapes this
# change calls (stubs.sql, ../sch-l4-handoff/stubs-extra.sql), the live text of every definition this change edits (live/, each checked against its live md5),
# seed.sql, fixtures-before.sql (the defects, rolled back), the migration, then again (nothing changes), fixtures.sql. Drops the database at the end (SCHDISC_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${SCHDISC_DB:-g_sch_disc_fixtures}
ROOT=../../..
SC=../sch-coverage-recovery
L4=../sch-l4-handoff
M=$ROOT/supabase/migrations
MIG=$M/20261108160000_cf247_sch_disc_honest_coverage_and_recovery.sql
WC=$M/20261104170000_cf247_work_continuity.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
ITEMS='security.scholarship_coverage_items_v1(uuid[])'; CLS='security.scholarship_coverage_classify_v1(uuid[])'; REC='public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)'
declare -A LIVE=( ["$ITEMS"]=5605660603d40b3917001c37807a09bb ["$CLS"]=7cd322359de3c7f823df240452afc2a8 ["$REC"]=9207e7fd49ffa0ba7ae5f3aae4bbcbf6 )
declare -A FILE=( ["$ITEMS"]=security.scholarship_coverage_items_v1 ["$CLS"]=security.scholarship_coverage_classify_v1 ["$REC"]=public.svc_scholarship_listing_record_v2 )
after() { sed -n "s/^--   $1 *[0-9a-f]\{32\} -> \([0-9a-f]\{32\}\)$/\1/p" $MIG | head -1; }
A_ITEMS=$(after 'security.scholarship_coverage_items_v1(uuid\[\])'); A_CLS=$(after 'security.scholarship_coverage_classify_v1(uuid\[\])'); A_REC=$(after 'public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)')
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${SCHDISC_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
# the scholarship coverage path as released
$P -d $DB -f $SC/stubs.sql >/dev/null
$P -d $DB -f $SC/stub-ops-contract.sql >/dev/null 2>&1
$P -d $DB -c "insert into pipeline.ops_root_causes(code, class, title) values ('sch_zero_scholarships', 'data', 'Provider with zero scholarships'),
  ('sch_under_represented', 'data', 'Under-represented'), ('sch_category_missing', 'data', 'Category missing'), ('sch_listing_not_fanned_out', 'dependency', 'Listing not fanned out')
  on conflict do nothing" >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 4 review categories/' $WC; awk '/^-- 5 functions/,/^create or replace function security.work_review_room_v1/' $WC | sed '$d'; } | $P -d $DB >/dev/null
for f in $SC/live/*.def; do $P -d $DB -c "set check_function_bodies = off" -f $f >/dev/null; done
$P -d $DB -1 -f $M/20261104390000_cf247_sch_coverage_recovery.sql >/dev/null 2>&1 || { echo "20261104390000 did not replay"; exit 1; }
$P -d $DB -1 -f $M/20261104430000_cf247_sch_coverage_classify_fix.sql >/dev/null 2>&1 || { echo "20261104430000 did not replay"; exit 1; }
$P -d $DB -f $L4/stubs-extra.sql >/dev/null
$P -d $DB -c "set check_function_bodies = off" -f $L4/live/security.scholarship_publishability_for_v1.def >/dev/null
$P -d $DB -f stubs.sql >/dev/null
# the definitions this change edits, as live on 8 Nov 2026
for s in "${!FILE[@]}"; do $P -d $DB -c "set check_function_bodies = off" -f "live/${FILE[$s]}.def" >/dev/null; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 8 Nov 2026): ${#LIVE[@]} definitions"
$P -d $DB -f seed.sql >/dev/null
$P -d $DB -1 -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 3 ] || { echo "the migration did not apply its three guarded edits"; echo "$OUT" | tail -5; exit 1; }
check() { [ "$(md5of "$ITEMS")" = "$A_ITEMS" ] && [ "$(md5of "$CLS")" = "$A_CLS" ] && [ "$(md5of "$REC")" = "$A_REC" ] \
  || { echo "after md5s: $(md5of "$ITEMS") $(md5of "$CLS") $(md5of "$REC")"; exit 1; }; }
check; echo "after: items $A_ITEMS, classify $A_CLS, listing_record_v2 $A_REC"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select jobname || command from cron.job
      union all select jobname from pipeline.automation_catalogue union all select code || resolved::text || owner from pipeline.scholarship_coverage_state_codes
      union all select kind || name from pipeline.component_register) s"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 3 ] || { echo "a second run changed an edited function"; exit 1; }
check; [ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed settings, jobs, states or the register"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all scholarship SCH/DISC fixtures passed"
