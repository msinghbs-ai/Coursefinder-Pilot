#!/usr/bin/env bash
# Guards: F-CDESC a recovered description keeps its opening sentence (read of recovered descriptions, 13 Nov 2026): migration 20261113320000 edits exactly one body (the subset plan, md5 from live to the stated md5), adds no function, changes no setting,
# no reading, no Layer 4 item and no course; applies twice with no change; stops over a changed live body with nothing applied; its held recovery restores the body (twice) and the migration comes back;
# and behaves as scenarios.sql says, with every REGRESSION check failing on the database from before it. Scratch PostgreSQL only. Builds on cdesc-shorten. COP_KEEP=1 keeps the databases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
export LC_ALL=C # fixed: one byte order for sort and comm
DB=${COP_DB:-g_cdesc_opening}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
M=supabase/migrations/20261113320000_cf247_cdesc_opening_sentence_kept.sql
HELD=supabase/held/cdesc_opening_kept_forward_recovery.sql
F=tests/fixtures/cdesc-opening
SIG='security.cdesc_subset_plan_v1(uuid,uuid,jsonb)'; BEFORE=2fd1a050b0e70c0ae9298a0d7419b075; AFTER=89e86ee2fe13eb582d7cac0f1ed4f7fa
q() { psql -X -d "$1" -Atc "$2"; }
W=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; rm -rf "$W"; if [ -z "${COP_KEEP:-}" ]; then for d in "$DB" "${DB}_old" "${DB}_crt" "${DB}_t" "${DB}_rf" "${DB}_s"; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; fi; exit "$code"; }
trap cleanup EXIT
BASE=$(CRS_KEEP=1 CRS_DB=${DB}_crt bash tests/fixtures/cdesc-shorten/run.sh 2>&1) || { echo "$BASE" | tail -15; echo "the cdesc-shorten harness failed"; exit 1; }
for d in ${DB}_crt_old ${DB}_crt_crt ${DB}_crt_t ${DB}_crt_rf ${DB}_crt_s; do dropdb --if-exists "$d" >/dev/null 2>&1 || true; done
echo "base: the cdesc-shorten harness built the database (migrations up to 20261113310000)"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true; createdb -T "${DB}_crt" "$DB"
[ "$(q $DB "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $BEFORE ] || { echo "the loaded plan is not the live body"; exit 1; }
grep -qF -- "security.cdesc_subset_plan_v1  $BEFORE -> $AFTER" $M || { echo "the header does not record the edit"; exit 1; }
dropdb --if-exists "${DB}_old" >/dev/null 2>&1; createdb -T "$DB" "${DB}_old"
FNS="select p.oid::regprocedure::text || ' ' || md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public', 'api', 'pipeline', 'catalogue') and p.prokind = 'f' order by 1"
SET="select key || '=' || value::text from pipeline.platform_toolset_settings order by 1"
RS="select id || ' ' || state || ' ' || coalesce(reason, '') || ' ' || md5(coalesce(value::text, '')) from pipeline.field_enrich_items order by id"
snap() { q $DB "$FNS" | sort > "$1.fn"; q $DB "$SET" | sort > "$1.set"; q $DB "$RS" > "$1.items"; q $DB "select jobname || ' ' || schedule from cron.job order by 1" > "$1.cron"; for t in pipeline.layer4_review_items catalogue.courses; do q $DB "select md5(string_agg(x::text, '|' order by x::text)) from $t x"; done > "$1.rows"; }
snap "$W/0"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null 2>&1
snap "$W/1"
[ "$(comm -23 "$W/0.fn" "$W/1.fn" | sed 's/ .*//' | tr '\n' ' ')" = "$SIG " ] && grep -qF "$SIG $AFTER" "$W/1.fn" || { echo "the changed functions are not exactly the plan at the stated md5"; comm -3 "$W/0.fn" "$W/1.fn"; exit 1; }
[ -z "$(comm -13 <(sed 's/ .*//' "$W/0.fn" | sort -u) <(sed 's/ .*//' "$W/1.fn" | sort -u))" ] || { echo "unexpected functions added"; exit 1; }
for f in set items rows cron; do cmp -s "$W/0.$f" "$W/1.$f" || { echo "the migration changed $f"; exit 1; }; done
echo "applied: only the plan changed (to the stated md5) and no function was added; no setting, reading, Layer 4 item, course or job changed (so the check, the wording policy and the machine rule are what they were)"
psql -X -q -v ON_ERROR_STOP=1 -d $DB -1 -At -f $M >/dev/null 2>&1; snap "$W/2"
for f in fn set items rows cron; do cmp -s "$W/1.$f" "$W/2.$f" || { echo "the second run changed $f"; exit 1; }; done
echo "applied again: no change"
createdb -T "${DB}_old" "${DB}_t"
psql -X -q -d "${DB}_t" -c "do \$\$ declare d text := pg_get_functiondef('$SIG'::regprocedure); begin execute replace(d, 'remainder_below_minimum', 'remainder_below_minimum_x'); end \$\$"
q "${DB}_t" "$FNS" | sort > "$W/t0.fn"
if psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_t" -1 -f $M >/dev/null 2>"$W/t.err"; then echo "the migration applied over a changed live body"; exit 1; fi
grep -q 'differs from the definition this change replaces' "$W/t.err" || { echo "the refusal does not name the changed body"; cat "$W/t.err"; exit 1; }
q "${DB}_t" "$FNS" | sort > "$W/t1.fn"; cmp -s "$W/t0.fn" "$W/t1.fn" || { echo "a refused run left something behind"; exit 1; }
dropdb "${DB}_t"
echo "refused: over a changed plan body the migration stops and leaves nothing"
createdb -T "$DB" "${DB}_rf"
for i in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_rf" -1 -f $HELD >/dev/null 2>&1 || { echo "the held recovery failed (run $i)"; exit 1; }; done
[ "$(q "${DB}_rf" "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $BEFORE ] || { echo "the held recovery did not restore the body"; exit 1; }
psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_rf" -1 -f $M >/dev/null 2>&1 && [ "$(q "${DB}_rf" "select md5(prosrc) from pg_proc where oid = '$SIG'::regprocedure")" = $AFTER ] || { echo "the migration did not come back after the recovery"; exit 1; }
dropdb "${DB}_rf"
echo "forward recovery: the held file restores the plan body (twice); the migration then applies again"
pre() { sed -n '5,88p' tests/fixtures/cdesc-machine/scenarios.sql; sed -n '5,75p' tests/fixtures/cdesc-subset/scenarios.sql; }
for pair in "$DB:new" "${DB}_old:old"; do
  d=${pair%%:*}; mode=${pair##*:}
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1; createdb -T "$d" "${DB}_s"
  { pre; cat $F/scenarios.sql; } > "$W/$mode.sql"
  OUT=$(psql -X -d "${DB}_s" -v ON_ERROR_STOP=1 -f "$W/$mode.sql" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p') || true
  if [ "$mode" = new ]; then
    if echo "$OUT" | grep -E 'FAIL|ERROR'; then echo "scenarios FAILED on the migrated database"; exit 1; fi
    echo "$OUT" | grep -q 'cop: all' || { echo "the scenarios did not finish"; echo "$OUT" | tail -5; exit 1; }
    echo "$OUT" | grep -E '\[pass\]' | sed 's/^NOTICE /opening: /'
  else
    FAILS=$(echo "$OUT" | grep -c 'REGRESSION.*\[FAIL\]' || true); EXPECTED=$(grep -c "expect('REGRESSION" $F/scenarios.sql)
    [ "$FAILS" = "$EXPECTED" ] || { echo "only $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"; echo "$OUT" | grep -E 'REGRESSION|ERROR'; exit 1; }
    echo "regression: $FAILS of the $EXPECTED REGRESSION checks fail on the database from before the migration"
  fi
  dropdb --if-exists "${DB}_s" >/dev/null 2>&1
done
echo "cdesc-opening: done"
