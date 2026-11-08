#!/usr/bin/env bash
# Guards: Platform Admin 8 Nov 2026 14:06 (English gap recovery and IQ-00072): round trip of the three ENG migrations on isolated local PostgreSQL (never a Supabase project).
#   A the English path fixture (tests/fixtures/english-requirements/run.sh, production-manifest parity, migration 20261106550000), then funnel-harness.sql, migrations 20261108120000 and 20261108121000
#     (each run twice: the second says "already applied", nothing is added twice), then funnel-tests.sql;
#   B a small database with the LIVE security.enrich_plan_v1 (live/, md5 checked), plan-harness.sql, migration 20261108122000 twice, then plan-tests.sql.
# PGHOST/PGPORT/PGUSER point at the scratch PostgreSQL. Databases are dropped at the end (ENG_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
FX=tests/fixtures/eng-gap-recovery MIG=supabase/migrations
DBA=${ENG_DB_A:-g_eng_gap_a} DBB=${ENG_DB_B:-g_eng_gap_b}
P="psql -X -q -v ON_ERROR_STOP=1"; T=$(mktemp -d)
cleanup() { [ -n "${ENG_KEEP:-}" ] || { dropdb --if-exists "$DBA" 2>/dev/null; dropdb --if-exists "$DBB" 2>/dev/null; }; rm -rf "$T"; }
trap cleanup EXIT
fail() { echo "FAIL $*"; exit 1; }
# A
EN_DB=$DBA EN_KEEP=1 bash tests/fixtures/english-requirements/run.sh > "$T/en.out" 2>&1 || { cat "$T/en.out" >&2; fail 'the English path fixture did not build'; }
$P -d "$DBA" -f $FX/funnel-harness.sql
for m in 20261108120000_cf247_eng_gap_funnel 20261108121000_cf247_eng_default_after_withdrawn_reading; do
  first=$($P -At -d "$DBA" -f $MIG/$m.sql 2>&1 | grep -v NOTICE || true)
  second=$($P -At -d "$DBA" -f $MIG/$m.sql 2>&1 | grep -v NOTICE || true)
  case "$m" in *withdrawn*) grep -q ': applied' <<<"$first" || fail "$m did not apply: $first"; grep -q 'already applied' <<<"$second" || fail "$m second run: $second";; esac
  echo "PASS $m applies, and a second run adds nothing"
done
$P -X -d "$DBA" -f $FX/funnel-tests.sql > "$T/a.out" 2>&1 || { cat "$T/a.out" >&2; fail 'a funnel scenario failed'; }
echo "PASS scenario-count funnel-tests.sql: $(grep -c 'NOTICE:  PASS' "$T/a.out")"
# B
dropdb --if-exists "$DBB"; createdb "$DBB"
$P -d "$DBB" -f $FX/plan-harness.sql
$P -d "$DBB" -c "set check_function_bodies = off" -f $FX/live/security.enrich_plan_v1.sql
[ "$($P -At -d "$DBB" -c "select md5(pg_get_functiondef('security.enrich_plan_v1(uuid)'::regprocedure))")" = 774c061974916b878f7762e55de07bb6 ] || fail 'the loaded security.enrich_plan_v1 differs from live (774c0619...)'
echo 'PASS the loaded security.enrich_plan_v1 carries its live md5 (8 Nov 2026)'
first=$($P -At -d "$DBB" -f $MIG/20261108122000_cf247_plan_stalled_onboarding_hold.sql 2>&1 | grep -v NOTICE || true)
second=$($P -At -d "$DBB" -f $MIG/20261108122000_cf247_plan_stalled_onboarding_hold.sql 2>&1 | grep -v NOTICE || true)
grep -q ': applied' <<<"$first" || fail "plan migration did not apply: $first"; grep -q 'already applied' <<<"$second" || fail "plan migration second run: $second"
echo 'PASS 20261108122000 applies under the live md5, and a second run adds nothing'
$P -X -d "$DBB" -f $FX/plan-tests.sql > "$T/b.out" 2>&1 || { cat "$T/b.out" >&2; fail 'a plan scenario failed'; }
echo "PASS scenario-count plan-tests.sql: $(grep -c 'NOTICE:  PASS' "$T/b.out")"
echo 'eng-gap-recovery fixture round trip: passed'
