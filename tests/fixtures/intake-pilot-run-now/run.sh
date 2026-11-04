#!/usr/bin/env bash
# Run now and the 20-course Course Intake Dates pilot on isolated fixtures (CF-247, Platform Admin 4 Nov 2026 20:05 §1-§5; 20:02 §1-§3).
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it.
#   1 the intake-dates fixture database, kept (tests/fixtures/intake-dates/run.sh): the live projection, admission write, guards, plan v2 and the
#     job function, each md5-checked against live there; its cases pass first;
#   2 the live security.intake_dates_apply_v1(integer) checked (d15c04c6..., read live 4 Nov 2026 20:07) before this change;
#   3 the task tables, roles and consumer read-back (stubs.sql); the migration applied, then applied again unchanged;
#   4 the cases (fixtures.sql), a run refused while another holds the job's lock, then the run and read-back (fixtures2.sql).
#   3b the cohort scope migration (Platform Admin 4 Nov 2026 20:53) from the cohort function as live after v2.15.476, twice.
# Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
FX=tests/fixtures/intake-pilot-run-now
DB=${RUN_NOW_DB:-intake_run_now_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104610000_cf247_intake_pilot_run_now.sql
TMP=$(mktemp -d)
[ -n "${RUN_NOW_KEEP:-}" ] && trap 'rm -rf "$TMP"' EXIT || trap 'rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
INTAKE_DB=$DB INTAKE_KEEP=1 bash tests/fixtures/intake-dates/run.sh > "$TMP/base.log" 2>&1 || { cat "$TMP/base.log"; exit 1; }
grep -c '^NOTICE PASS' "$TMP/base.log" | xargs -I{} echo "intake-dates fixture: {} PASS"
md5of() { $P -d $DB -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($1) with ordinality t(f, o)"; }
LIVE="array['security.intake_dates_apply_v1(integer)', 'security.intake_dates_plan_v2(uuid[],integer)']"
[ "$(md5of "$LIVE")" = "d15c04c680dc0128ca5da33556426c43 8e3e11c3b78e4e52ea0709e48a666ff6" ] || { echo "job and plan differ from live: $(md5of "$LIVE")"; exit 1; }
echo "before (rebuilt = live 4 Nov 2026 20:07): $(md5of "$LIVE")"
$P -d $DB -f $FX/stubs.sql
$P -d $DB -1 -o /dev/null -f $MIG
SIGS="array['security.intake_dates_apply_v1(integer)', 'security.intake_dates_apply_v1(integer,uuid[])', 'security.intake_dates_plan_v2(uuid[],integer)']"
AFTER=$(md5of "$SIGS"); echo "after: $AFTER"
$P -d $DB -1 -o /dev/null -f $MIG
[ "$(md5of "$SIGS")" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.platform_toolset_settings where key like 'run_now.%'")" = 3 ] || { echo "settings added twice"; exit 1; }
echo "second run: unchanged"
# the cohort scope (Platform Admin 4 Nov 2026 20:53): from the cohort function as live after v2.15.476, the scope migration twice
MIG2=supabase/migrations/20261104630000_cf247_intake_pilot_top_au_universities.sql
CC="array['security.run_now_cohort_create_v1(text,uuid,text,text)']"
[ "$(md5of "$CC")" = "0fd43a771a427530995c20f88eb1af1c" ] || { echo "cohort function differs from live: $(md5of "$CC")"; exit 1; }
$P -d $DB -c "alter table catalogue.providers add column if not exists provider_type_id uuid" \
  -c "create table if not exists ref.provider_types(id uuid primary key default gen_random_uuid(), code text unique, name text, description text, status text default 'active')"
$P -d $DB -1 -o /dev/null -f $MIG2
CCA=$(md5of "$CC"); echo "cohort scope after: $CCA"
$P -d $DB -1 -o /dev/null -f $MIG2
# hotfix 20261104640000: production's outcome-code foreign key on admin_jobs, reproduced, then the fix applied twice
$P -d $DB -q -c "create table if not exists pipeline.ops_outcome_codes(code text primary key); insert into pipeline.ops_outcome_codes values ('succeeded_with_result'),('succeeded_no_movement'),('not_needed'),('deferred_dependency'),('blocked_policy'),('blocked_evidence'),('failed_retryable'),('failed_remediation') on conflict do nothing; alter table pipeline.admin_jobs drop constraint if exists admin_jobs_outcome_fkey; update pipeline.admin_jobs set outcome = null where outcome is not null and outcome not in (select code from pipeline.ops_outcome_codes); alter table pipeline.admin_jobs add constraint admin_jobs_outcome_fkey foreign key (outcome) references pipeline.ops_outcome_codes(code);" >/dev/null
MIG3=supabase/migrations/20261104640000_cf247_run_now_outcome_code.sql
$P -d $DB -1 -o /dev/null -f $MIG3
$P -d $DB -1 -o /dev/null -f $MIG3
[ "$(md5of "$CC")" = "$CCA" ] || { echo "a second run of the scope migration changed the definition"; exit 1; }
# the intake-dates fixture's helpers in front of each case file
sed -n '/^create function pg_temp.ok/,/^create function pg_temp.lists/p' tests/fixtures/intake-dates/fixtures.sql | sed '/^create function pg_temp.lists/,$d' > "$TMP/helpers.sql"
cat "$TMP/helpers.sql" $FX/fixtures.sql > "$TMP/f1.sql"; cat "$TMP/helpers.sql" $FX/fixtures2.sql > "$TMP/f2.sql"
$P -d $DB -f "$TMP/f1.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
# one run at a time: while another session holds the job's own lock, Run now is refused and names the run holding it
$P -d $DB -c "begin" -c "select pg_advisory_xact_lock(hashtext('cf247 intake dates apply'))" -c "select pg_sleep(4)" -c "commit" >/dev/null &
sleep 1
R=$($P -d $DB -Atc "select security.job_run_now_v1('intake-dates-apply', 'concurrent', jsonb_build_object('cohort_id', (select v from public.fixture_run_now where k = 'cohort')), md5('admin')::uuid)")
wait
echo "$R" | grep -q '"refused": "a run of this job is in progress"' && echo "$R" | grep -q '"in_flight": {"pid"' || { echo "concurrent run not refused: $R"; exit 1; }
echo "NOTICE PASS one run at a time: refused while the job's lock is held, the holding run returned"
$P -d $DB -c "delete from pipeline.admin_jobs where reason = 'concurrent'" >/dev/null  # fixture only: keep the case counts of part 2
$P -d $DB -f "$TMP/f2.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
