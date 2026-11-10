#!/usr/bin/env bash
# Guards: F-CDESC course description throughput (CF-247; Platform Admin 10 Nov 2026 23:17): migration 20261111000000 edits only security.course_description_machine_trg_v1 (checked by the md5 of its body, refused with nothing applied when the live body differs).
# A reading recorded through the API (the AI worker's svc_enrich_ai_record: many answers in ONE statement under the API statement time-out) is recorded without running the admission inside that statement, so a slow admission can no longer cancel the whole
# batch; the job's real settle (live text) then admits each such reading once, via 'settle'; a reading recorded outside the API (the job's subset recovery and held recheck) is admitted at once as before; the switch off still does nothing;
# the forward recovery returns the previous body byte for byte. The failure is reproduced on the live text first (the regression fails on the old body).
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Loads the LIVE bodies of the trigger function and of security.course_description_machine_settle_v1 (live/, md5 checked) over the stand-ins in stubs.sql
# (the admission is a stand-in that records each call and sleeps fx.admit_ms, the measured cost of the real check and read-back). CAO_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order whatever the runner's locale
DB=${CAO_DB:-g_cdesc_admit_outside}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
F=tests/fixtures/cdesc-admit-outside-record
M=supabase/migrations/20261111000000_cf247_cdesc_admit_outside_ai_record.sql
R=supabase/held/cdesc_admit_outside_ai_record_forward_recovery.sql
FN='security.course_description_machine_trg_v1()'; BEFORE=ec9b96498c54e37f8492a1003ea97520; AFTER=c75d63a6390f4cb0e3ed7276e70c25f8
SETTLE='security.course_description_machine_settle_v1()'; SETTLE_MD5=4c40d655a7ff674ce184b598056d835f
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
q() { psql -X -q -d "$DB" -Atc "$1"; }
md5of() { q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure"; }
expect() { [ "$2" = "$3" ] || { echo "$1: got '$2', expected '$3'"; exit 1; }; }
W=$(mktemp -d)
cleanup() { rm -rf "$W"; [ -n "${CAO_KEEP:-}" ] || { dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1; }; }
trap cleanup EXIT
dropdb --if-exists $DB >/dev/null 2>&1; dropdb --if-exists ${DB}_x >/dev/null 2>&1
createdb $DB
$P -f $F/stubs.sql; $P -f $F/live/security.course_description_machine_trg_v1.sql; $P -f $F/live/security.course_description_machine_settle_v1.sql
$P -c "create trigger field_enrich_items_cdesc_machine after update of state on pipeline.field_enrich_items for each row when (new.state = 'review' and old.state is distinct from 'review' and new.field = 'description') execute function security.course_description_machine_trg_v1()"
expect "loaded trigger function" "$(md5of "$FN")" $BEFORE
expect "loaded settle" "$(md5of "$SETTLE")" $SETTLE_MD5
echo "loaded: $FN = live (body md5 $BEFORE) and $SETTLE = live ($SETTLE_MD5), read 10 Nov 2026; the admission is a stand-in"
DEF0=$(q "select pg_get_functiondef('$FN'::regprocedure)")
TRG0=$(q "select pg_get_triggerdef(oid) from pg_trigger where tgname = 'field_enrich_items_cdesc_machine'")

# n readings (leased) with their waiting Layer 4 items; prints the reading ids
mk() { q "with l as (insert into pipeline.layer4_review_items(id, entity_type, field_code, status, created_at) select gen_random_uuid(), 'course', 'course_description_first_read', 'pending', now() - make_interval(secs => 100 - g) from generate_series(1, $1) g returning id),
                 r as (insert into pipeline.field_enrich_items(field, state, value) select 'description', 'leased', jsonb_build_object('review_item_id', l.id::text, 'text', 'x') from l returning id) select string_agg(id::text, ',' order by id) from r"; }
# one recording statement moving the readings to review: $1 ids, $2 api|job|empty, $3 admission cost ms; the statement time-out is 1.5 s (the API's 8 s scaled with the cost); prints ok or the error
record() {
  local ctx=""; case "$2" in api) ctx="select set_config('request.method', 'POST', true);";; empty) ctx="select set_config('request.method', '', true);";; esac
  psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -At 2>&1 <<SQL | grep -E '^(ok|ERROR: .*)$' | head -1 || true
begin;
$ctx
select set_config('fx.admit_ms', '$3', true);
set local statement_timeout = '1500ms'; -- fixed: the fixture's API time-out
update pipeline.field_enrich_items set state = 'review' where id in ($1);
commit;
select 'ok';
SQL
}
states() { q "select string_agg(state, ',' order by id) from pipeline.field_enrich_items where id in ($1)"; }
calls() { q "select count(*) from security.fx_admit_calls a join pipeline.field_enrich_items f on (f.value->>'review_item_id')::uuid = a.item where f.id in ($1) and a.via = '$2'"; }

