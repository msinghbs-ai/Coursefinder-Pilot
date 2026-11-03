#!/usr/bin/env bash
# CF-247 P0 autonomous operations, workstream B worker release (coverage-sweep v0.59.5; migration 20261104110000) on isolated fixtures. Needs a
# scratch PostgreSQL (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes); the three live
# functions the worker calls, created from the repository's own migrations (workstream A 20261104010000, workstream D 20261104020000) and checked
# against the live md5s read 3 Nov 2026 18:15 AEDT; the migration unchanged, then again (nothing changed); fixtures.sql. Drops the database at
# the end (OWR_KEEP=1 keeps it). The worker's pure functions are run by the spec (tests/uat/cf-247-s254-worker-ops-requests-contract.spec.mjs).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OWR_DB:-ops_worker_requests_fixtures}
MIG=../../../supabase/migrations/20261104110000_cf247_ops_worker_requests.sql
MA=../../../supabase/migrations/20261104010000_cf247_ops_controller.sql
MD=../../../supabase/migrations/20261104020000_cf247_ops_job_lifecycle.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${OWR_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
{ sed -n '/^create or replace function public.svc_ops_diagnosis_next(p_limit int)/,/^end \$function\$;/p' $MA
  sed -n '/^create or replace function public.svc_ops_diagnosis_record(p_id bigint/,/^end \$function\$;/p' $MA
  sed -n '/^create or replace function public.svc_enrich_ai_stash_v1(p_results jsonb)/,/^end \$\$;/p' $MD; } | $P -d $DB
declare -A LIVE=(
  ["public.svc_ops_diagnosis_next(integer)"]=ade1ae9613bbdfd6f45bd6408e20d880
  ["public.svc_ops_diagnosis_record(bigint,jsonb,numeric)"]=1ac0cc3359af6bca9c0e28e74ed49bcd
  ["public.svc_enrich_ai_stash_v1(jsonb)"]=70a97d7a560571d2de2fecc68ea8ee64
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "read against (loaded = live): ${#LIVE[@]} definitions"
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
