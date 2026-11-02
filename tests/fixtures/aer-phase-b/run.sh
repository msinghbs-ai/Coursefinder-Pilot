#!/usr/bin/env bash
# AER Phase B on isolated fixtures (CF-247 AER mandate 2 Nov 2026 14:45, §16 Phase B; §17 scenarios 14-21, 23, 24). Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database with the live column definitions (stubs.sql),
# rebuilds the four live definitions Phase B edits or relies on from this repository's migrations (before.mjs) and checks their md5s against
# the live ones read on 2 Nov 2026, applies the 20261102110000 migration unchanged (its own md5 guards and post-check run), applies it
# again (no change), loads the data (setup.sql; the real RMIT Nepal rows from rows.mjs), then runs fixtures.sql. Drops the database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERB_DB:-aer_phase_b_fixtures}
MIG=supabase/migrations/20261102110000_cf247_aer_phase_b_assurance.sql
FX=tests/fixtures/aer-phase-b
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f $FX/stubs.sql
node $FX/before.mjs | $P -d $DB -o /dev/null
SIGS="public.admin_aer(text,jsonb) security.ops_scorecard_record_v1() security.platform_alerts_add_v1(uuid,text,text,text,text,text,text) security.platform_alerts_evaluate_v1()"
md5s() { for s in $SIGS; do $P -d $DB -Atc "select md5(pg_get_functiondef('$s'::regprocedure))"; done | paste -sd' '; }
BEFORE=$(md5s)
[ "$BEFORE" = "5e58f5d6126b3b2fe026e376a56c7686 e0031afa54d1afb992fc74805ee0e623 6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
$P -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5s); echo "after: $AFTER"
[ "$AFTER" = "0593747bb6ddd55c785fc445a06eb242 a4b9b21d49bf92c38054858985beecb2 6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499" ] || { echo "after md5s differ"; exit 1; }
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 2 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f $FX/setup.sql
node $FX/rows.mjs | $P -d $DB
$P -d $DB -f $FX/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
