#!/usr/bin/env bash
# CF-247 pipeline yield checks on isolated fixtures (Platform Admin direction 2 Nov 2026 23:24 §3). Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the integration-queue fixture database (its stubs, the
# alert path loaded from the repository and checked against live, migration 20261102120000), the yield stubs, then the 20261103040000
# migration twice (the second run changes nothing), then fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${YIELD_DB:-pipeline_yield_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
IQ=tests/fixtures/integration-queue
FX=tests/fixtures/pipeline-yield
MIG=supabase/migrations/20261103040000_cf247_pipeline_yield_checks.sql
TMP=$(mktemp -d)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap 'rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d $DB -f $IQ/stubs.sql
node -e '
const s = require("fs").readFileSync("supabase/migrations/20261031091000_cf247_ss014_operational_automation.sql", "utf8")
for (const n of ["security.platform_alerts_add_v1(", "security.platform_alerts_evaluate_v1("]) {
  const a = s.indexOf("create or replace function " + n), b = s.indexOf("end $function$;", a) + "end $function$;".length
  console.log(s.slice(a, b))
}' > "$TMP/alerts.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/alerts.sql"
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f $FX/stubs.sql
IQMD5=$($P -d $DB -Atc "select md5(pg_get_functiondef('security.integration_validate_v1()'::regprocedure))")
$P -d $DB -1 -o /dev/null -f $MIG 2>&1 | show
$P -d $DB -1 -o /dev/null -f $MIG 2>&1 | { grep -v "already exists, skipping" || true; } | show
[ "$($P -d $DB -Atc "select md5(pg_get_functiondef('security.integration_validate_v1()'::regprocedure))")" = "$IQMD5" ] || { echo "the migration changed security.integration_validate_v1"; exit 1; }
[ -n "${YIELD_KEEP:-}" ] && trap - EXIT
[ "$($P -d $DB -Atc "select count(*) from cron.job where jobname = 'integration-validate'")" = 1 ] || { echo "the job is not single"; exit 1; }
echo "applied twice: integration_validate_v1 unchanged ($IQMD5), one job"
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
