#!/usr/bin/env bash
# CF-247 Workstream F: hidden failures and country settings on isolated fixtures (Platform Admin direction 3 Nov 2026 09:32 §5, §7). Needs a
# scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the pipeline-yield fixture
# database (integration-queue stubs, the alert path from the repository, migrations 20261102120000 and 20261103040000), stubs.sql, the live
# definitions in live/ (read with pg_get_functiondef on 3 Nov 2026 10:13-10:30 AEDT), each checked against its live md5; the lock defect
# reproduced on the live definitions (a worker's foreign-key check waits for the admin-jobs runner); fixtures-before.sql (the other defects,
# and today's behaviour kept for comparison); the 20261103140000 migration unchanged (its md5 guards and after-md5 checks run), then again
# (already applied, nothing added twice); the lock test again (the worker is no longer blocked; runners still skip each other's task); then
# fixtures.sql. Drops the throwaway database at the end (HIDDENFAIL_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${HIDDENFAIL_DB:-hidden_failures_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
IQ=tests/fixtures/integration-queue
YF=tests/fixtures/pipeline-yield
FX=tests/fixtures/hidden-failures
MIG=supabase/migrations/20261103140000_cf247_hidden_failures_country_config.sql
TMP=$(mktemp -d)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap 'rm -rf "$TMP"; [ -n "${HIDDENFAIL_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }

# the pipeline-yield fixture database, as tests/fixtures/pipeline-yield/run.sh builds it
$P -d $DB -f $IQ/stubs.sql
node -e '
const s = require("fs").readFileSync("supabase/migrations/20261031091000_cf247_ss014_operational_automation.sql", "utf8")
for (const n of ["security.platform_alerts_add_v1(", "security.platform_alerts_evaluate_v1("]) {
  const a = s.indexOf("create or replace function " + n), b = s.indexOf("end $function$;", a) + "end $function$;".length
  console.log(s.slice(a, b))
}' > "$TMP/alerts.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/alerts.sql"
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f $YF/stubs.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261103040000_cf247_pipeline_yield_checks.sql 2>&1 | show
$P -d $DB -f $FX/stubs.sql

