#!/usr/bin/env bash
# CF-247 SS-021 work continuity (migration 20261104170000) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database the way the Layer 4 readiness fixture does: the integration queue stubs and the
# queue (repository migration 20261102120000), ../ops-controller/stubs-extra.sql, workstream A's migration 20261104010000 (the real controller,
# its authority triggers and the shared contract), the reopen rule 20261104100000 (live since v2.15.436), then stubs.sql (the other live shapes)
# and live/ (the definitions this change edits or calls, as pg_get_functiondef gives them, each checked against its live md5 read 3 Nov 2026
# 21:24-21:29 AEDT). Then: the migration without A's contract in a rolled-back database (it must refuse), the migration (only the two guarded
# edits change an existing function, to their after md5s), again (nothing changes), and fixtures.sql (mandate §8 items 1-9).
# Drops the databases at the end (WC_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${WC_DB:-work_continuity_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104170000_cf247_work_continuity.sql
FX=tests/fixtures/work-continuity
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_noa" -c "create database $DB" -c "create database ${DB}_noa" >/dev/null 2>&1
[ -n "${WC_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_noa" >/dev/null 2>&1' EXIT

# 1 without workstream A's contract the migration refuses and leaves nothing behind
$P -d ${DB}_noa -f tests/fixtures/integration-queue/stubs.sql
$P -d ${DB}_noa -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
if OUT=$($P -d ${DB}_noa -1 -At -f $MIG 2>&1); then echo "the migration applied without workstream A's contract"; exit 1; fi
grep -q "workstream A's operations contract (migration 20261104010000) must be applied before this change" <<<"$OUT" || { echo "$OUT" | tail -3; exit 1; }
[ "$($P -d ${DB}_noa -Atc "select count(*) from pg_proc where proname like 'work\_%' escape '\\'") $($P -d ${DB}_noa -Atc "select to_regclass('pipeline.work_items') is null")" = "0 t" ] || { echo "a refused run left objects"; exit 1; }
echo "without A's contract: refused, nothing left"

# 2 the database as live
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
$P -d $DB -c "alter table pipeline.component_register add constraint component_register_kind_check check (kind = any (array['job','table','view','edge_function','screen','function']))"
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>&1 | show
$P -d $DB -1 -o /dev/null -f tests/fixtures/ops-reopen/ai-guards.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-reopen/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql 2>&1 | show
$P -d $DB -f $FX/stubs.sql
for f in $FX/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=c5ce0cb9c431a337789d67bc1878be62
  ["security.ops_remedy_register_v1(text,jsonb)"]=cec6cd2f6518b453fbc8ec3137ce39bd
  ["security.ops_root_cause_register_v1(text,jsonb)"]=591616a6a0bd60d607f65c41c18e2968
  ["security.ops_report_v1(integer)"]=ff46a882b695539ca5cb7879a68ee578
  ["security.course_relink_tick_v1(integer)"]=0cd20104a975c471ed4dd9060569f3b8
  ["security.lane_paid_hold_v1(text)"]=99ec517b8b51b0d1305b739e7f1562fb
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live): ${#LIVE[@]}"
EDITED="'security.course_relink_tick_v1(integer)'::regprocedure, 'security.ops_report_v1(integer)'::regprocedure"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public') and p.prokind = 'f' and p.oid not in ($EDITED)
       and p.proname not like 'work\_%' escape '\\' and p.proname not in ('course_relink_fair_run_v1', 'course_relink_order_v1')"
F0=$(q "$FNS")

# 3 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 2 ] || { echo "the migration did not apply its two guarded edits"; echo "$OUT" | tail -5; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
for s in "security.course_relink_tick_v1(integer)" "security.ops_report_v1(integer)"; do
  A=$(after "$s"); [ -n "$A" ] && [ "$(md5of "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of "$s") (header: $A)"; exit 1; }; echo "after: $s $A"
done
echo "applied: only the two guarded edits changed existing functions"
SNAP="select md5(string_agg(x, '|' order by x)) from (select 'r:' || r::text x from pipeline.ops_root_causes r union all select 'm:' || m::text from pipeline.ops_remedies m
  union all select 's:' || s.key || s.value::text from pipeline.platform_toolset_settings s union all select 'j:' || j.jobname || j.schedule || j.command || j.active from cron.job j
  union all select 'c:' || c.jobname from pipeline.automation_catalogue c union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 'p:' || p::text from pipeline.work_recovery_policies p union all select 'k:' || k::text from pipeline.work_review_categories k
  union all select 't:' || t.tgname from pg_trigger t where not t.tgisinternal union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 2 ] || { echo "the second run did not find its edits applied"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed the registers, settings, jobs, triggers or functions"; exit 1; }
echo "applied twice: the second run changed nothing"
echo "new function md5s:"; q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'security' and (p.proname like 'work\_%' escape '\\' or p.proname in ('course_relink_fair_run_v1', 'course_relink_order_v1')) order by 1"

$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all work continuity fixtures passed"
