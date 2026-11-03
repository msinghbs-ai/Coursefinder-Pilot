#!/usr/bin/env bash
# CF-247 P0 autonomous operations, workstream B worker release (coverage-sweep v0.59.5; migration 20261104110000) on isolated fixtures. Needs a
# scratch PostgreSQL (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes); the three
# functions the worker calls, created from the repository's own migrations (workstream A 20261104010000, workstream D 20261104020000; their
# live md5s read 3 Nov 2026 18:15 AEDT) and then edited exactly as workstream A2's migration 20261104100000 edits the two diagnosis functions
# (contract ops-diagnose-v1; branch cf247-ops-a2, commit 0a1f82ee, read with git show, or the file on main once A2 lands), each checked against
# its md5; the migration unchanged, then again (nothing changed); fixtures.sql. Drops the database at
# the end (OWR_KEEP=1 keeps it). The worker's pure functions are run by the spec (tests/uat/cf-247-s254-worker-ops-requests-contract.spec.mjs).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OWR_DB:-ops_worker_requests_fixtures}
MIG=../../../supabase/migrations/20261104110000_cf247_ops_worker_requests.sql
MA=../../../supabase/migrations/20261104010000_cf247_ops_controller.sql
MD=../../../supabase/migrations/20261104020000_cf247_ops_job_lifecycle.sql
MA2=../../../supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql
if [ -f "$MA2" ]; then A2SRC=$(cat "$MA2"); else A2SRC=$(git -C ../../.. show 0a1f82eeb37ea8d05ced8bf93a7ed8c20b9511c6:supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql); fi
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${OWR_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
{ sed -n '/^create or replace function public.svc_ops_diagnosis_next(p_limit int)/,/^end \$function\$;/p' $MA
  sed -n '/^create or replace function public.svc_ops_diagnosis_record(p_id bigint/,/^end \$function\$;/p' $MA
  sed -n '/^create or replace function public.svc_enrich_ai_stash_v1(p_results jsonb)/,/^end \$\$;/p' $MD; } | $P -d $DB
[ "$(md5of 'public.svc_ops_diagnosis_next(integer)')" = ade1ae9613bbdfd6f45bd6408e20d880 ] && [ "$(md5of 'public.svc_ops_diagnosis_record(bigint,jsonb,numeric)')" = 1ac0cc3359af6bca9c0e28e74ed49bcd ] \
  || { echo "workstream A's diagnosis functions differ from their v2.15.429 live text"; exit 1; }
# workstream A2's two edits, exactly as its migration makes them (its helper and the two guarded statements)
{ sed -n '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/p' <<<"$A2SRC"
  sed -n "/^select pg_temp.edit_once('public.svc_ops_diagnosis_next(integer)'/,/^]::text\[\]\[\], array\[/p" <<<"$A2SRC"
  sed -n "/^select pg_temp.edit_once('public.svc_ops_diagnosis_record(bigint,jsonb,numeric)'/,/^]::text\[\]\[\], array\[/p" <<<"$A2SRC"; } | $P -d $DB -At | grep -c ': applied' | grep -qx 2 \
  || { echo "workstream A2's two edits did not apply"; exit 1; }
declare -A LIVE=(
  ["public.svc_ops_diagnosis_next(integer)"]=adc209ebf9196c613e3dd82fa76fed61
  ["public.svc_ops_diagnosis_record(bigint,jsonb,numeric)"]=6f1fd77189ea85610a57c6feef16a130
  ["public.svc_enrich_ai_stash_v1(jsonb)"]=70a97d7a560571d2de2fecc68ea8ee64
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "read against (A2 contract ops-diagnose-v1, stash as live): ${#LIVE[@]} definitions"
$P -d $DB -1 -f $MIG 2>&1 | show
SNAP="select md5(string_agg(x, '|' order by x)) from (select jobname || schedule || command x from cron.job union all select toolset_key || key || value::text || coalesce(used_by, '') from pipeline.platform_toolset_settings
      union all select kind || name from pipeline.component_register union all select jobname || description from pipeline.automation_catalogue
      union all select md5(pg_get_functiondef('public.svc_course_link_search_prior_v1(text[])'::regprocedure))) z"
S1=$($P -d $DB -Atc "$SNAP")
$P -d $DB -1 -f $MIG 2>&1 | show
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed jobs, settings, registers or the function"; exit 1; }
echo "second run: nothing changed"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "fixtures: all passed"
