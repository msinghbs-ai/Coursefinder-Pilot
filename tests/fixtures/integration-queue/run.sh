#!/usr/bin/env bash
# CF-247 integration queue on isolated fixtures (continuous validation mandate, Platform Admin 2 Nov 2026 16:58). Needs a scratch PostgreSQL
# (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database with the live table definitions (stubs.sql),
# loads the existing add/evaluate/take/confirm/admin acknowledgement functions from repository migration 20261031091000 and checks their md5s against
# the live ones read on 6 Nov 2026 21:44 UTC (admin acknowledgement at 21:48:56 UTC). Guards: IQ-00112 alert collector recovery mandate, Admin decision ff7ef0a2e63ca68b6333cfc4ab0fabb311b4f559.
# Applies the 20261102120000 migration twice (the second run
# changes nothing), checks that the alert functions are unchanged by it, then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${IQ_DB:-integration_queue_fixtures}
# fixed: this runner creates/drops its database; only explicit local fixture connections and safe identifiers are accepted.
case "${PGHOST:-}" in ''|localhost|127.0.0.1|::1|/*) ;; *) echo "refused: isolated local PostgreSQL required" >&2; exit 1 ;; esac
case "${PGHOSTADDR:-}" in ''|127.0.0.1|::1) ;; *) echo "refused: remote PGHOSTADDR" >&2; exit 1 ;; esac
[ -z "${PGSERVICE:-}" ] || { echo "refused: service-selected database connection" >&2; exit 1; }
[[ "$DB" =~ ^integration_queue_fixtures[a-z0-9_]*$ ]] || { echo "refused: unsafe fixture database name" >&2; exit 1; }
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
for (const n of ["security.platform_alerts_add_v1(", "security.platform_alerts_evaluate_v1(", "security.platform_alerts_take_v1(", "security.platform_alerts_confirm_v1(", "public.admin_platform_alerts("]) {
  const a = s.indexOf("create or replace function " + n)
  if (a < 0) throw new Error(`missing repository alert function: ${n}`)
  const end = s.indexOf("end $function$;", a)
  if (end < a) throw new Error(`unterminated repository alert function: ${n}`)
  console.log(s.slice(a, end + "end $function$;".length))
}' > "$TMP/alerts.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/alerts.sql"
md5s() { $P -d $DB -Atc "select md5(pg_get_functiondef('security.platform_alerts_add_v1(uuid,text,text,text,text,text,text)'::regprocedure)) || ' ' || md5(pg_get_functiondef('security.platform_alerts_evaluate_v1()'::regprocedure)) || ' ' || md5(pg_get_functiondef('security.platform_alerts_take_v1(text)'::regprocedure)) || ' ' || md5(pg_get_functiondef('security.platform_alerts_confirm_v1(bigint[],boolean,text)'::regprocedure)) || ' ' || md5(pg_get_functiondef('public.admin_platform_alerts(text,jsonb)'::regprocedure))"; }
LIVE="6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499 7e9b0cdf3ad4b7f211c6c1d18e9666c1 5122e79787610eafec2ee328bfd90617 d5dd97f1bdb0b718d99b220f6404f1ac"
[ "$(md5s)" = "$LIVE" ] || { echo "alert functions differ from live: $(md5s)"; exit 1; }
echo "alert path (repository = live): $LIVE"
$P -d $DB -1 -o /dev/null -f $MIG 2>&1 | show
$P -d $DB -1 -o /dev/null -f $MIG 2>&1 | { grep -v "already exists, skipping" || true; } | show
[ "$($P -d $DB -Atc "select count(*) from cron.job where jobname = 'integration-validate'")" = 1 ] || { echo "the job was scheduled twice"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.integration_operating_mode")" = 1 ] || { echo "the mode row is not single"; exit 1; }
[ "$(md5s)" = "$LIVE" ] || { echo "the migration changed the alert functions"; exit 1; }
echo "applied twice: one job, one mode row, alert path unchanged"
$P -d $DB -f $FX/fixtures.sql 2>&1 | tee "$TMP/fixtures.log" | show
grep -Fq 'PASS alert collector protocol: 79 original IDs preserved; fixture transport acceptance is not recipient receipt' "$TMP/fixtures.log" || {
  echo "collector scenario completion evidence missing" >&2; exit 1;
}
COLLECTOR_ASSERTIONS=$(grep -c 'NOTICE:  ok: collector:' "$TMP/fixtures.log")
[ "$COLLECTOR_ASSERTIONS" -eq 38 ] || { echo "expected 38 collector assertions, observed $COLLECTOR_ASSERTIONS" >&2; exit 1; }
echo "Collector assertions executed: $COLLECTOR_ASSERTIONS (isolated fixture only; no actual notification delivery)"
