#!/usr/bin/env bash
# CF-247 human-assisted recovery (migration 20261104450000; Platform Admin design decision 4 Nov 2026 06:30) on isolated fixtures. Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database:
#   1 the live Layer 4 Inbox exactly as ../l4-course-link/run.sh rebuilds it (the stubs, the live-before definitions, the migrations that reached
#     production, then 20261104260000), checked against the live md5s read 4 Nov 2026 06:31 AEDT; the Inbox functions are not edited (they
#     belong to the Inbox performance change): the fixture proves they are unchanged after the migration;
#   2 workstream A's contract (../sch-coverage-recovery/stub-ops-contract.sql), the work-continuity contract from its migration (20261104170000:
#     settings, policies, work items, security.work_item_report_v1 at its live md5), the scholarship coverage tables (20261104390000 §2),
#     stubs.sql, and live/security.ops_report_v1.def (pg_get_functiondef text, live md5 5a1e21cc);
#   3 the migration, then again (nothing changes);
#   4 fixtures.sql: the six lifecycles of §8 end to end, deduplication, the Inbox kind and route, ranks, audit, the report, and the switches.
# Drops the database at the end (HAR_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${HAR_DB:-human_assisted_recovery_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104450000_cf247_human_assisted_recovery.sql
FX=tests/fixtures/human-assisted-recovery
P1=tests/fixtures/p1-provider-descriptions
WC=supabase/migrations/20261104170000_cf247_work_continuity.sql
SC=supabase/migrations/20261104390000_cf247_sch_coverage_recovery.sql
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; [ -n "${HAR_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the live Layer 4 Inbox (as ../l4-course-link/run.sh builds it)
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $P1/stubs.sql >/dev/null
for f in $P1/live-before/*.sql; do PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$f" >/dev/null; done
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -o /dev/null -f supabase/migrations/20261102090000_cf247_p1_provider_descriptions.sql 2>&1 | show
M=supabase/migrations/20261103110000_cf247_course_description_deadline_fields.sql
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f tests/fixtures/course-text/live/security.layer4_review_decide_impl.sql >/dev/null
{ sed -n '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/p' $M; sed -n "/^select pg_temp.edit_once('security.layer4_inbox_items_v1()'/,/]], array\[/p" $M
  sed -n "/^select pg_temp.edit_once('security.layer4_review_decide_impl(uuid,text,text,jsonb)'/,/]], array\[/p" $M; } > "$TMP/items.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -At -f "$TMP/items.sql" >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f tests/fixtures/iq67-coverage-admit/live/security.layer4_course_link_apply_impl.def >/dev/null
sed -n '/^create or replace function security.binding_refusal_route_v1/,/^end \$function\$;/p' supabase/migrations/20261102030000_cf247_e16_binding_validation.sql > "$TMP/brr.sql"
sed -n '/^create or replace function security.layer4_url_key_v1/,/^\$function\$;/p' supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql > "$TMP/key.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/brr.sql" -f "$TMP/key.sql" >/dev/null
$P -d $DB -f tests/fixtures/l4-course-link/stubs.sql >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -o /dev/null -f supabase/migrations/20261104260000_cf247_l4_course_link.sql 2>&1 | show

# 2 the contracts this change builds on, and the stubs
$P -d $DB -f tests/fixtures/sch-coverage-recovery/stub-ops-contract.sql >/dev/null
$P -d $DB -f $FX/stubs.sql >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 4 review categories/' $WC; awk '/^-- 5 functions/,/^create or replace function security.work_review_room_v1/' $WC | sed '$d'; } | $P -d $DB >/dev/null
awk '/^-- 2\. tables/,/^-- 3\. D1/' $SC | $P -d $DB >/dev/null
$P -d $DB -c "set check_function_bodies = off" -f $FX/live/security.ops_report_v1.def >/dev/null
declare -A LIVE=( ["security.layer4_inbox_kinds_v1()"]=e79ce1815952b4a0e59108981bf62c36 ["security.layer4_inbox_items_v1()"]=4fc05d14f4ba49335ff90496a20f582d
  ["public.admin_layer4_inbox(text,jsonb)"]=1fb975482d29c7c9f1ecdf3cdb011a10 ["security.ops_report_v1(integer)"]=5a1e21cc42f8f54cbf0d9f3f7fe81c71
  ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e ["security.layer4_review_decide_impl(uuid,text,text,jsonb)"]=55353f1903c97b268255c8c1e4f5ca6f )
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 4 Nov 2026 06:31): ${#LIVE[@]} definitions"

# 3 the migration, then again
EDITED=("security.ops_report_v1(integer)")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 1 ] || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
for s in "${EDITED[@]}"; do A=$(after "$s"); [ -n "$A" ] && [ "$(md5of "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of "$s") (header: $A)"; exit 1; }
  echo "after: $s ${LIVE[$s]} -> $A"; done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text x from pipeline.platform_toolset_settings s
  union all select 'c:' || c::text from pipeline.layer4_intervention_classes c union all select 'h:' || h::text from pipeline.layer4_intervention_handlers h
  union all select 'j:' || j.jobname || j.schedule || j.command from cron.job j union all select 'a:' || a.jobname from pipeline.automation_catalogue a
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 'r:' || r.code from pipeline.ops_remedies r
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 1 ] || { echo "the second run did not find its edits applied"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed settings, classes, handlers, jobs, registers or functions"; exit 1; }
for s in "security.layer4_inbox_kinds_v1()" "security.layer4_inbox_items_v1()" "public.admin_layer4_inbox(text,jsonb)"; do
  [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "the migration changed $s, which it does not own"; exit 1; }; done
echo "applied twice: the second run changed nothing; the Inbox functions are untouched"
$P -d $DB -f $FX/seed.sql >/dev/null
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all human-assisted recovery fixtures passed"
