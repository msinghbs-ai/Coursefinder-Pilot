#!/usr/bin/env bash
# Guards: F-INT D3 forward fix (Platform Admin decision 9 Nov 2026: "Do not manually rerun an already-applied migration. If the revisit backfill was missed, implement an idempotent forward
# migration with checksum, row-count and rollback/forward-recovery safeguards."): migration 20261109170000 on an isolated PostgreSQL copy of the production-equivalent fixture
# (tests/fixtures/deakin-intake-calendar/run.sh, kept) in the state production holds after release #943 (migrations 20261109040000 and 20261109041000 applied with the switch
# intake_dates.revisit_stored_inputs at 0). Phase 1 switch OFF (nothing changes, applied twice); phase 2 switch ON with each safeguard tampered in turn (the whole migration rolls back, state
# identical); phase 3 the real run (expected rows, record, checksum, idempotent second application); phase 4 forward recovery by the security function; phase 5 re-run and the
# Platform Admin call. The consumer API (G3) and every other function definition are compared before and after. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=intake_deakin_calendar_fixtures; DB=${RB_DB:-intake_revisit_backfill_fixtures}; F=tests/fixtures/intake-revisit-backfill; SD=tests/fixtures/intake-self-driving
MIG=supabase/migrations/20261109170000_cf247_intake_revisit_backfill.sql
RELEASED=(supabase/migrations/20261109040000_cf247_intake_revisit_page_fingerprint.sql supabase/migrations/20261109041000_cf247_intake_applicability_month_year.sql)
ART=${UAT_ARTIFACTS:-/tmp}
P=(psql -X -q -v ON_ERROR_STOP=1)
fail() { echo "FAIL $*"; exit 1; }
if [ -z "${RB_REUSE:-}" ] || ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  DK_KEEP=1 bash tests/fixtures/deakin-intake-calendar/run.sh > /dev/null 2> "$ART/rb-base.err" || { grep -v NOTICE "$ART/rb-base.err" | tail -20; exit 1; }
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE || true
[ -n "${RB_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
q() { "${P[@]}" -d $DB -Atc "$1"; }
apply() { "${P[@]}" -d $DB -1 -f $MIG 2>&1; }   # the migration as the deploy applies it: one transaction
# production as released by #943: the repeat check and its two tables, then the two released migrations
"${P[@]}" -d $DB -f $SD/stubs.sql 2>&1 | grep -v NOTICE || true
"${P[@]}" -d $DB -c 'set check_function_bodies = off' -f $SD/live-repeats-function.sql
for m in "${RELEASED[@]}"; do "${P[@]}" -d $DB -1 -o /dev/null -f $m 2>&1 | grep -v NOTICE || true; done
# parity: the definitions the backfill calls are those of production (read 9 Nov 2026)
for x in 'security.intake_revisit_stored_inputs_v1(text) b6d11a5f07271ba950de01d1a0ae6517' 'security.intake_revisit_at_v1(text) dd10dc1c02a0ecf7a75d63467df1110a' \
         'security.intake_failure_class_trg_v1() 3353fe59717325d9870808e10d5af40d' 'security.current_role_rank() d709d92dbd7a648ccf78e594d68ca980'; do
  set -- $x; [ "$(q "select md5(pg_get_functiondef('$1'::regprocedure))")" = "$2" ] || fail "$1 differs from production ($(q "select md5(pg_get_functiondef('$1'::regprocedure))"), expected $2)"
done
echo 'PASS parity: the four production definitions the backfill calls or relies on (the helper that names the four actions and reads the switch, the revisit time, the failure-class trigger, the role rank) = production (md5, read 9 Nov 2026)'
[ "$(q "select value::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.revisit_stored_inputs'")" = "0" ] || fail 'the switch is not 0 after the released migrations'
# G3 and "nothing else": the consumer API and every function definition outside the two new ones
API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%') or p.proname = 'svc_website_settings_v1') order by 1"
DEFS_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue', 'search') and p.prokind in ('f', 'p') and p.proname not like 'rb\_%' and p.proname not in ('intake_revisit_backfill_undo_v1', 'admin_intake_revisit_backfill_undo_v1') order by 1"
"${P[@]}" -d $DB -Atc "$API_SQL" > "$ART/rb-api-before.txt"; "${P[@]}" -d $DB -Atc "$DEFS_SQL" > "$ART/rb-defs-before.txt"
"${P[@]}" -d $DB -f $F/seed.sql 2>&1 | grep -o 'PASS.*'
state() { q "select md5(string_agg(to_jsonb(d)::text, '|' order by d.intake_id)) from pipeline.course_intake_dates d"; }
S1=$(state)

# phase 1: switch OFF (as production today): nothing changes, applied twice, the tables and functions exist
OUT=$(apply) || fail "phase 1 first application: $OUT"
echo "$OUT" | grep -q 'intake_dates.revisit_stored_inputs is 0 (not 1), so no row is changed; the switch is not turned on by this migration' || fail "phase 1: no notice: $OUT"
OUT=$(apply) || fail "phase 1 second application: $OUT"
echo "$OUT" | grep -q 'is 0 (not 1)' || fail 'phase 1 second application: no notice'
[ "$(state)" = "$S1" ] || fail 'phase 1: the migration changed a decision row with the switch off'
[ "$(q "select count(*) from pipeline.intake_revisit_backfill_batches") $(q "select count(*) from pipeline.intake_revisit_backfill_log")" = "0 0" ] || fail 'phase 1: a record was written with the switch off'
[ "$(q "select value::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.revisit_stored_inputs'")" = "0" ] || fail 'phase 1: the switch changed'
echo 'PASS switch off: applied twice with intake_dates.revisit_stored_inputs at 0, the migration raises a notice, changes no decision row, writes no batch or log row and leaves the switch at 0 (it never turns a switch on)'

# the Platform Admin turns the switch on in Settings > Pipeline settings (with a reason); then the change is merged
q "update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.revisit_stored_inputs'" > /dev/null
q "create table public.rb_set as select * from pipeline.platform_toolset_settings" > /dev/null
S2=$(state)
cleanup_tamper() { q "drop trigger if exists rb_tamper on pipeline.course_intake_dates; drop trigger if exists rb_tamper on pipeline.intake_revisit_backfill_log; drop trigger if exists rb_tamper on pipeline.intake_revisit_backfill_batches" > /dev/null; }

# phase 2: each safeguard tampered in turn: the migration fails, everything it did rolls back
tamper() { # case, expected message
  "${P[@]}" -d $DB -v case=$1 -f $F/tamper.sql
  if OUT=$(apply); then cleanup_tamper; fail "phase 2 $1: the migration did not abort: $OUT"; fi
  cleanup_tamper
  echo "$OUT" | grep -q "$2" || fail "phase 2 $1: wrong error: $(echo "$OUT" | grep -E 'ERROR|CONTEXT' | cut -c1-400)"
  [ "$(state)" = "$S2" ] || fail "phase 2 $1: a decision row changed after the abort"
  [ "$(q "select count(*) from pipeline.intake_revisit_backfill_batches") $(q "select count(*) from pipeline.intake_revisit_backfill_log")" = "0 0" ] || fail "phase 2 $1: a record was left after the abort"
  echo "PASS abort ($1): $3"
}
tamper row_checksum 'checksum after the update' 'a row that holds a different time after the update than the plan (1 microsecond) stops the migration on the md5 checksum; nothing is changed, no batch or log row is left'
tamper other_column 'a column other than next_revisit_at changed' 'a column other than next_revisit_at changed on any row stops the migration; nothing is changed'
tamper other_row 'revisit time of a row that is not a candidate changed' 'a revisit time changed on a row that is not a candidate stops the migration; nothing is changed'
tamper row_not_updated 'rows planned' 'a candidate that is not updated (row count differs from the plan and the log) stops the migration; nothing is changed'
tamper log_value 'the log does not match the rows' 'a log row that does not hold the value set stops the migration; nothing is changed'
tamper batch_checksum 'the recorded checksum' 'a tampered checksum in the batch record stops the migration (the stored checksum is read back and compared); nothing is changed'
# a second run at the same moment: the advisory lock is held by another session
"${P[@]}" -d $DB -Atc "select pg_advisory_lock(hashtextextended('cf247.intake_revisit_backfill', 0)); select pg_sleep(6)" > /dev/null &
LOCKPID=$!; sleep 2
if OUT=$(apply); then wait $LOCKPID; fail "phase 2 lock: the migration ran while another run held its lock"; fi
echo "$OUT" | grep -q 'another run of the backfill holds its lock' || fail "phase 2 lock: wrong error"
wait $LOCKPID
[ "$(state)" = "$S2" ] || fail 'phase 2 lock: a decision row changed'
echo 'PASS abort (concurrent run): while another session holds the backfill lock the migration stops with nothing changed'

# phase 3: the real run
OUT=$(apply) || fail "phase 3: $OUT"
echo "$OUT" | grep -E 'F-INT revisit backfill: batch' | sed -e 's/^psql:[^ ]* //' | cut -c1-300
OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-600; fail 'cases-after'; }
echo "$OUT" | grep -o 'PASS.*'
# phase 4: the second application, then forward recovery
OUT=$(apply) || fail "phase 4: $OUT"
echo "$OUT" | grep -q 'no row needs a revisit time' || fail 'phase 4: the second application did not report no candidates'
OUT=$("${P[@]}" -d $DB -f $F/cases-undo.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-600; fail 'cases-undo'; }
echo "$OUT" | grep -o 'PASS.*'
# phase 5: a new version of the file after recovery, then the Platform Admin call
OUT=$(apply) || fail "phase 5: $OUT"
OUT=$("${P[@]}" -d $DB -f $F/cases-admin.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-600; fail 'cases-admin'; }
echo "$OUT" | grep -o 'PASS.*'
# G3 and nothing else
"${P[@]}" -d $DB -Atc "$API_SQL" > "$ART/rb-api-after.txt"; "${P[@]}" -d $DB -Atc "$DEFS_SQL" > "$ART/rb-defs-after.txt"
cmp -s "$ART/rb-api-before.txt" "$ART/rb-api-after.txt" || { diff "$ART/rb-api-before.txt" "$ART/rb-api-after.txt" | head; fail 'consumer API changed by the migration (G3)'; }
echo "PASS consumer API frozen: $(wc -l < "$ART/rb-api-after.txt") api, website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_* functions identical (md5 of the definition) before and after the migration and its re-runs"
cmp -s "$ART/rb-defs-before.txt" "$ART/rb-defs-after.txt" || { diff "$ART/rb-defs-before.txt" "$ART/rb-defs-after.txt" | head; fail 'a function definition changed'; }
echo "PASS no definition changed: $(wc -l < "$ART/rb-defs-after.txt") functions of security, public, api, pipeline, catalogue and search are identical before and after; the migration adds two functions and two tables only"
