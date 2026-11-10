#!/usr/bin/env bash
# Guards: Platform Admin decision 10 Nov 2026 19:47 (one primary outcome action, "Read / refresh entry requirements now", for academic entry requirements; F-AER.01-.06), F-AER.04 (first reads and protected changes stay human Layer 4 decisions) and G4 database-backed tests: migration 20261110220000 composes the existing readers into one governed action with a stage timeline, checks every reviewer packet for country, qualification, grade, scale, applicability, source page and year (a fact the page does not print is flagged "not stated", never filled), adds the Data Delivery reviewer key and stops one deliberately-off recovery switch from turning the whole stream off; md5-guarded, idempotent, and taken back by its held forward recovery.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a small database (stubs.sql: the live columns the change reads, the helpers it calls), loads the live definitions it edits (live/, bodies md5
# d593eb0aa0fe06b0b4b28c86821bfff5, 27a42c5f02d09f518e77bd965814bbe0, 330e079018c93f8db8a649ed3a08ae12 and 208067f054c2f3ac7adb1196e3e8c25c, read 10 Nov 2026) and the parked-items view of migration 20261110160000, then runs before.sql, the migration twice,
# after.sql, the refusals and the forward recovery. Drops the database at the end (ARN_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${ARN_DB:-g_aer_read_now}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
F=tests/fixtures/aer-read-now
M=supabase/migrations/20261110220000_cf247_aer_read_now.sql
R=supabase/held/aer_read_now_forward_recovery.sql
PARKED=supabase/migrations/20261110160000_cf247_aer_source_recovery.sql
POP='security.aer_course_population_v1()'; DDA='security.data_delivery_aer_v1()'; L4D='security.layer4_aer_review_detail_v1(text)'; DDV='security.data_delivery_v1()'
POP_BEFORE=d593eb0aa0fe06b0b4b28c86821bfff5; DDA_BEFORE=27a42c5f02d09f518e77bd965814bbe0; L4D_BEFORE=330e079018c93f8db8a649ed3a08ae12; DDV_BEFORE=208067f054c2f3ac7adb1196e3e8c25c
q() { psql -X -d "$DB" -Atc "$1"; }
W=$(mktemp -d); trap 'rm -rf "$W"; [ -n "${ARN_KEEP:-}" ] || { dropdb --if-exists '$DB' >/dev/null 2>&1; dropdb --if-exists '${DB}_refuse' >/dev/null 2>&1; dropdb --if-exists '${DB}_md5' >/dev/null 2>&1; }' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
$P -f $F/stubs.sql
# the parked-items view as migration 20261110160000 creates it (its create to the closing $f$)
awk '/^create or replace function security.aer_parked_items_v1/{f=1} f{print} f&&/^\$f\$;?$/{exit}' $PARKED > $W/parked.sql
[ -s $W/parked.sql ] || { echo "could not extract aer_parked_items_v1"; exit 1; }
$P -f $W/parked.sql
# the live definitions (bodies unchecked, as live holds them)
for f in security.aer_course_population_v1 security.data_delivery_aer_v1 security.layer4_aer_review_detail_v1 security.data_delivery_v1; do { echo "set check_function_bodies = off;"; cat $F/live/$f.sql; echo ";"; } > $W/$f.sql; $P -f $W/$f.sql; done
for t in "$POP $POP_BEFORE" "$DDA $DDA_BEFORE" "$L4D $L4D_BEFORE" "$DDV $DDV_BEFORE"; do set -- $t; [ "$(q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure")" = "$2" ] || { echo "the loaded $1 differs from live $2"; exit 1; }; done
echo "loaded: the four functions as live holds them (body md5 $POP_BEFORE, $DDA_BEFORE, $L4D_BEFORE, $DDV_BEFORE)"
$P -f $F/data.sql
OUT=$($P -f $F/before.sql 2>&1) || { echo "$OUT" | grep -E 'FAIL|ERROR' | head -3; exit 1; }
echo "before: the aer stream shows recovery off with two of three switches on, no reviewer key, no provider-scoped rules, no facts in the reviewer detail (the live defects, reproduced)"