# BEFORE: the failure on the live text. Three description readings in one API call, each admission 700 ms: the call passes the time-out, the trigger's "exception when others" does not catch it, the whole call is cancelled
B=$(mk 3)
OUT=$(record "$B" api 700)
grep -qF "canceling statement due to statement timeout" <<<"$OUT" || { echo "before: the live text did not time out: $OUT"; exit 1; }
expect "before: readings after the cancelled call" "$(states "$B")" "leased,leased,leased"
expect "before: admissions kept" "$(q "select count(*) from security.fx_admit_calls")" 0
echo "before: on the live text one API call recording 3 description readings (about 0.7 s of admission each) is cancelled by the time-out; all 3 answers are lost (still leased), the regression fails on the old body"
q "truncate security.fx_admit_calls; delete from pipeline.field_enrich_items; delete from pipeline.layer4_review_items" >/dev/null

snap() { q "select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security','pipeline','public') order by 1" > "$1.fn"
         q "select key || '=' || value::text from pipeline.platform_toolset_settings order by 1" > "$1.set"
         q "select pg_get_triggerdef(oid) from pg_trigger where not tgisinternal order by tgname" > "$1.trg"
         q "select count(*) || ' ' || coalesce(string_agg(state, ',' order by id), '') from pipeline.field_enrich_items" > "$1.rd"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; }

# a live body that differs: the migration refuses, and nothing is applied
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$FN'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "the migration applied over a changed body"; exit 1; }
grep -qF "differs from the definition this change replaces" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d ${DB}_x -Atc "select md5(prosrc) <> '$AFTER' from pg_proc where oid = '$FN'::regprocedure")" = t ] || { echo "the refused migration changed the body"; exit 1; }
dropdb ${DB}_x
echo "refused: a hand-changed live trigger function is refused by the migration (transaction rolled back, body untouched)"

# the migration
snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
expect "after md5" "$(md5of "$FN")" $AFTER
grep -qF -- "--   $FN   $BEFORE -> $AFTER" $M || { echo "the migration header does not record the md5s"; exit 1; }
snap "$W/1"
[ "$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//')" = "$FN" ] && [ "$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//')" = "$FN" ] || { echo "functions other than the trigger function changed"; exit 1; }
for f in set trg rd l4; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
OUT=$($P -1 -At -f $M 2>&1); grep -qF "already applied" <<<"$OUT" || { echo "the second run was not a no-op"; exit 1; }
snap "$W/2"; for f in fn set trg rd l4; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "migration: $FN $BEFORE -> $AFTER; no other function, setting, trigger, reading or Layer 4 item changed; applied again: no change"

