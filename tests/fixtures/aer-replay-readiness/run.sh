#!/usr/bin/env bash
# CF-247 AER (lane aer2): the replay has the items it creates assessed for review-readiness in the same run (migration 20261108150000). Needs a scratch
# PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds the aer-technical-holds database (live definitions rebuilt and checked),
# checks the replay is exactly the live definition, shows the gap BEFORE (a replayed item has no readiness assessment), applies the migration, runs
# fixtures.sql, and applies the migration a second time (already applied). Drops the database at the end (AERRR_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
P="psql -v ON_ERROR_STOP=1 -q -X"
FX=tests/fixtures/aer-replay-readiness
MIG=supabase/migrations/20261108150000_cf247_aer_replay_marks_new_items_ready.sql
DB=${AERRR_DB:-g_aer2_replay_readiness}
q() { $P -d $DB -Atc "$1"; }
bash $FX/build-base.sh $DB
[ -n "${AERRR_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
[ "$(q "select md5(pg_get_functiondef('security.aer_replay_v1(boolean)'::regprocedure))")" = eccd0e821b5cffa733af3adc0162c0ea ] || { echo "loaded replay differs from live (8 Nov 2026)"; exit 1; }
echo "loaded security.aer_replay_v1 = live (eccd0e82)"
$P -d $DB -f $FX/setup.sql
$P -d $DB -f $FX/stub-readiness.sql
# BEFORE: the replay creates a new item and nothing assesses it
$P -d $DB -c "update pipeline.platform_toolset_settings set value = to_jsonb(array['d1000000-0000-4000-8000-000000000000=9']) where key = 'entry.max_rows_by_provider'" >/dev/null
$P -d $DB -c "update pipeline.platform_toolset_settings set value = to_jsonb(100) where key = 'aer.replay_daily_max'" >/dev/null
OLD=$(q "select public.fx_seed('c3000000-0000-4000-8000-0000000000b1', 'Diploma of Before')")
q "select (security.aer_replay_v1(false)->>'replaced')" | grep -q '^1$' || { echo "the replay did not recreate the BEFORE read"; exit 1; }
NEW=$(q "select new_item_id from pipeline.aer_read_supersessions where old_item_id = '$OLD'")
[ -n "$NEW" ] || { echo "no new item"; exit 1; }
[ "$(q "select count(*) from public.readiness_calls")" = 0 ] || { echo "the live replay called an assessment"; exit 1; }
echo "PASS before: the replay created item ${NEW:0:8} and nothing assessed it (it keeps no gate until the next readiness run)"
[ "$(q "select count(*) from pipeline.layer4_item_readiness where item_id = '$NEW'")" = 0 ] || { echo "unexpected readiness row"; exit 1; }
# the migration (guard on the live md5), then again
$P -d $DB -At -f $MIG | grep -q "applied" || { echo "migration did not apply"; exit 1; }
[ "$($P -d $DB -At -f $MIG | grep -c 'already applied')" = 1 ] || { echo "second run did not report already applied"; exit 1; }
echo "PASS migration applied twice: already applied"
OUT=$($P -d $DB -f $FX/fixtures.sql 2>&1) || { echo "$OUT" | tail -15; echo "fixtures failed"; exit 1; }
echo "$OUT" | grep -E "PASS"; echo "$OUT" | grep -qE "FAIL|ERROR" && { echo "$OUT" | grep -E "FAIL|ERROR"; exit 1; } || true
# a database whose replay is not the live definition is refused
$P -d $DB -c "create or replace function security.aer_replay_v1(p_preview boolean default false) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$" >/dev/null
if $P -d $DB -o /dev/null -f $MIG 2>/dev/null; then echo "FAIL the guard accepted a replay that is not the live definition"; exit 1; fi
echo "PASS the md5 guard refuses a replay that is not the live definition"
echo "aer-replay-readiness: passed"
