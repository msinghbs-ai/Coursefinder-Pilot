#!/usr/bin/env bash
# CF-247 integration queue on isolated fixtures (continuous validation mandate, Platform Admin 2 Nov 2026 16:58). Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database with the live table definitions (stubs.sql),
# loads the existing alert functions (security.platform_alerts_add_v1, security.platform_alerts_evaluate_v1) from repository migration
# 20261031091000 and checks their md5s against the live ones read on 2 Nov 2026, applies the 20261102120000 migration twice (the second run
# changes nothing), checks that the alert functions are unchanged by it, then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${IQ_DB:-integration_queue_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261102120000_cf247_integration_queue.sql
FX=tests/fixtures/integration-queue
TMP=$(mktemp -d)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap 'rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d $DB -f $FX/stubs.sql
node -e '
const s = require("fs").readFileSync("supabase/migrations/20261031091000_cf247_ss014_operational_automation.sql", "utf8")
for (const n of ["security.platform_alerts_add_v1(", "security.platform_alerts_evaluate_v1("]) {
  const a = s.indexOf("create or replace function " + n), b = s.indexOf("end $function$;", a) + "end $function$;".length
  console.log(s.slice(a, b))
}' > "$TMP/alerts.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/alerts.sql"
md5s() { $P -d $DB -Atc "select md5(pg_get_functiondef('security.platform_alerts_add_v1(uuid,text,text,text,text,text,text)'::regprocedure)) || ' ' || md5(pg_get_functiondef('security.platform_alerts_evaluate_v1()'::regprocedure))"; }
LIVE="6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499"
[ "$(md5s)" = "$LIVE" ] || { echo "alert functions differ from live: $(md5s)"; exit 1; }
echo "alert path (repository = live): $LIVE"
$P -d $DB -1 -o /dev/null -f $MIG 2>&1 | show
$P -d $DB -1 -o /dev/null -f $MIG 2>&1 | { grep -v "already exists, skipping" || true; } | show
[ "$($P -d $DB -Atc "select count(*) from cron.job where jobname = 'integration-validate'")" = 1 ] || { echo "the job was scheduled twice"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.integration_operating_mode")" = 1 ] || { echo "the mode row is not single"; exit 1; }
[ "$(md5s)" = "$LIVE" ] || { echo "the migration changed the alert functions"; exit 1; }
echo "applied twice: one job, one mode row, alert path unchanged"
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
