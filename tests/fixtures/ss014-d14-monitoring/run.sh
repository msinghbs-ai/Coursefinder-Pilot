#!/usr/bin/env bash
# SS-014 D14 and monitoring accuracy on isolated fixtures (Platform Admin 2 Nov 2026 07:41). Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database; rebuilds security.flag_jobs_v1 and security.queue_watch_run_v1 from
# this repository's migrations and the two readers from their live text, and checks all four md5s against the live ones read on 2 Nov 2026;
# checks the health check skeleton's rule lines against the live lines; reproduces each defect on those definitions (fixtures-before.sql);
# applies the 20261102040000 migration (its own md5 guards and after-md5 checks run; the health check's md5s are the skeleton's, see
# hc-edit.mjs), applies it again (no change), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${SS014_DB:-ss014_d14_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d $DB -f stubs.sql
node before.mjs collab | $P -d $DB
node before.mjs | $P -d $DB -o /dev/null
$P -d $DB -f live-readers.sql
$P -d $DB -f health-stub.sql
md5s() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest(array['security.flag_jobs_v1()', 'security.queue_watch_run_v1(boolean)',
  'public.svc_coverage_read_next(integer)', 'public.svc_course_link_search_next(integer)']) with ordinality t(f, o)"; }
BEFORE=$(md5s); [ "$BEFORE" = "a7a7427b4caeea2fa62d017695c3b54e 59c67cf1b496ab43c11c82491962b418 2ac1114dd4a5da99d8ddb742f7d0c1be 00f7add9839d659f7dfc7efe6bd82216" ] || { echo "rebuilt definitions differ from live: $BEFORE"; exit 1; }
echo "before (rebuilt = live): $BEFORE"
LINES=$($P -d $DB -Atc "select string_agg(md5(l), ' ' order by n) from unnest(string_to_array(pg_get_functiondef('security.platform_health_check_v1(boolean)'::regprocedure), E'\n')) with ordinality t(l, n) where l like '%coverage_course_pages%'")
[ "$LINES" = "5b390eac539668d07ac8d539c26519c7 8843993088ad60515f7fbd72c6906b2b e52e47dcc4c92a212688eab5c63fc049" ] || { echo "health check rule lines differ from live: $LINES"; exit 1; }
echo "health check rule lines = live lines 126, 127, 129"
$P -d $DB -f fixtures-before.sql 2>&1 | show
# the health check: its edit applies once to the live lines; the md5 the check query predicts is the md5 the applied edit gives
read HB T1 T2 HA < <(node hc-edit.mjs check 'security.platform_health_check_v1(boolean)' | $P -d $DB -At -F' ')
[ "$T1 $T2" = "1 1" ] || { echo "health check edits apply $T1 and $T2 times"; exit 1; }
VARIANT=$(mktemp); node hc-edit.mjs variant "$HB" "$HA" > "$VARIANT"
$P -d $DB -1 -o /dev/null -f "$VARIANT"
AFTER=$(md5s); echo "after: $AFTER"
[ "$AFTER" = "2421dd1c132bd6460aa12c8dbdce3fa6 5735193b0d93f4764502504617c55687 2ac1114dd4a5da99d8ddb742f7d0c1be 00f7add9839d659f7dfc7efe6bd82216" ] || { echo "after md5s differ"; exit 1; }
[ "$($P -d $DB -Atc "select md5(pg_get_functiondef('security.platform_health_check_v1(boolean)'::regprocedure))")" = "$HA" ] || { echo "health check: applied md5 is not the predicted one"; exit 1; }
echo "health check skeleton: applied md5 = predicted ($HA)"
$P -d $DB -1 -At -f "$VARIANT" | grep -c 'already applied' | grep -qx 3 || { echo "a second run changed something"; exit 1; }
[ "$(md5s)" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
rm -f "$VARIANT"
$P -d $DB -f fixtures.sql 2>&1 | show
