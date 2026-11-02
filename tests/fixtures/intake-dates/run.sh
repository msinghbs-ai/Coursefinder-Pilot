#!/usr/bin/env bash
# Intake year, start date and deadline on isolated fixtures (CF-247, Platform Admin 2 Nov 2026 11:10 §2 and 11:18). Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the E16 fixture database (its stubs, its five rebuilt definitions and the E16 migration), so the course page check and the search
#     projection (search.refresh_course_enrichment_core_v1 / _scoped_v1) are the live definitions; their md5s are checked against live;
#   2 security.coverage_apply_course_v1 and the two guards on catalogue.course_intakes rebuilt from this repository's migrations, md5s checked
#     against the live ones read on 2 Nov 2026;
#   3 the intake-dates migration unchanged (its md5 guard and post-check run), then again (no change);
#   4 fixtures.sql: the cases, and the chain stored reading -> intake row -> search projection -> consumer API intake objects.
# Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${INTAKE_DB:-intake_dates_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
E16=tests/fixtures/e16-binding-validation
E16MIG=supabase/migrations/20261102030000_cf247_e16_binding_validation.sql
MIG=supabase/migrations/20261102080000_cf247_intake_dates_persist.sql
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${INTAKE_KEEP:-}" ] || trap 'rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($1) with ordinality t(f, o)"; }
# 1 the E16 fixture database
node $E16/before.mjs > "$TMP/e16.sql"
$P -d $DB -c "create schema security; create schema search; create schema pipeline; create schema catalogue"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f "$TMP/e16.sql"
$P -d $DB -f $E16/stubs.sql
$P -d $DB -1 -o /dev/null -f $E16MIG
PROJ="array['search.refresh_course_enrichment_core_v1(boolean)', 'search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)', 'security.course_page_check_v1(uuid,text,text,text)']"
[ "$(md5of "$PROJ" | cut -d' ' -f1-2)" = "04fa25d82c373de08767d5573d4caabc 5b45bbf1e39d9098d5f23de729418b2d" ] || { echo "projection differs from live: $(md5of "$PROJ")"; exit 1; }
echo "projection (rebuilt = live): $(md5of "$PROJ" | cut -d' ' -f1-2)"
# 2 the admission write and the intake guards, as live
$P -d $DB -c "drop function security.coverage_apply_course_v1(uuid, uuid, uuid, text, text, jsonb)"
$P -d $DB -f tests/fixtures/intake-dates/stubs.sql
node tests/fixtures/intake-dates/before.mjs > "$TMP/before.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f "$TMP/before.sql"
SIGS="array['security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', 'security.course_intake_same_month_guard()', 'security.manual_fact_guard()']"
BEFORE=$(md5of "$SIGS"); [ "$BEFORE" = "8674165fa03b97ca15c3bc82923b1288 44e23d4abc1d36cdbb85407287a87e5f d0490f3707199988e87b5f37ca5e7342" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
# 3 the migration, twice
$P -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5of "$SIGS"); echo "after: $AFTER"
$P -d $DB -1 -At -f $MIG | grep -c 'already applied' | grep -qx 1 || { echo "a second run changed something"; exit 1; }
[ "$(md5of "$SIGS")" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from cron.job where jobname = 'intake-dates-apply'")" = 1 ] || { echo "the job was scheduled twice"; exit 1; }
echo "second run: already applied, unchanged"
[ "$(md5of "array['api.website_v2_label_month(text)']")" = "4263b5ad2369e87c99674f9159d672f8" ] || { echo "the API month helper differs from live"; exit 1; }
# 4 the cases
CAL=$(node tests/fixtures/intake-dates/parse.mjs)
$P -d $DB -v cal="$CAL" -f tests/fixtures/intake-dates/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