# the md5 each edit leaves, learned by applying the migration once to a copy with the after-check switched off, then written into the migration header and guards
dropdb --if-exists ${DB}_md5 >/dev/null 2>&1; createdb -T $DB ${DB}_md5
sed -e 's/if md5(v_src) <> r.md5_after then raise exception/if false then raise exception/' -e 's/if r.must_match and md5(v_src) <> r.md5_after then raise exception/if false then raise exception/' $M > $W/learn.sql
psql -X -q -d ${DB}_md5 -v ON_ERROR_STOP=1 -1 -f $W/learn.sql >/dev/null 2>&1
md5of() { psql -X -d ${DB}_md5 -Atc "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure"; }
POP_AFTER=$(md5of "$POP"); DDA_AFTER=$(md5of "$DDA"); L4D_AFTER=$(md5of "$L4D"); DDV_AFTER=$(md5of "$DDV")
dropdb --if-exists ${DB}_md5 >/dev/null 2>&1
[ -z "${ARN_LEARN:-}" ] || { echo "$POP_AFTER $DDA_AFTER $L4D_AFTER $DDV_AFTER"; exit 0; }
for want in "$POP $POP_BEFORE -> $POP_AFTER" "$DDA $DDA_BEFORE -> $DDA_AFTER" "$L4D $L4D_BEFORE -> $L4D_AFTER" "$DDV $DDV_BEFORE -> $DDV_AFTER"; do grep -qF -- "--   $want" $M || { echo "the migration header does not record: $want"; exit 1; }; done
for a in "$POP_AFTER" "$DDA_AFTER" "$L4D_AFTER" "$DDV_AFTER"; do grep -qF "'$a'" $M || { echo "the migration guard does not carry the after md5 $a"; exit 1; }; done

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
DATA="select (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.layer4_review_items r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.field_enrich_items r) || (select md5(string_agg(r::text, '|' order by r.key)) from pipeline.platform_toolset_settings r) || (select md5(string_agg(r::text, '|' order by r.jobid)) from cron.job r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_runs r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_sources r) || (select md5(string_agg(r::text, '|' order by r.id)) from catalogue.provider_entry_matrix r) || (select md5(string_agg(r::text, '|' order by r.id)) from catalogue.course_entry_requirements r) || (select count(*) from pipeline.admin_control_events)"
snap() { q "$FNS" | sort > "$1.fn"; q "$DATA" > "$1.data"; }
same() { for f in "${@:3}"; do cmp -s "$1.$f" "$2.$f" || { echo "changed: $f"; exit 1; }; done; }

# a live function that differs from the recorded one: the migration raises and nothing at all is applied
for HAND in "$POP|and not exists (select 1 from pipeline.manual_locks|and true and not exists (select 1 from pipeline.manual_locks" "$L4D|v_sec jsonb;|v_sec jsonb; v_hand int;"; do
  FN=${HAND%%|*}; REST=${HAND#*|}; FROM=${REST%%|*}; TO=${REST#*|}
  RF=${DB}_refuse; dropdb --if-exists $RF >/dev/null 2>&1; createdb -T $DB $RF
  psql -X -q -d $RF -v ON_ERROR_STOP=1 -c "set check_function_bodies = off" -c "do \$\$ begin execute replace(pg_get_functiondef('$FN'::regprocedure), '$FROM', '$TO'); end \$\$" >/dev/null
  [ "$(psql -X -d $RF -Atc "select md5(prosrc) from pg_proc where oid = '$FN'::regprocedure")" != "$(q "select md5(prosrc) from pg_proc where oid = '$FN'::regprocedure")" ] || { echo "the hand change did not change $FN"; exit 1; }
  rb=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum) )
  OUT=$(psql -X -d $RF -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1) && { echo "$M applied over a changed $FN"; exit 1; }
  grep -qF "differs from the definition this change edits" <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
  ra=$( (psql -X -d $RF -Atc "$FNS" | sort | md5sum) )
  [ "$rb" = "$ra" ] || { echo "the refused migration changed something"; exit 1; }
  dropdb --if-exists $RF >/dev/null 2>&1
