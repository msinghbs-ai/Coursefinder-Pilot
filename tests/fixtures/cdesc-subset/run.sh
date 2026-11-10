#!/usr/bin/env bash
# Guards: F-CDESC subset recovery (Platform Admin, 10 Nov 2026, Workstream C): migration 20261110230000 edits exactly five course-description function bodies (md5 from live to the stated md5), adds the helper functions (no setting value, Layer 4 item, reading, ledger row or description changes by applying it),
# applies twice with no change, stops over a changed live body, restores the five live bodies byte for byte from its held recovery file and comes back; and behaves as scenarios.sql says (only the sentences that fail a test are set aside and the rest admitted, and a reading whose only fault is its size is NOT cut,
# nor a remainder below the minimum, a generic or About page, a requirements page, a locked course, a duplicate or a human-rejected course are admitted), with every REGRESSION check failing on the database from before it.
# Needs a scratch PostgreSQL 16 or 17 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds on the cdesc-throughput harness (which builds on the cdesc-machine and course-description-backpressure harnesses).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${CDS_DB:-g_cdesc_subset}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
M=supabase/migrations/20261110230000_cf247_cdesc_subset_recovery.sql
HELD=supabase/held/cdesc_subset_recovery_forward_recovery.sql
F=tests/fixtures/cdesc-subset
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
q() { psql -X -d "$DB" -Atc "$1"; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CDS_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_thr" "${DB}_thr_old" "${DB}_t" "${DB}_rf" "${DB}_s"; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
BASE=$(CDT_KEEP=1 CDT_DB=${DB}_thr bash tests/fixtures/cdesc-throughput/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the cdesc-throughput harness failed"; exit 1; }
echo "base: the cdesc-throughput harness built the database (production-parity fixture with the cdesc migrations up to 20261110180000)"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true
createdb -T "${DB}_thr" "$DB"
declare -A LIVE=( ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)']=6e65745a7863f0dae97a743821475eb0 ['security.course_description_machine_admit_v1(uuid,text)']=69b8911fe24f041b4cf67a844d8d8f6f
                  ['security.course_description_machine_check_v1(uuid)']=4c321730269064b42ff9ac10a114336b ['security.course_description_machine_run_v1()']=faa6dab1bfeef3464ba86fac11b34766 ['security.data_delivery_cdesc_flow_v1()']=bd500303727d5c11a708aa99341809a4 )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the five definitions the migration edits = live (body md5, read 10 Nov 2026)"
dropdb --if-exists "${DB}_old" >/dev/null 2>&1; createdb -T "$DB" "${DB}_old"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.field_enrich_items" > "$1.rd"; q "select count(*) from catalogue.courses where nullif(btrim(description), '') is not null" > "$1.desc"; q "select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from (select * from pipeline.layer4_review_items) t" > "$1.l4rows"; q "select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from (select * from pipeline.field_enrich_items) t" > "$1.rdrows"; q "select count(*) from pipeline.course_description_machine_admissions" > "$1.led"; }
snap "$W/0"
$P -1 -At -f $M >/dev/null
snap "$W/1"
CHANGED=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ .*//' | sort)
EXPECT=$(printf '%s\n' "${!LIVE[@]}" | sort)
[ "$CHANGED" = "$EXPECT" ] || { echo "the changed functions are not exactly the five edited ones:"; echo "$CHANGED"; exit 1; }
for sig in "${!LIVE[@]}"; do grep -Fq "$sig ${LIVE[$sig]}" "$W/0.fn" || { echo "$sig was not at its live md5 before"; exit 1; }; done
! grep -q '@@MD5_' $M || { echo "a placeholder md5 is left in the migration"; exit 1; }
NEW=$(comm -13 "$W/0.fn" "$W/1.fn" | sed 's/ .*//' | sort)
[ "$(comm -13 <(printf '%s\n' "$CHANGED") <(printf '%s\n' "$NEW") | tr '\n' ' ')" = "admin_course_description_item_v1(uuid[]) security.cdesc_item_detail_v1(uuid[]) security.cdesc_page_kind_v1(text,text,text) security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric) security.cdesc_subset_plan_v1(uuid,uuid,jsonb) security.cdesc_subset_recover_v1() security.data_delivery_cdesc_subset_v1() " ] || { echo "the new functions are not exactly the seven new ones:"; echo "$NEW"; exit 1; }
cmp -s "$W/0.set" "$W/1.set" || { echo "a setting changed or was added:"; diff "$W/0.set" "$W/1.set"; exit 1; }
for f in l4 rd desc l4rows rdrows led; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
echo "applied: only the five governed function bodies changed (and seven new functions were added); no setting (none added), Layer 4 item, reading, ledger row or description changed"
$P -1 -At -f $M >/dev/null
snap "$W/2"; for f in fn set l4 rd desc l4rows rdrows led; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change (functions, settings, items, readings, ledger, descriptions)"
# a live body that is neither the one this edits nor the one it writes stops the migration and applies nothing
dropdb --if-exists "${DB}_t" >/dev/null 2>&1; createdb -T "${DB}_old" "${DB}_t"
psql -X -q -d "${DB}_t" -c "create or replace function security.course_description_machine_run_v1() returns jsonb language sql as \$\$ select '{}'::jsonb \$\$"
if OUT=$(psql -X -d "${DB}_t" -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1); then echo "the migration applied over a changed live body"; exit 1; fi
grep -qF 'differs from the definition this change replaces' <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d "${DB}_t" -Atc "select to_regprocedure('security.cdesc_subset_recover_v1()') is null")" = t ] || { echo "the refused migration left a function behind"; exit 1; }
dropdb --if-exists "${DB}_t" >/dev/null 2>&1
echo "refused: a live body that differs from the guarded one stops the migration and nothing is applied"
# forward recovery
createdb -T "$DB" "${DB}_rf"
psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null || { echo "the forward recovery failed"; exit 1; }
for sig in "${!LIVE[@]}"; do [ "$(psql -X -d "${DB}_rf" -Atc "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the forward recovery did not restore $sig"; exit 1; }; done
psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null || { echo "the forward recovery does not run twice"; exit 1; }
psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -1 -f $M >/dev/null 2>&1 || { echo "the migration failed after its forward recovery"; exit 1; }
for sig in "${!LIVE[@]}"; do grep -Fq "$sig $(psql -X -d "${DB}_rf" -Atc "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" "$W/1.fn" || { echo "the migration did not bring back $sig"; exit 1; }; done
dropdb --if-exists "${DB}_rf" >/dev/null 2>&1
echo "forward recovery: the held file restores the five live bodies byte for byte (twice); applying the migration again brings the edits back"

# the scenarios: prelude of the cdesc-machine scenarios (lines 5 to 88), then ours; on the migrated database and on the database from before it
pre() { sed -n '5,88p' tests/fixtures/cdesc-machine/scenarios.sql; }
FPN=""; FPO=""
for pair in "$DB:new" "${DB}_old:old"; do
  d=${pair%%:*}; mode=${pair##*:}
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1; createdb -T "$d" "${DB}_s"
  { pre; cat $F/scenarios.sql; } > "$W/$mode.sql"
  OUT=$(psql -X -d "${DB}_s" -v ON_ERROR_STOP=1 -f "$W/$mode.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
  FP=$(echo "$OUT" | sed -n 's/^NOTICE equivalence: the course description check gives one answer for every battery input (fingerprint \([0-9a-f]*\)).*/\1/p')
  if [ "$mode" = new ]; then
    if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "scenarios FAILED on the migrated database"; exit 1; fi
    echo "$OUT" | grep -q 'cdsub: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
    echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /subset: /'
    FPN=$FP
  else
    FAILS=$(echo "$OUT" | grep -c 'REGRESSION.*\[FAIL\]' || true)
    EXPECTED=$(grep -c "expect('REGRESSION" $F/scenarios.sql)
    [ "$FAILS" -ge 4 ] || { echo "only $FAILS of $EXPECTED REGRESSION checks fail on the database from before the migration (at least 4 must)"; echo "$OUT" | grep FAIL; exit 1; }
    echo "regression: $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"
    FPO=$FP
  fi
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1
done
[ -n "$FPN" ] && [ "$FPN" = "$FPO" ] || { echo "the course description check answers differently after the migration (fingerprint $FPN, before $FPO)"; exit 1; }
echo "equivalence: the course description check gives the same answer for every battery input before and after the migration (fingerprint $FPN)"
echo "cdesc-subset: done"