# live definitions and their live md5 (3 Nov 2026): the ten this change edits and the three it calls
declare -A LIVE=(
  ["security.admin_jobs_tick_v1(integer)"]=6a482636d1f67ca41add017f8c241b01
  ["security.admin_job_slice_v1(uuid,integer)"]=6d9ba8d97a068061566d2790eec103fc
  ["security.admin_job_watch_v1(uuid)"]=042c960f0f7d6fdb4d83a725e644a4a8
  ["security.enrich_fields_slice_v1(uuid,integer)"]=b677308fffdc23e5fbd2ad54d1b97d30
  ["public.svc_nz_cop_next(integer)"]=255c75c911ce848c7787a64194fa0722
  ["security.enrich_focus_v1(uuid)"]=803098094b9d8404ad1b9531c7e597bd
  ["security.enrich_focus_refresh_v1()"]=0588c931c545df5ef8a1b58730c9d3b5
  ["security.scholarship_discovery_refill_v1(integer)"]=5a72808f07e2f5219518ed3fc20fcdb7
  ["security.integration_yield_checks_v1()"]=4c25bf79db544f8605c9c25b45fc8318
  ["security.pipeline_yield_v1(integer)"]=87ab2f7e7a6acf18a18c7191c9eb2b98
  ["security.course_link_search_cap_reason_v1()"]=5b46ddd0283dce924a2f6cdeb90c6549
  ["public.svc_cricos_peo_next(integer)"]=9b7675ad956065b6ba793b5e744114ad
  ["security.integration_issue_upsert_v1(jsonb,text)"]=f292f65689a35e213a3d12a539c11b1d
)
for f in $FX/live/*.sql; do PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"

# the lock test: a task held by the runner (or a slice) in an open transaction while a worker records an item of that task
# (two updates of the item in one transaction: the second checks the foreign key to the task, FOR KEY SHARE)
locktest() {  # $1 kind, $2 args, $3 the holder's statement (JOB = the task id); prints free or blocked
  local jid
  jid=$($P -d $DB -Atc "update pipeline.admin_jobs set state = 'done' where state in ('queued', 'running'); insert into pipeline.admin_jobs(kind, lane, state, args) values ('$1', 'lt', 'queued', '$2'::jsonb) returning id" | tail -1)
  $P -d $DB -Atc "insert into pipeline.field_enrich_items(job_id, field, state, attempts) values ('$jid', 'english', 'ai', 0)" >/dev/null
  ( $P -d $DB -c "begin" -c "${3//JOB/$jid}" -c "select pg_sleep(3)" -c "commit" >/dev/null ) &
  local h=$!
  sleep 1
  if $P -d $DB -c "set lock_timeout = '1s'" -c "begin" -c "update pipeline.field_enrich_items set cost_usd = 0.01, leased_until = null, updated_at = now() where job_id = '$jid'" \
       -c "update pipeline.field_enrich_items set state = 'skipped', reason = 'the page does not state it' where job_id = '$jid'" -c "commit" >/dev/null 2>&1; then echo free; else echo blocked; fi
  wait $h
}
lockall() {
  echo "$(locktest qualify_adapters '{"providers": []}' "select security.admin_jobs_tick_v1(10)") $(locktest enrich_fields '{}' "select security.enrich_fields_slice_v1('JOB', 1)") $(locktest firecrawl_run '{}' "select security.admin_job_watch_v1('JOB')")"
}
[ "$(lockall)" = "blocked blocked blocked" ] || { echo "the lock defect was not reproduced on the live definitions"; exit 1; }
echo "before: a worker's record waits for the runner, the enrich slice and the watch (IQ-00053 reproduced)"

$P -d $DB -f $FX/fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG 2>&1 | grep -c ': applied' | grep -qx 10 || { echo "the migration did not apply all ten guarded edits"; $P -d $DB -1 -At -f $MIG; exit 1; }
declare -A AFTER
for s in "${!LIVE[@]}"; do AFTER[$s]=$(md5of "$s"); done
echo "after:"; for s in "${!LIVE[@]}"; do echo "  $s ${LIVE[$s]} -> ${AFTER[$s]}"; done
SNAP="select (select count(*) from pipeline.platform_toolset_settings), (select count(*) from cron.job), (select count(*) from pipeline.component_register), (select count(*) from pipeline.automation_catalogue), (select string_agg(jobname || '=' || command || '=' || active, ';' order by jobname) from cron.job)"
S1=$($P -d $DB -Atc "$SNAP")
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 10 || { echo "a second run changed something"; exit 1; }
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "a second run changed $s"; exit 1; }; done
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run added settings, jobs, catalogue or register rows"; exit 1; }
echo "second run: already applied, unchanged"

[ "$(lockall)" = "free free free" ] || { echo "a worker's record still waits for the runner"; exit 1; }
echo "ok after: the worker records while the runner, the enrich slice and the watch hold the task"
# two runners still skip each other's task (NO KEY UPDATE conflicts with itself)
JID=$($P -d $DB -Atc "update pipeline.admin_jobs set state = 'done' where state in ('queued', 'running'); insert into pipeline.admin_jobs(kind, lane, state, args) values ('qualify_adapters', 'lt', 'running', '{\"providers\": [\"00000000-0000-0000-0000-0000000000a1\"]}'::jsonb) returning id" | tail -1)
( $P -d $DB -c "begin" -c "select id from pipeline.admin_jobs where id = '$JID' for no key update" -c "select pg_sleep(3)" -c "commit" >/dev/null ) &
H=$!; sleep 1
OUT=$($P -d $DB -Atc "select security.admin_jobs_tick_v1(10)")
wait $H
[ "$OUT" = "[]" ] || { echo "a second runner took a task another runner holds: $OUT"; exit 1; }
echo "ok after: a second runner skips the task the first holds (skip locked unchanged)"

$P -d $DB -f $FX/fixtures.sql 2>&1 | show