done
echo "refused: a hand-changed live population or reviewer detail is refused by the migration and nothing is applied (no function added, none edited)"

# the migration
snap "$W/0"
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
for t in "$POP $POP_AFTER" "$DDA $DDA_AFTER" "$L4D $L4D_AFTER" "$DDV $DDV_AFTER"; do set -- $t; [ "$(q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure")" = "$2" ] || { echo "the migration did not leave the recorded md5 for $1"; exit 1; }; done
snap "$W/1"
changed=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort); added=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ [0-9a-f]*$//' | sort)
[ "$changed" = "$(printf '%s\n' "$POP" "$DDA" "$L4D" "$DDV" | sort)" ] || { echo "functions changed other than the four edited: $changed"; exit 1; }
WANT_ADDED="admin_aer_read_now(jsonb)
security.aer_course_population_v1(uuid)
security.aer_packet_facts_v1(uuid)
security.aer_packet_rows_v1(uuid)
security.aer_pending_packets_v1(uuid,uuid)
security.aer_read_now_class_v1(text,text)
security.aer_read_now_out_v1(text,text,text,text,jsonb,jsonb)
security.aer_read_now_plan_v1(uuid,uuid)
security.aer_read_now_source_v1(uuid,uuid)
security.aer_read_now_status_v1(uuid,uuid)
security.aer_read_now_v1(uuid,uuid,text,uuid)"
[ "$(comm -13 <(echo "$changed") <(echo "$added") | sort)" = "$(echo "$WANT_ADDED" | sort)" ] || { echo "unexpected functions added: $added"; exit 1; }
same "$W/0" "$W/1" data
OUT=$($P -1 -At -f $M 2>&1) || { echo "$OUT" | tail -8; exit 1; }
snap "$W/2"; same "$W/1" "$W/2" fn data
echo "migration 20261110220000: four functions go from the recorded live md5s to the recorded after md5s, eleven functions are added, no layer 4 item, enrich item, setting, job, source, run or entry row changed; applied again: no change"

# the scenarios
OUT=$($P -f $F/after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|FAIL' | head -5; exit 1; }
echo "$OUT" | grep -qE 'FAIL|ERROR' && { echo "$OUT" | grep -E 'FAIL|ERROR' | head -5; exit 1; }
echo "scenarios: $(grep -c 'NOTICE:  ok:' <<<"$OUT") checks passed (packet facts with nothing filled or inferred, every outcome, budgets and caps shared with the scheduled reader, idempotent click, permissions, stage timeline, Data Delivery)"
[ -z "${ARN_VERBOSE:-}" ] || echo "$OUT" | grep 'NOTICE:  ok:'

# the forward recovery: the four edits are taken back; the new functions stay (unused); repeatable; the migration applies again after it
$P -1 -At -f $R >/dev/null
for t in "$POP $POP_BEFORE" "$DDA $DDA_BEFORE" "$L4D $L4D_BEFORE"; do set -- $t; [ "$(q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure")" = "$2" ] || { echo "the recovery did not restore the live body of $1"; exit 1; }; done
[ "$(q "select md5(prosrc) from pg_proc where oid = '$DDV'::regprocedure")" = "$DDV_BEFORE" ] || { echo "the recovery did not restore the live Data Delivery body"; exit 1; }
[ "$(q "select to_regprocedure('public.admin_aer_read_now(jsonb)') is not null")" = t ] || { echo "the recovery removed a new function"; exit 1; }
$P -1 -At -f $R >/dev/null
$P -1 -At -f $M >/dev/null
for t in "$POP $POP_AFTER" "$DDA $DDA_AFTER" "$L4D $L4D_AFTER" "$DDV $DDV_AFTER"; do set -- $t; [ "$(q "select md5(prosrc) from pg_proc where oid = '$1'::regprocedure")" = "$2" ] || { echo "the migration did not apply again after the recovery ($1)"; exit 1; }; done
echo "recovery: the forward recovery returns the four functions to the live bodies (md5s above), is repeatable, and the migration applies again after it"
echo "aer-read-now: done"
