#!/usr/bin/env bash
# CF-247 AER throughput (migration 20261104470000; mandate 4 Nov 2026 08:16 §8) on isolated fixtures. Needs a scratch PostgreSQL 16 (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 ../integration-queue/stubs.sql (schemas, settings, providers, courses, Layer 4 items), workstream A's contract stand-in
#     (../sch-coverage-recovery/stub-ops-contract.sql), the controller's outcome codes (stubs-pre.sql), the work-continuity contract from its
#     migrations (20261104170000 §1-§5 and 20261104320000 §1-§3: settings, policies, work items, review categories, security.work_item_report_v1
#     and work_item_eligible_v1, checked against the live md5s), stubs.sql (the other live shapes; the gate answers from fx.gate), and live/
#     (pg_get_functiondef text of the definitions this change edits or calls, each checked against its live md5 read 4 Nov 2026 08:19 AEDT);
#   2 seed.sql: production-shaped (live 08:26-08:28 AEDT): 564 waiting course reads and 41 matrix runs at 16 universities (RMIT 303), the gate
#     classes in live proportion (169 complete, 162 row limit, 45 shared page, 163 dropped minimums, 25 row level), 376 held reads never gated,
#     83 held reads with one refused correction, repeated keys (duplicate matrix items), stored copies missing or on another URL;
#   3 the readiness and technical recovery as live (before), then the migration (only the three guarded edits change existing functions, to
#     their after md5s), then again (nothing changes);
#   4 fixtures.sql: the assertions (readiness, gate class, E13 recovery off, preview, on, fairness, budgets, refusals, the held step yielding).
# Drops the database at the end (AERT_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERT_DB:-aer_throughput_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104470000_cf247_aer_throughput.sql
FX=tests/fixtures/aer-throughput
WC=supabase/migrations/20261104170000_cf247_work_continuity.sql
AD=supabase/migrations/20261104320000_cf247_work_continuity_adopt.sql
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${AERT_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the database as live
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql >/dev/null 2>&1
$P -d $DB -f tests/fixtures/sch-coverage-recovery/stub-ops-contract.sql >/dev/null
$P -d $DB -f $FX/stubs-pre.sql >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 5 functions/' $WC | sed '$d'
  awk '/^-- 5 functions/,/^create or replace function security.work_review_room_v1/' $WC | sed '$d'; } | $P -d $DB >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 4 functions/' $AD | sed '$d'; } | $P -d $DB >/dev/null
$P -d $DB -f $FX/stubs.sql >/dev/null
for f in $FX/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f" >/dev/null; done
declare -A LIVE=(
  ["security.layer4_readiness_tick_v1()"]=5ed0f7d1ba89c9248403fa4bce76d6fe
  ["security.aer_technical_recovery_v1()"]=3b8ea81abeae4b7d45f43e8cdb27ed26
  ["security.aer_schedule_held_v1(integer)"]=0ea5886c2956255ea2d3f102c64b0166
  ["security.course_entry_correction_v1(uuid,uuid,text)"]=1e2947b30a02a38327e2b67e312339af
  ["security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)"]=2e93bd9b3bc0c2ca7628f3a407b8f57f
  ["security.course_entry_read_enqueue_v1(uuid,uuid,text)"]=df0f2a2826e61b92b168847f1557435b
  ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e
  ["security.work_item_eligible_v1(text,text,text)"]=3d7b00a65efca566a464919c5aa3be6d
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live 4 Nov 2026 08:19): ${#LIVE[@]}"

# 2 production-shaped seed, and the live behaviour before the change
$P -d $DB -f $FX/seed.sql >/dev/null
q "select security.layer4_readiness_tick_v1()" >/dev/null
q "select security.aer_technical_recovery_v1()" >/dev/null
BEFORE=$(q "select count(*) filter (where x.readiness = 'judgement_ready' and fx.cls(f.g) not in ('complete'))
              from pipeline.layer4_item_readiness x join fx.gate f on f.item_id = x.item_id where x.field_code = 'course_entry_first_read'")
echo "before: held course reads reported judgement_ready after a readiness run: $BEFORE"
[ "$BEFORE" -gt 300 ] || { echo "the seed does not reproduce the live starvation"; exit 1; }

# 3 the migration, then again
EDITED="'security.layer4_readiness_tick_v1()'::regprocedure, 'security.aer_technical_recovery_v1()'::regprocedure, 'security.aer_schedule_held_v1(integer)'::regprocedure"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' and p.oid not in ($EDITED) and p.proname not in ('aer_e13_class_v1', 'aer_e13_recover_v1')"
F0=$(q "$FNS")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 3 ] || { echo "the migration did not apply its three guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "security.layer4_readiness_tick_v1()" "security.aer_technical_recovery_v1()" "security.aer_schedule_held_v1(integer)"; do
  [ "$(md5of "$s")" = "$(after "$s")" ] || { echo "$s after: $(md5of "$s"), expected $(after "$s")"; exit 1; }
done
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not own"; exit 1; }
S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 3 ] || { echo "the second run was not a no-op"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the second run changed settings"; exit 1; }
echo "migration: three guarded edits to their after md5s; nothing else changed; applied again: no change"

# 4 the assertions
$P -d $DB -f $FX/fixtures.sql 2>&1 | sed -n "s/^.*\(NOTICE\|ERROR\):  /\1 /p"
echo "aer-throughput fixtures: passed"
