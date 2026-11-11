#!/usr/bin/env bash
# Guards: F-OPS task runner (CF-247; Platform Admin 11 Nov 2026 13:45): migration 20261111230000 edits only security.admin_jobs_tick_v1 (checked by the md5 of its body, refused with nothing applied when the live body differs) and adds the setting
# jobs.transient_retry_max. A task whose slice meets a passing database error (deadlock 40P01, serialization failure 40001, lock not available 55P03) stays running, its slice rolled back, and is taken again next run, up to the setting;
# past it, or for any other error, the task fails as before; 0 keeps the old behaviour; cancel and pause are unchanged; the forward recovery returns the previous body byte for byte. The failure is reproduced on the live text first.
# Needs a scratch PostgreSQL 16 or 17 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. JTR_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order whatever the runner's locale
DB=${JTR_DB:-g_jobs_transient_retry}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
F=tests/fixtures/jobs-transient-retry
M=supabase/migrations/20261111230000_cf247_jobs_transient_retry.sql
R=supabase/held/jobs_transient_retry_forward_recovery.sql
FN='security.admin_jobs_tick_v1(integer)'; BEFORE=f95f8c26d9bbd4fa07a74bcd0797e198; AFTER=d25e4bad56b632eae40d15f69ddfc4f4
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
q() { psql -X -q -d "$DB" -Atc "$1"; }
md5of() { q "select md5(prosrc) from pg_proc where oid = '$FN'::regprocedure"; }
expect() { [ "$2" = "$3" ] || { echo "$1: got '$2', expected '$3'"; exit 1; }; }
W=$(mktemp -d)
cleanup() { rm -rf "$W"; [ -n "${JTR_KEEP:-}" ] || { dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1; }; }
trap cleanup EXIT
dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1
createdb $DB
$P -f $F/stubs.sql; $P -f $F/live/security.admin_jobs_tick_v1.sql
expect "loaded runner" "$(md5of)" $BEFORE
echo "loaded: $FN = live (body md5 $BEFORE), read 11 Nov 2026; the slice and the close are stand-ins"
DEF0=$(q "select pg_get_functiondef('$FN'::regprocedure)")
# a task with planned slice outcomes ($2: space-separated); prints its id
task() { local id; id=$(q "insert into pipeline.admin_jobs(id, lane, state) values (gen_random_uuid(), '$1', 'queued') returning id"); q "create sequence security.fx_seq_${id//-/}" >/dev/null; local s=0; for o in $2; do s=$((s+1)); q "insert into security.fx_plan values ('$id', $s, '$o')" >/dev/null; done; echo "$id"; }
tick() { q "select security.admin_jobs_tick_v1(10)" >/dev/null; }
st() { q "select state || '|' || coalesce(error, '') from pipeline.admin_jobs where id = '$1'"; }
retries() { q "select count(*) from pipeline.admin_job_events where job_id = '$1' and note like 'transient database error%'"; }

# BEFORE: on the live text a passing deadlock fails the task for good
B=$(task lane-b "40P01 done"); tick
expect "before: deadlock" "$(st $B)" "failed|fixture error 40P01"
tick; expect "before: never taken again" "$(st $B)" "failed|fixture error 40P01"
echo "before: on the live text a slice deadlock (40P01) ends the task failed and the runner never takes it again (the regression fails on the old body)"
q "truncate pipeline.admin_jobs, pipeline.admin_job_events, security.fx_plan, security.fx_work, security.fx_closed" >/dev/null

snap() { q "select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','pipeline') order by 1" > "$1.fn"
         q "select toolset_key || '.' || key || '=' || value::text from pipeline.platform_toolset_settings order by 1" > "$1.set"
         q "select count(*) from pipeline.admin_control_events" > "$1.ev"; }
# a live body that differs: refused, nothing applied (the setting insert included: one transaction)
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$FN'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "the migration applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change replaces" <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
expect "refused: no setting" "$(psql -X -d ${DB}_x -Atc "select count(*) from pipeline.platform_toolset_settings where key = 'jobs.transient_retry_max'")" 0
dropdb ${DB}_x
echo "refused: a hand-changed live runner is refused (transaction rolled back: body untouched, no setting added)"

snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
expect "after md5" "$(md5of)" $AFTER
grep -qF -- "--   $FN   $BEFORE -> $AFTER" $M || { echo "the header does not record the md5s"; exit 1; }
snap "$W/1"
[ "$(comm -3 "$W/0.fn" "$W/1.fn" | sed 's/^\t//; s/ [0-9a-f]*$//' | sort -u)" = "$FN" ] || { echo "functions other than the runner changed"; exit 1; }
expect "one setting added" "$(comm -13 "$W/0.set" "$W/1.set")" "pipeline.jobs.transient_retry_max=5"
expect "settings removed" "$(comm -23 "$W/0.set" "$W/1.set")" ""
expect "one audit row" "$(( $(cat $W/1.ev) - $(cat $W/0.ev) ))" 1
expect "setting metadata" "$(q "select concat_ws('|', unit, min_value, max_value, used_by is not null, label is not null) from pipeline.platform_toolset_settings where key = 'jobs.transient_retry_max'")" "times|0|50|t|t"
OUT=$($P -1 -At -f $M 2>&1); grep -qF "already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; for f in fn set ev; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: $FN $BEFORE -> $AFTER; only the runner changed; one setting (jobs.transient_retry_max = 5, 0 to 50 times, label and used_by) and one audit row added; applied again: no change"

# A1: a passing deadlock: the task stays running, the slice's work is rolled back, the next run finishes it
A=$(task lane-a "40P01 done"); tick
expect "A1 after the deadlock" "$(st $A)" "running|"
expect "A1 retry event" "$(retries $A)" 1
expect "A1 slice rolled back" "$(q "select count(*) from security.fx_work where job_id = '$A'")" 0
expect "A1 not closed" "$(q "select count(*) from security.fx_closed where job_id = '$A'")" 0
tick; expect "A1 next run" "$(st $A)" "done|"
expect "A1 closed once" "$(q "select count(*) from security.fx_closed where job_id = '$A'")" 1
echo "A1: a slice deadlock leaves the task running (its slice rolled back, one retry event, not closed); the next run takes it again and it finishes done"
# A2: serialization failure and lock not available are treated the same
S=$(task lane-s "40001 55P03 done"); tick; tick; expect "A2 still running" "$(st $S)" "running|"; tick
expect "A2 done" "$(st $S)" "done|"; expect "A2 retries" "$(retries $S)" 2
echo "A2: serialization failure (40001) and lock not available (55P03) are retried the same way"
# A3: a deadlock that keeps coming: 5 retries, then the task fails as before
X=$(task lane-x "40P01 40P01 40P01 40P01 40P01 40P01 done")
for i in 1 2 3 4 5; do tick; expect "A3 run $i" "$(st $X)" "running|"; done
tick; expect "A3 past the limit" "$(st $X)" "failed|fixture error 40P01"; expect "A3 retries" "$(retries $X)" 5
echo "A3: after jobs.transient_retry_max (5) retries the next transient error fails the task, with its error, as before"
# A4: any other error fails at once, as before
O=$(task lane-o "22012 done"); tick; expect "A4 other error" "$(st $O)" "failed|fixture error 22012"; expect "A4 no retry" "$(retries $O)" 0
echo "A4: any other error (22012) fails the task at once, unchanged"
# A5: the setting at 0 keeps the old behaviour
q "update pipeline.platform_toolset_settings set value = '0' where key = 'jobs.transient_retry_max'" >/dev/null
Z=$(task lane-z "40P01 done"); tick; expect "A5 setting 0" "$(st $Z)" "failed|fixture error 40P01"
q "update pipeline.platform_toolset_settings set value = '5' where key = 'jobs.transient_retry_max'" >/dev/null
echo "A5: with jobs.transient_retry_max at 0 a deadlock fails the task at once (the old behaviour)"
# A6: cancel and pause unchanged; an unfinished slice keeps the task running
C=$(task lane-c "done"); q "update pipeline.admin_jobs set cancel_requested = true where id = '$C'" >/dev/null
U=$(task lane-u "more more done"); q "update pipeline.admin_jobs set pause_requested = true where id = '$U'" >/dev/null
tick; expect "A6 cancel" "$(st $C)" "cancelled|"; expect "A6 pause" "$(st $U)" "paused|"
q "update pipeline.admin_jobs set state = 'queued' where id = '$U'" >/dev/null; tick; expect "A6 unfinished" "$(st $U)" "running|"
echo "A6: cancel and pause are unchanged; an unfinished slice keeps the task running"

# the forward recovery
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(md5of)" = $BEFORE ] && [ "$(q "select pg_get_functiondef('$FN'::regprocedure)")" = "$DEF0" ] || { echo "the recovery did not restore the runner byte for byte"; exit 1; }
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1); grep -qF "already the original" <<<"$OUT" || { echo "the second recovery was not a no-op"; exit 1; }
K=$(task lane-k "40P01 done"); tick; expect "recovery: old behaviour back" "$(st $K)" "failed|fixture error 40P01"
$P -1 -At -f $M >/dev/null; expect "applied again after the recovery" "$(md5of)" $AFTER
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$FN'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the recovery ran over a changed body"; exit 1; }
grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "unexpected recovery refusal"; exit 1; }
echo "recovery: the forward recovery returns the runner to the live text byte for byte (the old failure comes back), is repeatable, refuses a changed body, and the migration applies again after it"
echo "jobs-transient-retry: done"