# A1: the same API call now records all 3 readings at once and runs no admission inside it
A=$(mk 3)
expect "A1 recording" "$(record "$A" api 700)" ok
expect "A1 states" "$(states "$A")" "review,review,review"
expect "A1 admissions inside the call" "$(q "select count(*) from security.fx_admit_calls")" 0
expect "A1 still waiting" "$(q "select count(*) from pipeline.layer4_review_items where status = 'pending'")" 3
echo "A1: one API call recording 3 description readings now completes (all 3 in review, no admission run inside the call); the 3 Layer 4 items wait, undecided"
# A2: the job's real settle (live text, job context) admits each waiting reading once, via settle, oldest first
OUT=$(q "select set_config('fx.admit_ms', '700', false); select security.course_description_machine_settle_v1()::text" | tail -1)
expect "A2 settle" "$OUT" '{"on": true, "errors": 0, "admitted": 3, "left_for_a_person": 0}'
expect "A2 calls via settle" "$(calls "$A" settle)" 3
expect "A2 one call each" "$(q "select count(distinct item) || '/' || count(*) from security.fx_admit_calls")" "3/3"
expect "A2 nothing waiting" "$(q "select count(*) from pipeline.layer4_review_items where status = 'pending'")" 0
echo "A2: the job's live settle takes the 3 readings left waiting and admits each exactly once (via settle); nothing is left waiting"
# A3: a reading recorded outside the API (the job: subset recovery, held recheck) is admitted at once, as before
J=$(mk 2)
expect "A3 recording" "$(record "$J" job 0)" ok
expect "A3 fresh_reading" "$(calls "$J" fresh_reading)" 2
echo "A3: readings recorded by the job (no API request) are admitted at once inside the recording, via fresh_reading, exactly as before"
# A4: an empty request.method is no API request
E=$(mk 1)
expect "A4 recording" "$(record "$E" empty 0)" ok
expect "A4 fresh_reading" "$(calls "$E" fresh_reading)" 1
echo "A4: an empty request.method is treated as no API request (admitted at once)"
# A5: the switch off: nothing is admitted in either context
q "update pipeline.platform_toolset_settings set value = '0' where key = 'enrich.course_description_machine_on'" >/dev/null
O1=$(mk 1); O2=$(mk 1)
expect "A5 api" "$(record "$O1" api 0)" ok; expect "A5 job" "$(record "$O2" job 0)" ok
expect "A5 calls" "$(q "select count(*) from security.fx_admit_calls a join pipeline.field_enrich_items f on (f.value->>'review_item_id')::uuid = a.item where f.id in ($O1,$O2)")" 0
expect "A5 settle" "$(q "select security.course_description_machine_settle_v1()::text")" '{"on": false}'
q "update pipeline.platform_toolset_settings set value = '1' where key = 'enrich.course_description_machine_on'" >/dev/null
echo "A5: with enrich.course_description_machine_on at 0 nothing is admitted, through the API or by the job (unchanged)"
# A6: the trigger still fires only on a move into review of a description reading
N=$(q "insert into pipeline.field_enrich_items(field, state, value) values ('deadline', 'leased', jsonb_build_object('review_item_id', gen_random_uuid()::text)) returning id")
expect "A6 recording" "$(record "$N" job 0)" ok
expect "A6 calls" "$(q "select count(*) from security.fx_admit_calls a join pipeline.field_enrich_items f on (f.value->>'review_item_id')::uuid = a.item where f.id = $N")" 0
expect "A6 trigger unchanged" "$(q "select pg_get_triggerdef(oid) from pg_trigger where tgname = 'field_enrich_items_cdesc_machine'")" "$TRG0"
echo "A6: the trigger definition is unchanged (after update of state, into review, description only)"

# the forward recovery
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(md5of "$FN")" = $BEFORE ] && [ "$(q "select pg_get_functiondef('$FN'::regprocedure)")" = "$DEF0" ] || { echo "the recovery did not restore the trigger function byte for byte"; exit 1; }
OUT=$(psql -X -d $DB -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1); grep -qF "already the original" <<<"$OUT" || { echo "the second recovery was not a no-op"; exit 1; }
B2=$(mk 3); OUT=$(record "$B2" api 700); grep -qF "canceling statement due to statement timeout" <<<"$OUT" || { echo "after the recovery the old behaviour did not come back"; exit 1; }
$P -1 -At -f $M >/dev/null; expect "applied again after the recovery" "$(md5of "$FN")" $AFTER
createdb -T $DB ${DB}_x
psql -X -q -d ${DB}_x -v ON_ERROR_STOP=1 -c "do \$\$ begin execute regexp_replace(pg_get_functiondef('$FN'::regprocedure), 'begin', 'begin /* changed by hand */'); end \$\$"
OUT=$(psql -X -d ${DB}_x -q -At -v ON_ERROR_STOP=1 -1 -f $R 2>&1) && { echo "the recovery ran over a changed body"; exit 1; }
grep -qF "differs from both texts this recovery knows" <<<"$OUT" || { echo "the recovery refusal is not the expected one"; exit 1; }
echo "recovery: the forward recovery returns the trigger function to the live text byte for byte (pg_get_functiondef identical, the old time-out comes back), is repeatable, refuses a changed body, and the migration applies again after it"
echo "cdesc-admit-outside-record: done"
