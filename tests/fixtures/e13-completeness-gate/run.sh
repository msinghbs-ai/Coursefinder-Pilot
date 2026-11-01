#!/usr/bin/env bash
# E13 completeness gate on isolated fixtures (CF-247 E13, Platform Admin 2 Nov 2026 05:18). Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database, rebuilds the three live definitions from this repository's
# migrations and checks their md5s against the live ones read on 2 Nov 2026, applies the E13 migration unchanged (its own md5 guards run),
# applies it again (no change), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${E13_DB:-e13_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f tests/fixtures/e13-completeness-gate/stubs.sql
node tests/fixtures/e13-completeness-gate/before.mjs | $P -d $DB -o /dev/null
md5s() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest(array['security.enrich_entry_record_v1(bigint,jsonb)', 'security.course_entry_review_apply_v1(uuid,text,jsonb,text)', 'security.aer_review_read_v1(uuid)']) with ordinality t(f, o)"; }
BEFORE=$(md5s); [ "$BEFORE" = "857102dc182426a841a41e7244f7a088 ce8d0bad9717034342f165b1876fb632 62793b3544874e91a1e2aa26b80e8a14" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql
AFTER=$(md5s); echo "after: $AFTER"
$P -d $DB -1 -At -f supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql | grep -c 'already applied' | grep -qx 3 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f tests/fixtures/e13-completeness-gate/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
