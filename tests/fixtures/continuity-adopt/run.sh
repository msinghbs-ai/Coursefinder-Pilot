#!/usr/bin/env bash
# CF-247 SS-021 part 3: lanes adopt work continuity (migration 20261104190000) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database as ../work-continuity/run.sh does (the integration queue
# stubs and migration 20261102120000, ../ops-controller/stubs-extra.sql, workstream A's migration 20261104010000, the reopen rule
# 20261104100000, ../work-continuity/stubs.sql and live/), then the contract migration 20261104170000 itself (v2.15.443, as live), then
# stubs.sql (the shapes the adopted lanes read) and live/ (the definitions this change edits, as pg_get_functiondef gives them; each checked
# against its live md5, read 3 Nov 2026 22:01-22:10 AEDT, as are the contract functions it calls). Then the migration (only its five guarded
# edits change an existing function, to their after md5s), again (nothing changes), and fixtures.sql (overnight mandate §3 acceptance cases).
# Drops the database at the end (WCA_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${WCA_DB:-continuity_adopt_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104190000_cf247_work_continuity_adopt.sql
WC=tests/fixtures/work-continuity
FX=tests/fixtures/continuity-adopt
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${WCA_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the database as live (v2.15.443)
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -c "alter table pipeline.component_register add constraint component_register_kind_check check (kind = any (array['job','table','view','edge_function','screen','function']))"
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>&1 | show
$P -d $DB -1 -o /dev/null -f tests/fixtures/ops-reopen/ai-guards.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-reopen/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql 2>&1 | show
$P -d $DB -f $WC/stubs.sql
for f in $WC/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104170000_cf247_work_continuity.sql 2>&1 | show
$P -d $DB -f $FX/stubs.sql
for f in $FX/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=c5ce0cb9c431a337789d67bc1878be62
  ["security.work_review_room_v1(text)"]=a7542c70665220ba53a1d6e5bed05a1b
  ["security.aer_schedule_tick_v1(boolean)"]=bc28099db02a26344fae2527b624a8c7
  ["security.fee_reader_tick_v1()"]=0c93b20de02d1714cd6672c259fddb20
  ["security.course_link_search_tick_v1(integer)"]=ffc9fb647925f689678a035cdd64b3e1
  ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e
  ["security.work_fair_pick_v1(text,text,jsonb,integer)"]=c1e63976b1ff6be67f5a4477baa09588
  ["security.work_item_eligible_v1(text,text,text)"]=3d7b00a65efca566a464919c5aa3be6d
  ["security.work_continuity_tick_v1()"]=0cf18ee9422cdbe1dbe8c7d1d67861d6
  ["security.lane_paid_hold_v1(text)"]=99ec517b8b51b0d1305b739e7f1562fb
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live): ${#LIVE[@]}"
EDITED="'security.integration_issue_upsert_v1(jsonb,text)'::regprocedure, 'security.work_review_room_v1(text)'::regprocedure, 'security.aer_schedule_tick_v1(boolean)'::regprocedure,
        'security.fee_reader_tick_v1()'::regprocedure, 'security.course_link_search_tick_v1(integer)'::regprocedure"
NEW="'integration_issue_allowed_v1', 'work_review_ready_v1', 'aer_provider_load_v1', 'aer_fair_courses_v1', 'aer_technical_recovery_v1', 'course_search_paid_cap_v1', 'page_find_continuity_v1'"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'pipeline') and p.prokind = 'f' and p.oid not in ($EDITED) and p.proname not in ($NEW)"
F0=$(q "$FNS")
L4="select md5(coalesce(string_agg(i::text, '|' order by i.id), '')) from pipeline.layer4_review_items i"

# 2 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 5 ] || { echo "the migration did not apply its five guarded edits"; echo "$OUT" | tail -5; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
for s in "security.integration_issue_upsert_v1(jsonb,text)" "security.work_review_room_v1(text)" "security.aer_schedule_tick_v1(boolean)" \
         "security.fee_reader_tick_v1()" "security.course_link_search_tick_v1(integer)"; do
  A=$(after "$s"); [ -n "$A" ] && [ "$(md5of "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of "$s") (header: $A)"; exit 1; }; echo "after: $s $A"
done
echo "applied: only the five guarded edits changed existing functions"
SNAP="select md5(string_agg(x, '|' order by x)) from (select 'r:' || r::text x from pipeline.ops_root_causes r union all select 'm:' || m::text from pipeline.ops_remedies m
  union all select 's:' || s.key || s.value::text from pipeline.platform_toolset_settings s union all select 'j:' || j.jobname || j.schedule || j.command || j.active from cron.job j
  union all select 'c:' || c.jobname from pipeline.automation_catalogue c union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 'p:' || p::text from pipeline.work_recovery_policies p union all select 'k:' || k::text from pipeline.work_review_categories k
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 5 ] || { echo "the second run did not find its edits applied"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed the registers, settings, jobs or functions"; exit 1; }
echo "applied twice: the second run changed nothing"
echo "new function md5s:"; q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'security' and p.proname in ($NEW) order by 1"

$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all continuity adoption fixtures passed"
