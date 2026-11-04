#!/usr/bin/env bash
# CF-247 scholarship hand-off to Layer 4 (IQ-00264; direction 4 Nov 2026 10:00 §2) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a
# Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database with the production path this change joins, as on main:
#   ../sch-coverage-recovery (live shapes, workstream A's contract, the work-continuity contract, then the real migrations 20261104390000 and
#   20261104430000: coverage states and the classifier); stubs-extra.sql (the remaining live shapes); the live publishing checks
#   (security.scholarship_publishability_for_v1) and the live Curator edit route (public.admin_scholarship_edit, live only, transcribed and
#   checked against its live md5); the human-assisted recovery contract, sections 1-11 of 20261104450000 (settings, classes, interventions,
#   raise, resolve, tick, the lane handlers); every definition this change calls or edits checked against its live md5; seed.sql;
#   fixtures-before.sql (the defects, rolled back); the migration 20261104480000, then again (nothing changes); fixtures.sql.
# Drops the database at the end (L4H_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${L4H_DB:-sch_l4_handoff_fixtures}
ROOT=../../..
SC=../sch-coverage-recovery
M=$ROOT/supabase/migrations
MIG=$M/20261104480000_cf247_sch_l4_handoff.sql
HAR=$M/20261104450000_cf247_human_assisted_recovery.sql
WC=$M/20261104170000_cf247_work_continuity.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
ITEMS='security.scholarship_coverage_items_v1(uuid[])'
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${L4H_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
# the scholarship coverage path as released (v2.15.460/461)
$P -d $DB -f $SC/stubs.sql >/dev/null
$P -d $DB -f $SC/stub-ops-contract.sql >/dev/null 2>&1
# root causes registered live by workstream C (20261104040000) that the coverage migration's remedies treat
$P -d $DB -c "insert into pipeline.ops_root_causes(code, class, title) values ('sch_zero_scholarships', 'data', 'Provider with zero scholarships'),
  ('sch_under_represented', 'data', 'Under-represented'), ('sch_category_missing', 'data', 'Category missing'), ('sch_listing_not_fanned_out', 'dependency', 'Listing not fanned out')
  on conflict do nothing" >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 4 review categories/' $WC; awk '/^-- 5 functions/,/^create or replace function security.work_review_room_v1/' $WC | sed '$d'; } | $P -d $DB >/dev/null
for f in $SC/live/*.def; do $P -d $DB -c "set check_function_bodies = off" -f $f >/dev/null; done
$P -d $DB -1 -f $M/20261104390000_cf247_sch_coverage_recovery.sql >/dev/null 2>&1
$P -d $DB -1 -f $M/20261104430000_cf247_sch_coverage_classify_fix.sql >/dev/null 2>&1
$P -d $DB -f stubs-extra.sql >/dev/null
$P -d $DB -c "set check_function_bodies = off" -f live/security.scholarship_publishability_for_v1.def -f live/public.admin_scholarship_edit.def >/dev/null
# the human-assisted recovery contract as on main (v2.15.463): sections 1-11
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 12 metrics/' $HAR; } | $P -d $DB >/dev/null
declare -A LIVE=( ["$ITEMS"]=d3dfacf0e70fd33162eab7a57aca72e4 ["security.scholarship_coverage_classify_v1(uuid[])"]=c072494c5e0082e2a8b58a06dfd94a00
  ["security.layer4_intervention_raise_v1(jsonb)"]=8fcabf1137cf126158c260759ac9f9aa ["security.layer4_intervention_resolve_v1(bigint,text,jsonb)"]=1385d22605acc549b545beb4f6a7d312
  ["security.layer4_interventions_tick_v1()"]=da2aaf0fd207edf4c36a55a8e2172424 ["security.scholarship_publishability_for_v1(uuid[])"]=d8123efd7e6e0d36fb6ebe9c8d38fdf7
  ["public.admin_scholarship_edit(uuid,text,jsonb)"]=0147553263d5a1b8795a0b31ebf11019 ["security.har_quote_ok_v1(text)"]=036a0df333451181b044ffc606e91b69
  ["security.har_sch_generate_v1(integer)"]=983b3939e4c8686fa6fcb03752f56370 ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e )
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 4 Nov 2026 11:12): ${#LIVE[@]} definitions"
$P -d $DB -f seed.sql >/dev/null
$P -d $DB -f fixtures-before.sql 2>&1 | show
A_ITEMS=$(sed -n "s/^--   security.scholarship_coverage_items_v1(uuid\[\]) *[0-9a-f]\{32\} -> \([0-9a-f]\{32\}\)$/\1/p" $MIG)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 1 ] && [ "$(md5of "$ITEMS")" = "$A_ITEMS" ] || { echo "the guarded edit did not apply: $(md5of "$ITEMS")"; echo "$OUT" | tail -3; exit 1; }
echo "after: scholarship_coverage_items_v1 d3dfacf0e70fd33162eab7a57aca72e4 -> $A_ITEMS"
SNAP="select md5(string_agg(x, '|' order by x)) from (select key || value::text x from pipeline.platform_toolset_settings union all select code || coalesce(verify_fn::text, '') || authority from pipeline.ops_remedies
      union all select code || class from pipeline.ops_root_causes union all select lane || generate_fn::text from pipeline.layer4_intervention_handlers union all select code || lane from pipeline.layer4_intervention_classes) s"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 1 ] && [ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed something"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all scholarship hand-off fixtures passed"
