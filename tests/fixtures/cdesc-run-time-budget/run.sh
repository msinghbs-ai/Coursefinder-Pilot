#!/usr/bin/env bash
# Guards: F-CDESC job time budget (CF-247 QA follow-up F1; Platform Admin 11 Nov 2026 13:45): migration 20261112080000 edits only security.course_description_machine_settle_v1 and security.course_description_machine_consumer_recheck_v1 (md5-guarded,
# refused with nothing applied when a live body differs). Settle never takes another item past 85 s of the job's statement and the read-back never starts another past 100 s, so a run with a backlog ends well inside the 120 s statement
# time-out instead of being cancelled with every decision rolled back; without a backlog nothing changes; the forward recovery returns both bodies byte for byte. The overrun is reproduced on the live text first. Real time: about 6 minutes.
# Needs a scratch PostgreSQL 16 or 17 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. CRT_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order whatever the runner's locale
DB=${CRT_DB:-g_cdesc_run_time_budget}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
F=tests/fixtures/cdesc-run-time-budget
M=supabase/migrations/20261112080000_cf247_cdesc_run_time_budget.sql
R=supabase/held/cdesc_run_time_budget_forward_recovery.sql
S='security.course_description_machine_settle_v1()'; S0=4c40d655a7ff674ce184b598056d835f; S1=5fa17251727adbb49cb718be889fce54
C='security.course_description_machine_consumer_recheck_v1()'; C0=a6138e39a1ba4a3d1b04cc01994d2848; C1=f4b6bc3e45866782c5f694046d07131f
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
q() { PGOPTIONS='-c statement_timeout=0' psql -X -q -d "$DB" -Atc "$1"; }
md5of() { q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure"; }
expect() { [ "$2" = "$3" ] || { echo "$1: got '$2', expected '$3'"; exit 1; }; }
cleanup() { [ -n "${CRT_KEEP:-}" ] || { dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1; }; }
trap cleanup EXIT
dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1
createdb $DB
$P -f $F/stubs.sql; $P -f $F/live/security.course_description_machine_settle_v1.sql; $P -f $F/live/security.course_description_machine_consumer_recheck_v1.sql
expect "loaded settle" "$(md5of "$S")" $S0; expect "loaded read-back" "$(md5of "$C")" $C0
echo "loaded: $S = live ($S0) and $C = live ($C0), read 11 Nov 2026; the admission, the Website read-back and the earlier steps are stand-ins"
DS=$(q "select pg_get_functiondef('$S'::regprocedure)"); DC=$(q "select pg_get_functiondef('$C'::regprocedure)")
backlog() { q "delete from pipeline.layer4_review_items; insert into pipeline.layer4_review_items(id, entity_type, field_code, status, created_at) select gen_random_uuid(), 'course', 'course_description_first_read', 'pending', now() - make_interval(secs => g) from generate_series(1, $1) g" >/dev/null; }
admitted() { q "select count(*) from pipeline.layer4_review_items where status = 'approved'"; }
# timed: runs $1 in one statement, prints "<result>|<seconds>"
timed() { q "select ($1)::text || '|' || round(extract(epoch from clock_timestamp() - statement_timestamp()))"; }

# BEFORE: on the live text, settle starting 83 s into the statement keeps admitting for its own 40 s: the statement ends past 120 s (in the job it would be cancelled and every decision rolled back)
backlog 60
OUT=$(timed "security.fx_settle_after(83)"); SECS=${OUT##*|}
[ "$SECS" -ge 121 ] || { echo "before: the live settle did not overrun (ended at ${SECS}s)"; exit 1; }
echo "before: on the live text settle started 83 s into the statement admits $(admitted) items and ends at ${SECS} s, past the 120 s limit of the job (the regression fails on the old body)"

# a live body that differs: refused, nothing applied
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$C'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "the migration applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change replaces" <<<"$OUT" || { echo "unexpected refusal: $OUT" | tail -3; exit 1; }
expect "refused: settle untouched" "$(psql -X -d ${DB}_x -Atc "select md5(prosrc) from pg_proc where oid = '$S'::regprocedure")" $S0
dropdb ${DB}_x
echo "refused: a hand-changed read-back body is refused and the whole migration rolls back (settle untouched too)"

FN0=$(q "select string_agg(p.oid::regprocedure::text || ' ' || md5(p.prosrc), E'\n' order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','pipeline','public','catalogue')")
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
expect "settle after" "$(md5of "$S")" $S1; expect "read-back after" "$(md5of "$C")" $C1
grep -qF -- "--   $S   $S0 -> $S1" $M && grep -qF -- "--   $C   $C0 -> $C1" $M || { echo "the header does not record the md5s"; exit 1; }
FN1=$(q "select string_agg(p.oid::regprocedure::text || ' ' || md5(p.prosrc), E'\n' order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','pipeline','public','catalogue')")
expect "only the two functions changed" "$(comm -3 <(echo "$FN0" | sort) <(echo "$FN1" | sort) | sed 's/^\t//; s/ [0-9a-f]*$//' | sort -u | tr '\n' ',')" "$C,$S,"
OUT=$($P -1 -At -f $M 2>&1); [ "$(grep -c "already applied" <<<"$OUT")" = 2 ] || { echo "the second run was not a no-op"; exit 1; }
echo "migration: $S $S0 -> $S1 and $C $C0 -> $C1; nothing else changed; applied again: no change"

# A1: the same backlog: settle started 83 s in stops taking items at 85 s
backlog 60
OUT=$(timed "security.fx_settle_after(83)"); SECS=${OUT##*|}; N=$(admitted)
[ "$SECS" -le 88 ] || { echo "A1: settle ran to ${SECS}s"; exit 1; }
[ "$N" -ge 1 ] && [ "$N" -le 4 ] || { echo "A1: admitted $N"; exit 1; }
echo "A1: settle started 83 s into the statement admits $N item(s) and stops at ${SECS} s (85 s bound); the other $((60 - N)) wait for the next run"
# A2: without earlier steps settle still uses its own 40 s box (unchanged) and takes a short backlog whole
backlog 5
OUT=$(timed "security.course_description_machine_settle_v1()"); expect "A2 settle result" "${OUT%|*}" '{"on": true, "errors": 0, "admitted": 5, "left_for_a_person": 0}'
echo "A2: with no earlier work in the statement a short backlog is settled whole, as before"
# A3: the read-back started 98 s in stops starting checks at 100 s
q "insert into catalogue.courses select gen_random_uuid(), 'k' || g from generate_series(1, 40) g; insert into pipeline.course_description_machine_admissions(course_id, outcome, after_description) select id, 'admitted', 'text ' || stable_key from catalogue.courses" >/dev/null
OUT=$(timed "security.fx_recheck_after(98)"); SECS=${OUT##*|}; N=$(q "select count(*) from pipeline.course_description_machine_admissions where consumer_check is not null")
[ "$SECS" -le 102 ] || { echo "A3: read-back ran to ${SECS}s"; exit 1; }
[ "$N" -ge 1 ] && [ "$N" -le 6 ] || { echo "A3: rechecked $N"; exit 1; }
echo "A3: the read-back started 98 s into the statement checks $N admission(s) and stops at ${SECS} s (100 s bound)"
# A4: without earlier steps the read-back keeps its own 15 s box (unchanged)
OUT=$(timed "security.course_description_machine_consumer_recheck_v1()"); SECS=${OUT##*|}
[ "$SECS" -ge 14 ] && [ "$SECS" -le 17 ] || { echo "A4: read-back ran ${SECS}s"; exit 1; }
echo "A4: with no earlier work the read-back keeps its own 15 s box (${SECS} s), as before"

# the forward recovery
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(q "select pg_get_functiondef('$S'::regprocedure)")" = "$DS" ] && [ "$(q "select pg_get_functiondef('$C'::regprocedure)")" = "$DC" ] || { echo "the recovery did not restore both bodies byte for byte"; exit 1; }
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1); [ "$(grep -c "already the original" <<<"$OUT")" = 2 ] || { echo "the second recovery was not a no-op"; exit 1; }
$P -1 -At -f $M >/dev/null; expect "applied again after the recovery" "$(md5of "$S")" $S1
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$S'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the recovery ran over a changed body"; exit 1; }
grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "unexpected recovery refusal"; exit 1; }
echo "recovery: both bodies return to the live text byte for byte, repeatable, refused on a changed body, and the migration applies again after it"
echo "cdesc-run-time-budget: done"
