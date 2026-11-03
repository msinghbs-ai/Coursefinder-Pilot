#!/usr/bin/env bash
# CF-247 SS-021 course-relink university isolation (migration 20261104240000) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the work-continuity fixture database (its run.sh steps up to the shapes), applies
# the released work-continuity migration 20261104170000, then stubs.sql and live/course_relink_provider_v1.sql (as pg_get_functiondef gives it);
# checks every definition this change edits or relies on against its live md5 (read 3 Nov 2026 22:17-22:20 AEDT); records the live step's
# answers on the seed (fixtures-before.sql); applies the migration (two guarded changes, after md5s), again (already applied); fixtures.sql.
# Drops the database at the end (RL_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${RL_DB:-relink_isolation_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104240000_cf247_relink_isolation.sql
FX=tests/fixtures/relink-isolation
WC=tests/fixtures/work-continuity
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${RL_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

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
  ["security.course_relink_provider_v1(uuid,integer)"]=776844024ca5ee99011ad73dfd36360b
  ["security.course_relink_fair_run_v1(integer)"]=cd5a842d0f87bbe5439934eec66af4ac
  ["security.course_relink_tick_v1(integer)"]=656d308b1b12532a7e3e4335cf0f21ea
  ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or relies on (loaded = live): ${#LIVE[@]}"
$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures-before.sql 2>&1 | show
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public') and p.prokind = 'f' and p.proname not in ('course_relink_provider_v1', 'course_relink_fair_run_v1')"
F0=$(q "$FNS")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': applied$')" = 2 ] || { echo "the migration did not apply its two guarded changes"; echo "$OUT" | tail -5; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not declare"; exit 1; }
for s in "security.course_relink_provider_v1(uuid,integer)" "security.course_relink_fair_run_v1(integer)"; do
  A=$(after "$s"); [ -n "$A" ] && [ "$(md5of "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of "$s") (header: $A)"; exit 1; }; echo "after: $s $A"
done
S1=$(q "select md5(string_agg(s.key || s.value::text, '|' order by s.key)) from pipeline.platform_toolset_settings s")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(echo "$OUT" | grep -c ': already applied$')" = 2 ] && [ "$(q "$FNS")" = "$F0" ] \
  && [ "$(q "select md5(string_agg(s.key || s.value::text, '|' order by s.key)) from pipeline.platform_toolset_settings s")" = "$S1" ] || { echo "the second run changed something"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all relink isolation fixtures passed"
