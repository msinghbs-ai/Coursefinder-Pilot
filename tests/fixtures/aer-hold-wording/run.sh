#!/usr/bin/env bash
# CF-247 AER (lane aer2): hold-message wording for the Firecrawl priority floor (migration 20261108150100). Needs a scratch PostgreSQL 16 (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Loads the two live definitions (live/*.sql, md5 checked against the live definitions read 8 Nov 2026), the stand-ins in stubs.sql,
# shows the wording BEFORE, applies the migration (guarded edits), runs fixtures.sql, and applies the migration a second time (already applied).
set -euo pipefail
cd "$(dirname "$0")/../../.."
P="psql -v ON_ERROR_STOP=1 -q -X"
FX=tests/fixtures/aer-hold-wording
MIG=supabase/migrations/20261108150100_cf247_course_search_hold_wording.sql
DB=${AERHW_DB:-g_aer2_hold_wording}
q() { $P -d $DB -Atc "$1"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${AERHW_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT
$P -d $DB -c "create schema security" >/dev/null
$P -d $DB -f $FX/stubs.sql >/dev/null
for f in $FX/live/*.sql; do $P -d $DB -f $f >/dev/null; done
[ "$(q "select md5(pg_get_functiondef('security.link_search_block_v1(uuid,uuid[])'::regprocedure))")" = 95e26930e1a9ae9e2e989febf95bfbf7 ] || { echo "loaded link_search_block_v1 differs from live"; exit 1; }
[ "$(q "select md5(pg_get_functiondef('public.admin_course_search_queue(uuid)'::regprocedure))")" = e970d9a3c2b1d398d0c7387e37b484d9 ] || { echo "loaded admin_course_search_queue differs from live"; exit 1; }
echo "loaded definitions = live (8 Nov 2026)"
# BEFORE: with the floor binding the live text still says tomorrow
$P -d $DB -c "insert into public.fx_settings values ('share_left', 5000), ('room', 0.5), ('priority_floor_course_search', 1500)" >/dev/null
[ "$(q "select security.link_search_block_v1('d1000000-0000-4000-8000-000000000000')->>'fix'")" = "Waits for tomorrow's share" ] || { echo "BEFORE did not show the live wording"; exit 1; }
echo "PASS before: with the floor holding, the live message says 'Waits for tomorrow's share'"
$P -d $DB -c "delete from public.fx_settings" >/dev/null
$P -d $DB -At -f $MIG | grep -c "applied" | grep -q 2 || { echo "migration did not apply both edits"; exit 1; }
[ "$($P -d $DB -At -f $MIG | grep -c 'already applied')" = 2 ] || { echo "second run did not report already applied"; exit 1; }
echo "PASS migration applied twice: already applied"
OUT=$($P -d $DB -f $FX/fixtures.sql 2>&1) || { echo "$OUT" | tail -15; echo "fixtures failed"; exit 1; }
echo "$OUT" | grep -E "PASS"; echo "$OUT" | grep -qE "FAIL|ERROR" && { echo "$OUT" | grep -E "FAIL|ERROR"; exit 1; } || true
# a database whose definition is not the live one is refused
$P -d $DB -c "create or replace function security.link_search_block_v1(p_provider uuid, p_course_ids uuid[] default null) returns jsonb language sql as \$\$ select null::jsonb \$\$" >/dev/null
if $P -d $DB -o /dev/null -f $MIG 2>/dev/null; then echo "FAIL the guard accepted a definition that is not the live one"; exit 1; fi
echo "PASS the md5 guard refuses a definition that is not the live one"
echo "aer-hold-wording: passed"
