#!/usr/bin/env bash
# Guards: F-CDESC decline throughput (Platform Admin directive 10 Nov 2026): migration 20261110180000 edits exactly seven course-description function bodies (md5 from live to the stated md5), adds the helper functions and two lists (no existing setting value, Layer 4 item, reading,
# ledger row or description changes by applying it), applies twice with no change, restores the seven live bodies byte for byte from its held recovery file and comes back; and behaves as scenarios_outcomes.sql and scenarios_flow.sql say, with every REGRESSION check
# failing on the database from before it. Needs a scratch PostgreSQL 16 or 17 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds on the cdesc-machine harness (which builds on the course-description-backpressure harness).
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${CDT_DB:-g_cdesc_throughput}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
M=supabase/migrations/20261110180000_cf247_cdesc_decline_throughput.sql
HELD=supabase/held/cdesc_decline_throughput_forward_recovery.sql
F=tests/fixtures/cdesc-throughput
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
q() { psql -X -d "$DB" -Atc "$1"; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CDT_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_t" "${DB}_rf"; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
BASE=$(CDM_KEEP=1 CDM_DB=$DB bash tests/fixtures/cdesc-machine/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the cdesc-machine harness failed"; exit 1; }
echo "base: the cdesc-machine harness built the database (production-parity fixture, the cdesc migrations up to 20261110130000)"
dropdb --if-exists "${DB}_pre" >/dev/null 2>&1 || true
$P -f $F/live/security.course_description_promote_held_v1.sql -f $F/stubs.sql
declare -A LIVE=( ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)']=3bb5d62b5e86cd7c76707171e02a3ae5 ['security.course_description_machine_check_v1(uuid)']=3e0fe24d762e7fc4348865ea09499690
                  ['security.enrich_course_text_record_v1(bigint,jsonb)']=c52c1969a80f2d3db1d81a4e46a49cd9 ['security.course_description_promote_held_v1(uuid)']=1c990fb9c93b1841195160a0e9a712ae
                  ['security.enrich_course_text_gaps_v1(text[])']=5352bc7ea7bbf3ef00bd616f2897f2f4 ['security.course_description_machine_run_v1()']=452e3ae1ed2ab196865e2905ad2801e1
                  ['security.data_delivery_cdesc_stages_v1()']=d2a913a4d294f71fadf949bff6786f94 )
for sig in "${!LIVE[@]}"; do
  [ "$(q "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the seven definitions the migration edits = live (body md5, read 10 Nov 2026)"
dropdb --if-exists "${DB}_old" >/dev/null 2>&1; createdb -T "$DB" "${DB}_old"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
snap() { q "$FNS" | sort > "$1.fn"; q "$SET" | sort > "$1.set"; q "select count(*) from pipeline.layer4_review_items" > "$1.l4"; q "select count(*) from pipeline.field_enrich_items" > "$1.rd"; q "select count(*) from catalogue.courses where nullif(btrim(description), '') is not null" > "$1.desc"; q "select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from (select * from pipeline.layer4_review_items) t" > "$1.l4rows"; q "select md5(coalesce(string_agg(t::text, '|' order by t::text), '')) from (select * from pipeline.field_enrich_items) t" > "$1.rdrows"; q "select count(*) from pipeline.course_description_machine_admissions" > "$1.led"; }
snap "$W/0"
$P -1 -At -f $M >/dev/null
snap "$W/1"
CHANGED=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ .*//' | sort)
EXPECT=$(printf '%s\n' "${!LIVE[@]}" | sort)
[ "$CHANGED" = "$EXPECT" ] || { echo "the changed functions are not exactly the seven edited ones:"; echo "$CHANGED"; exit 1; }
for sig in "${!LIVE[@]}"; do grep -Fq "$sig ${LIVE[$sig]}" "$W/0.fn" || { echo "$sig was not at its live md5 before"; exit 1; }; done
! grep -q '@@MD5_' $M || { echo "a placeholder md5 is left in the migration"; exit 1; }
[ -z "$(comm -23 "$W/0.set" "$W/1.set")" ] || { echo "a setting value changed:"; comm -23 "$W/0.set" "$W/1.set"; exit 1; }
[ "$(comm -13 "$W/0.set" "$W/1.set" | sed 's/=.*//')" = "$(printf '%s\n' enrich.course_description_learner_words enrich.course_description_supported_words)" ] || { echo "the new settings are not exactly the two lists:"; comm -13 "$W/0.set" "$W/1.set"; exit 1; }
for f in l4 rd desc l4rows rdrows led; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
echo "applied: only the seven governed function bodies changed (and new helper functions were added); two new lists, no setting value, Layer 4 item, reading, ledger row or description changed"
$P -1 -At -f $M >/dev/null
snap "$W/2"; for f in fn set l4 rd desc l4rows rdrows led; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change (functions, settings, items, readings, ledger, descriptions)"
# a live body that is neither the one this edits nor the one it writes stops the migration and applies nothing
dropdb --if-exists "${DB}_t" >/dev/null 2>&1; createdb -T "${DB}_old" "${DB}_t"
psql -X -q -d "${DB}_t" -c "create or replace function security.course_description_machine_run_v1() returns jsonb language sql as \$\$ select '{}'::jsonb \$\$"
if OUT=$(psql -X -d "${DB}_t" -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1); then echo "the migration applied over a changed live body"; exit 1; fi
grep -qF 'differs from the definition this change replaces' <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(psql -X -d "${DB}_t" -Atc "select to_regprocedure('security.cdesc_recheck_held_v1()') is null")" = t ] || { echo "the refused migration left a function behind"; exit 1; }
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
echo "forward recovery: the held file restores the seven live bodies byte for byte (twice); applying the migration again brings the edits back"

# the scenarios: prelude of the cdesc-machine scenarios (lines 5 to 88), then ours
pre() { sed -n '5,88p' tests/fixtures/cdesc-machine/scenarios.sql; }
for pair in "$DB:new" "${DB}_old:old"; do
  d=${pair%%:*}; mode=${pair##*:}
  createdb -T "$d" "${d}_s" 2>/dev/null || { dropdb --if-exists "${d}_s"; createdb -T "$d" "${d}_s"; }
  { pre; cat $F/scenarios_outcomes.sql; } > "$W/$mode.out.sql"
  OUT=$(psql -X -d "${d}_s" -v ON_ERROR_STOP=1 -f "$W/$mode.out.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
  if [ "$mode" = new ]; then
    if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "outcome scenarios FAILED on the migrated database"; exit 1; fi
    echo "$OUT" | grep -q 'cdt-outcomes: all' || { echo "the outcome scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
    echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /outcomes: /'
  else
    FAILS=$(echo "$OUT" | grep -c 'REGRESSION.*\[FAIL\]' || true); NONREG=$(echo "$OUT" | grep '\[FAIL\]' | grep -vc 'REGRESSION' || true)
    EXPECTED=$(grep -c "expect('REGRESSION" $F/scenarios_outcomes.sql)
    [ "$FAILS" -ge 9 ] || { echo "only $FAILS of $EXPECTED REGRESSION checks fail on the database from before the migration (at least 9 must)"; echo "$OUT" | grep FAIL; exit 1; }
    echo "regression: $FAILS of the $EXPECTED REGRESSION outcome checks fail on the database from before the migration (the others pin behaviour that did not change)"
  fi
  dropdb --if-exists "${d}_s" >/dev/null 2>&1
done
createdb -T "$DB" "${DB}_s"
{ pre; cat $F/scenarios_flow.sql; } > "$W/flow.sql"
OUT=$(psql -X -d "${DB}_s" -v ON_ERROR_STOP=1 -f "$W/flow.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "flow scenarios FAILED"; exit 1; fi
echo "$OUT" | grep -q 'cdt-flow: all' || { echo "the flow scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /flow: /'
dropdb --if-exists "${DB}_s" >/dev/null 2>&1
createdb -T "${DB}_old" "${DB}_s"
{ pre; cat $F/scenarios_flow.sql; } > "$W/flowold.sql"
OUT=$(psql -X -d "${DB}_s" -v oldmode=1 -v ON_ERROR_STOP=1 -f "$W/flowold.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
echo "$OUT" | grep -q 'REGRESSION places.*\[FAIL\]' || { echo "the places regression check did not fail on the database from before the migration"; echo "$OUT" | tail -5; exit 1; }
echo "regression: the places check fails on the database from before the migration (a new reading was held behind declined descriptions)"
dropdb --if-exists "${DB}_s" >/dev/null 2>&1
echo "cdesc-throughput: done"
