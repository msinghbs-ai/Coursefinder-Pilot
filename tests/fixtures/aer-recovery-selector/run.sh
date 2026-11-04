#!/usr/bin/env bash
# CF-247 AER technical recovery selector (migration 20261104550000; mandate 4 Nov 2026 16:32 §4-§6, §10) on isolated fixtures. Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the AER database as live after v2.15.471: the base and seed of ../aer-review-queue (605 waiting items in live proportion, RMIT 303, the
#     work-continuity contract, Human-assisted recovery), the live migrations 20261104470000 and 20261104530000, and from 20261104540000 the
#     lifecycle settings, security.l4_time_v1, security.layer4_reread_repeat_v1 and security.layer4_aer_recovery_detail_v1; every definition
#     this change edits checked against its live md5 (read 4 Nov 2026 17:11 AEDT);
#   2 seed.sql: production shape of lane aer_technical at 16:32 (refusals on the same stored copy with the enrich item that read it, the row-limit
#     refusals of the Diploma of Commerce shape, interventions), then the live lane run as it runs each hour until its holds are parked
#     technical_hold with no next time, as in production (IQ-00232);
#   3 the migration (six guarded changes to their after md5s), then again (nothing changes);
#   4 fixtures.sql: mandate §10 items 1-5 and 7-10 for AER, and the end-to-end recovery of one eligible item.
# Drops the database at the end (AERS_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERS_DB:-aer_recovery_selector_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104550000_cf247_aer_recovery_selector.sql
FX=tests/fixtures/aer-recovery-selector
RQ=tests/fixtures/aer-review-queue
TF=tests/fixtures/aer-throughput
WC=supabase/migrations/20261104170000_cf247_work_continuity.sql
AD=supabase/migrations/20261104320000_cf247_work_continuity_adopt.sql
HAR=supabase/migrations/20261104450000_cf247_human_assisted_recovery.sql
LC=supabase/migrations/20261104540000_cf247_l4_action_lifecycle.sql
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${AERS_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the AER database as live after v2.15.471
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql >/dev/null 2>&1
$P -d $DB -f tests/fixtures/sch-coverage-recovery/stub-ops-contract.sql >/dev/null
$P -d $DB -f $TF/stubs-pre.sql >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 5 functions/' $WC | sed '$d'
  awk '/^-- 5 functions/,/^create or replace function security.work_review_room_v1/' $WC | sed '$d'; } | $P -d $DB >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings/,/^-- 4 functions/' $AD | sed '$d'; } | $P -d $DB >/dev/null
$P -d $DB -f $TF/stubs.sql >/dev/null
for f in $TF/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f" >/dev/null; done
$P -d $DB -f $TF/seed.sql >/dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104470000_cf247_aer_throughput.sql
for i in $(seq 1 25); do q "update pipeline.layer4_item_readiness set classified_at = classified_at - interval '3 hours'; select security.layer4_readiness_tick_v1()" >/dev/null; done
$P -d $DB -f $RQ/stubs.sql >/dev/null
sed -n '/^create or replace function security.pipeline_list_v1/,/^\$function\$;/p' supabase/migrations/20261103140000_cf247_hidden_failures_country_config.sql | $P -d $DB >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings \(G2; Settings > Pipeline settings, section Human-assisted/,/^-- 6 the stronger-model step/' $HAR | sed '$d'
  awk '/^-- 8 AER \(lanes aer_source/,/^-- 12 metrics/' $HAR | sed '$d'
  awk '/^-- 13b AER reads held/,/^-- 14 the job/' $HAR | sed '$d'; } | $P -d $DB >/dev/null
$P -d $DB -f $RQ/seed.sql >/dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104530000_cf247_aer_review_queue.sql
$P -d $DB -f $FX/stubs.sql >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings \(G2; Settings › Pipeline settings, section Layer 4\)/,/^-- 2 indexes/' $LC | sed '$d'
  sed -n '/^create or replace function security.l4_time_v1/,/^revoke all on function security.l4_time_v1/p' $LC
  sed -n '/^create or replace function security.layer4_reread_repeat_v1/,/^revoke all on function security.layer4_reread_repeat_v1/p' $LC
  sed -n '/^create or replace function security.layer4_aer_recovery_detail_v1/,/^revoke all on function security.layer4_aer_recovery_detail_v1/p' $LC; } | $P -d $DB >/dev/null
declare -A LIVE=(
  ["security.aer_technical_recovery_v1()"]=370baa57bfb81fe58df767ad852ca9dd
  ["security.aer_schedule_held_v1(integer)"]=2a0d51faada02e5e36dafb88749b4707
  ["security.aer_e13_recover_v1(boolean)"]=1bd8be8be44d5cd6e25a41a337b43f61
  ["security.har_aer_item_generate_v1(integer)"]=22cb0e540469b5f2ed69a85ecacf5aa2
  ["security.layer4_aer_recovery_detail_v1(text)"]=dbf06336a7ee14fd0a84697d616cb67c
  ["security.layer4_reread_repeat_v1(uuid)"]=80c53ac44d4309279eeb1835d9f7fc21
  ["security.aer_settlement_v1(uuid)"]=49fb7e5071453b7eff4cf343d80b5737
  ["security.work_item_report_v1(text,text,text,text,jsonb)"]=6a15318c0ecd6644b32f1883463c542e
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live 4 Nov 2026 17:11): ${#LIVE[@]}"

# 2 the lane as in production at 16:32: holds re-checked as transient, then parked with no next time
$P -d $DB -f $FX/seed.sql >/dev/null
for i in 1 2 3 4; do q "update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'aer_technical' and stage = 'retry_wait'; select security.aer_technical_recovery_v1()" >/dev/null; done
BEFORE=$(q "select count(*) from pipeline.work_items where lane = 'aer_technical' and failure_class = 'technical_hold' and stage = 'parked' and next_eligible_at is null")
echo "before: technical holds parked with no next time (as IQ-00232): $BEFORE"
[ "$BEFORE" -gt 300 ] || { echo "the seed does not reproduce the production lane"; exit 1; }

# 3 the migration, then again
EDITED="'security.aer_technical_recovery_v1()'::regprocedure, 'security.aer_schedule_held_v1(integer)'::regprocedure, 'security.aer_e13_recover_v1(boolean)'::regprocedure, 'security.har_aer_item_generate_v1(integer)'::regprocedure, 'security.layer4_aer_recovery_detail_v1(text)'::regprocedure, 'security.layer4_reread_repeat_v1(uuid)'::regprocedure"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' and p.oid not in ($EDITED) and p.proname not in ('aer_recovery_rule_v1', 'aer_recovery_report_v1')"
F0=$(q "$FNS")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 5 ] || { echo "the migration did not apply its five guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "security.aer_technical_recovery_v1()" "security.aer_schedule_held_v1(integer)" "security.aer_e13_recover_v1(boolean)" "security.har_aer_item_generate_v1(integer)" \
         "security.layer4_aer_recovery_detail_v1(text)" "security.layer4_reread_repeat_v1(uuid)"; do
  [ "$(md5of "$s")" = "$(after "$s")" ] || { echo "$s after: $(md5of "$s"), expected $(after "$s")"; exit 1; }
done
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not own"; exit 1; }
S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 5 ] || { echo "the second run was not a no-op"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the second run changed settings"; exit 1; }
echo "migration: six guarded changes to their after md5s; nothing else changed; applied again: no change"

# 4 the assertions
$P -d $DB -f $FX/fixtures.sql 2>&1 | sed -n "s/^.*\(NOTICE\|ERROR\):  /\1 /p"
echo "aer-recovery-selector fixtures: passed"
