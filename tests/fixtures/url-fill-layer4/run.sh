#!/usr/bin/env bash
# Course link fill respects Layer 4 on isolated fixtures (CF-247 Workstream E, Platform Admin direction 2 Nov 2026 23:24). Needs a scratch
# PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the stubs; security.course_url_fill_v1
# rebuilt from 20261024001000 and checked against the live md5 read on 2 Nov 2026 23:46; the migration unchanged (its md5 guard runs), then
# again (already applied, nothing added twice); then fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${URLFILL_DB:-url_fill_layer4_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261103030000_cf247_url_fill_respects_layer4.sql
SIG="security.course_url_fill_v1()"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${URLFILL_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$SIG'::regprocedure))"; }
$P -d $DB -f tests/fixtures/url-fill-layer4/stubs.sql
node tests/fixtures/url-fill-layer4/before.mjs | $P -d $DB
[ "$(md5of)" = "9ae50ba49eea0a30ecd8da20eef7f97b" ] || { echo "rebuilt definition differs from live: $(md5of)"; exit 1; }
echo "before (rebuilt = live): $(md5of)"
$P -d $DB -1 -o /dev/null -f $MIG
[ "$(md5of)" = "270be3f52e98b58a1153b7c1170fd57e" ] || { echo "after differs: $(md5of)"; exit 1; }
echo "after: $(md5of)"
$P -d $DB -1 -At -f $MIG | grep -c 'already applied' | grep -qx 1 || { echo "a second run changed something"; exit 1; }
[ "$(md5of)" = "270be3f52e98b58a1153b7c1170fd57e" ] || { echo "a second run changed the definition"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.platform_toolset_settings where key in ('course_url.fill_respects_layer4','course_url.retraction_min_fills')")" = 2 ] || { echo "settings added twice"; exit 1; }
[ "$($P -d $DB -Atc "select (length(description) - length(replace(description, 'wait for Layer 4', ''))) / length('wait for Layer 4') from pipeline.automation_catalogue where jobname = 'course-url-fill'")" = 1 ] || { echo "catalogue note added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f tests/fixtures/url-fill-layer4/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
