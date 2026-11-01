#!/usr/bin/env bash
# E16 course page check on isolated fixtures (CF-247 E16-1/E16-2, Platform Admin 2 Nov 2026 07:21). Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database, rebuilds the five live definitions from this repository's
# migrations and checks their md5s against the live ones read on 2 Nov 2026, applies the E16 migration unchanged (its own md5 guards and
# post-check run), applies it again (no change), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${E16_DB:-e16_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261102030000_cf247_e16_binding_validation.sql
SIGS="array['security.coverage_page_refused_host_guard()', 'security.exit_awards_apply_v2(uuid)', 'security.enrich_fields_slice_v1(uuid,integer)', 'search.refresh_course_enrichment_core_v1(boolean)', 'search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)']"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${E16_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
node tests/fixtures/e16-binding-validation/before.mjs > /tmp/e16-before.$$.sql
$P -d $DB -c "create schema security; create schema search; create schema pipeline; create schema catalogue"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f /tmp/e16-before.$$.sql
rm -f /tmp/e16-before.$$.sql
$P -d $DB -f tests/fixtures/e16-binding-validation/stubs.sql
md5s() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($SIGS) with ordinality t(f, o)"; }
BEFORE=$(md5s); [ "$BEFORE" = "33351b506da59359656ee196218d7882 8d4e5f7b2fedbe7c3e04ff8b039c40e7 37b855677c98002ed2374f02cd1282f9 ce80f74549625c23317aba5c737afda6 3f0b051fdc0e8c34f757f8c21ff5b7d3" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
$P -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5s); echo "after: $AFTER"
$P -d $DB -1 -At -f $MIG | grep -c 'already applied' | grep -qx 5 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f tests/fixtures/e16-binding-validation/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
