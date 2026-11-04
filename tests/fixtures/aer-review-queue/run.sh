#!/usr/bin/env bash
# CF-247 AER review queue, technical routing and recovery pilots (migration 20261104530000; direction 4 Nov 2026 10:00 §3-§4) on isolated
# fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the AER database of ../aer-throughput (integration-queue stubs, workstream A's contract stand-in, the work-continuity contract, its
#     stubs and live definitions, its production-shaped seed: 605 waiting items, gate classes in live proportion, RMIT 303), then the live
#     v2.15.465 migration (20261104470000) and readiness runs until every item is gated, as production will be;
#   2 the Human-assisted recovery contract from its migration (20261104450000 §1-§5, §8-§11, §13b), stubs.sql and seed.sql (evidence,
#     study levels, owners, a manual lock, active and proposed rows, matrix rows, a correction refused on the same stored copy), each called
#     definition checked against its live md5 (read 4 Nov 2026 11:18 AEDT);
#   3 the migration (one guarded edit to its after md5), then again (nothing changes);
#   4 fixtures.sql: the queue, the packet, the card detail, ownership, routing, interventions, the pilot and the projection.
# Drops the database at the end (AERQ_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERQ_DB:-aer_review_queue_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104530000_cf247_aer_review_queue.sql
FX=tests/fixtures/aer-review-queue
TF=tests/fixtures/aer-throughput
WC=supabase/migrations/20261104170000_cf247_work_continuity.sql
AD=supabase/migrations/20261104320000_cf247_work_continuity_adopt.sql
HAR=supabase/migrations/20261104450000_cf247_human_assisted_recovery.sql
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${AERQ_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the AER database as live after v2.15.465
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
[ "$(q "select count(*) from pipeline.layer4_item_readiness where gate is null")" = 0 ] || { echo "the seed did not gate every item"; exit 1; }

# 2 Human-assisted recovery's contract, the other live shapes and the seed of this change
$P -d $DB -f $FX/stubs.sql >/dev/null
# the live list reader (20261103140000) in place of the stand-in of ../aer-throughput
sed -n '/^create or replace function security.pipeline_list_v1/,/^\$function\$;/p' supabase/migrations/20261103140000_cf247_hidden_failures_country_config.sql | $P -d $DB >/dev/null
{ echo "set check_function_bodies = off;"; awk '/^-- 1 settings \(G2; Settings > Pipeline settings, section Human-assisted/,/^-- 6 the stronger-model step/' $HAR | sed '$d'
  awk '/^-- 8 AER \(lanes aer_source/,/^-- 12 metrics/' $HAR | sed '$d'
  awk '/^-- 13b AER reads held/,/^-- 14 the job/' $HAR | sed '$d'; } | $P -d $DB >/dev/null
$P -d $DB -f $FX/seed.sql >/dev/null
declare -A LIVE=(
  ["security.layer4_intervention_raise_v1(jsonb)"]=8fcabf1137cf126158c260759ac9f9aa
  ["security.aer_e13_recover_v1(boolean)"]=90f80d59db94e29aab3fc520d1c99be6
  ["security.aer_e13_class_v1(jsonb)"]=be023e0e23074cbdd8ed370b3fc7c000
  ["security.har_aer_item_resume_v1(bigint,text,jsonb)"]=78bed1e4b8006bfc498518c88f426fe5
  ["security.layer4_aer_recovery_state_v1(uuid)"]=caf0e61bfcf983fb421638afd3aea795
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live 4 Nov 2026 11:18): ${#LIVE[@]}"

# 3 the migration, then again
EDITED="'security.aer_e13_recover_v1(boolean)'::regprocedure"
NEW="'aer_route_v1', 'aer_review_packet_v1', 'layer4_aer_review_detail_v1', 'layer4_aer_queue_v1', 'admin_layer4_aer_queue', 'layer4_aer_owner_claim_v1', 'har_aer_item_generate_v1', 'aer_e13_pilot_report_v1', 'aer_fair_projection_v1', 'aer_settlement_v1', 'layer4_aer_university_summary_v1', 'aer_progress_counts_v1'"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' and p.oid not in ($EDITED) and p.proname not in ($NEW)"
F0=$(q "$FNS")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 1 ] || { echo "the migration did not apply its guarded edit"; echo "$OUT" | tail -5; exit 1; }
[ "$(md5of "security.aer_e13_recover_v1(boolean)")" = "$(after "security.aer_e13_recover_v1(boolean)")" ] || { echo "aer_e13_recover_v1 after: $(md5of "security.aer_e13_recover_v1(boolean)")"; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not own"; exit 1; }
S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")
H0=$(q "select md5(string_agg(h::text, '|' order by kind, mode)) from pipeline.layer4_inbox_kind_hooks h")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 1 ] || { echo "the second run was not a no-op"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the second run changed settings"; exit 1; }
[ "$(q "select md5(string_agg(h::text, '|' order by kind, mode)) from pipeline.layer4_inbox_kind_hooks h")" = "$H0" ] || { echo "the second run changed the hook register"; exit 1; }
echo "migration: one guarded edit to its after md5; nothing else changed; applied again: no change"

# 4 the assertions
$P -d $DB -f $FX/fixtures.sql 2>&1 | sed -n "s/^.*\(NOTICE\|ERROR\):  /\1 /p"
echo "aer-review-queue fixtures: passed"
