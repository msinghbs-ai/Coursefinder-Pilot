#!/usr/bin/env bash
# Guards: F-CDESC cdesc-source-grounded-v1 (Platform Admin 11 Nov 2026, Admin PR #430): migration 20261112170000 edits exactly three course-description function bodies (md5 from live to the stated md5), adds two functions and two settings and
# nothing else, applies twice with no change, stops over a changed live body with nothing applied, restores the three bodies byte for byte from its held recovery (twice) and comes back; and behaves as scenarios.sql says, with every REGRESSION
# check failing on the database from before it. Needs a scratch PostgreSQL 16 or 17 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds on the cdesc-subset harness (which builds on cdesc-throughput, cdesc-machine and
# course-description-backpressure). CSG_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm, whatever the runner's locale
DB=${CSG_DB:-g_cdesc_source_grounded}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
M=supabase/migrations/20261112170000_cf247_cdesc_source_grounded_v1.sql
HELD=supabase/held/cdesc_source_grounded_forward_recovery.sql
F=tests/fixtures/cdesc-source-grounded
q() { psql -X -d "$1" -Atc "$2"; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${CSG_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_sub" "${DB}_t" "${DB}_rf" "${DB}_s"; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
BASE=$(CDS_KEEP=1 CDS_DB=${DB}_sub bash tests/fixtures/cdesc-subset/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the cdesc-subset harness failed"; exit 1; }
for d in ${DB}_sub_old ${DB}_sub_thr ${DB}_sub_thr_old; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done
echo "base: the cdesc-subset harness built the database (production-parity fixture with the cdesc migrations up to 20261110230000)"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true; createdb -T "${DB}_sub" "$DB"
declare -A LIVE=( ['security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)']=0aacac45e2a294a51db82777a9d1bc19
                  ['security.enrich_course_text_gaps_v1(text[])']=66d9dad4eb0d743b804097b1bf9d38d2 ['security.course_description_machine_run_v1()']=42c73e9c0f376150e7778104dfa9830a )
for sig in "${!LIVE[@]}"; do
  [ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the loaded $sig differs from live ${LIVE[$sig]}"; exit 1; }
  grep -qF -- "--   $sig  ${LIVE[$sig]} -> " $M || { echo "the header does not record $sig ${LIVE[$sig]}"; exit 1; }
done
echo "loaded: the three definitions the migration edits = live (body md5, read 12 Nov 2026)"
dropdb --if-exists "${DB}_old" >/dev/null 2>&1; createdb -T "$DB" "${DB}_old"

FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text || '|' || coalesce(used_by, '') from pipeline.platform_toolset_settings order by 1"
snap() { q $DB "$FNS" | sort > "$1.fn"; q $DB "$SET" | sort > "$1.set"; for t in pipeline.layer4_review_items pipeline.field_enrich_items catalogue.courses; do q $DB "select md5(string_agg(x::text, '|' order by x::text)) from $t x"; done > "$1.rows"; }
snap "$W/0"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null
snap "$W/1"
CHANGED=$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ .*//' | sort)
[ "$CHANGED" = "$(printf '%s\n' "${!LIVE[@]}" | sort)" ] || { echo "the changed functions are not exactly the three edited ones:"; echo "$CHANGED"; exit 1; }
for sig in "${!LIVE[@]}"; do A=$(grep -oP -- "--   \Q$sig\E  ${LIVE[$sig]} -> \K[0-9a-f]{32}" $M); grep -qF "$sig $A" "$W/1.fn" || { echo "$sig is not at the stated md5 $A"; exit 1; }; done
NEW=$(comm -13 <(sed 's/ .*//' "$W/0.fn" | sort -u) <(sed 's/ .*//' "$W/1.fn" | sort -u) | tr '\n' ' ')
[ "$NEW" = "security.cdesc_prompt_supersede_v1() security.cdesc_prompt_version_v1() " ] || { echo "unexpected new functions: $NEW"; exit 1; }
SADD=$(comm -13 <(sed 's/=.*//' "$W/0.set") <(sed 's/=.*//' "$W/1.set") | tr '\n' ' ')
[ "$SADD" = "enrich.course_description_copy_run_words enrich.course_description_generic_phrases " ] || { echo "unexpected settings added: $SADD"; exit 1; }
SCHG=$(comm -23 "$W/0.set" "$W/1.set" | sed 's/=.*//' | tr '\n' ' ')
[ -z "$SCHG" ] || [ "$SCHG" = "enrich.course_description_reask_max " ] || { echo "a setting changed: $SCHG"; exit 1; }
cmp -s "$W/0.rows" "$W/1.rows" || { echo "the migration changed Layer 4 items, readings or courses"; exit 1; }
echo "applied: only the three governed bodies changed (to the stated md5), two functions and two settings were added (reask_max marked retiring), no Layer 4 item, reading or course changed"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null; snap "$W/2"
for f in fn set rows; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change"
dropdb --if-exists "${DB}_t" >/dev/null 2>&1; createdb -T "${DB}_old" "${DB}_t"
psql -X -q -d "${DB}_t" -c "create or replace function security.course_description_machine_run_v1() returns jsonb language sql as \$\$ select '{}'::jsonb \$\$"
if OUT=$(psql -X -d "${DB}_t" -q -At -v ON_ERROR_STOP=1 -1 -f $M 2>&1); then echo "the migration applied over a changed live body"; exit 1; fi
grep -qF 'differs from the definition this change replaces' <<<"$OUT" || { echo "the refusal is not the expected one: $OUT" | tail -3; exit 1; }
[ "$(q ${DB}_t "select to_regprocedure('security.cdesc_prompt_supersede_v1()') is null and md5(prosrc) = '${LIVE['security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)']}' from pg_proc where oid = 'security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)'::regprocedure")" = t ] || { echo "the refused migration left something behind"; exit 1; }
dropdb --if-exists "${DB}_t" >/dev/null 2>&1
echo "refused: a live body that differs from the guarded one stops the migration and nothing is applied"
createdb -T "$DB" "${DB}_rf"
psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null; psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -f $HELD >/dev/null
for sig in "${!LIVE[@]}"; do [ "$(q ${DB}_rf "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" = "${LIVE[$sig]}" ] || { echo "the forward recovery did not restore $sig"; exit 1; }; done
psql -X -d "${DB}_rf" -q -v ON_ERROR_STOP=1 -1 -f $M >/dev/null
for sig in "${!LIVE[@]}"; do grep -Fq "$sig $(q ${DB}_rf "select md5(prosrc) from pg_proc where oid = '$sig'::regprocedure")" "$W/1.fn" || { echo "the migration did not bring back $sig"; exit 1; }; done
dropdb --if-exists "${DB}_rf" >/dev/null 2>&1
echo "forward recovery: the held file restores the three live bodies byte for byte (twice); applying the migration again brings the edits back"

{ sed -n '5,88p' tests/fixtures/cdesc-machine/scenarios.sql; cat $F/scenarios.sql; } > "$W/s.sql"
for pair in "$DB:new" "${DB}_old:old"; do
  d=${pair%%:*}; mode=${pair##*:}
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1; createdb -T "$d" "${DB}_s"
  OUT=$(psql -X -d "${DB}_s" -v ON_ERROR_STOP=0 -f "$W/s.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
  if [ "$mode" = new ]; then
    if echo "$OUT" | grep -E 'FAIL|^ERROR'; then echo "scenarios FAILED on the migrated database"; exit 1; fi
    echo "$OUT" | grep -q 'cdsg: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
    echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /source-grounded: /'
  else
    FAILS=$(echo "$OUT" | grep -c 'REGRESSION.*\[FAIL\]' || true); EXPECTED=$(grep -c "expect('REGRESSION" $F/scenarios.sql)
    [ "$FAILS" = "$EXPECTED" ] || { echo "only $FAILS of $EXPECTED REGRESSION checks fail on the database from before the migration"; echo "$OUT" | grep REGRESSION; exit 1; }
    echo "regression: $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"
  fi
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1
done
echo "cdesc-source-grounded: done"
