#!/usr/bin/env bash
# Guards: PR #872 complete vertical feature, isolated PostgreSQL only; no Supabase target.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
export RUN_NOW_DB=intake_ui_fixtures RUN_NOW_KEEP=1
bash tests/fixtures/intake-pilot-run-now/run.sh
P=(psql -X -q -v ON_ERROR_STOP=1 -d "$RUN_NOW_DB")
# Rebuild relevant constraints/triggers/grants from the committed authoritative metadata snapshot.
node tests/fixtures/intake-ui/parity.mjs > /tmp/intake-ui-parity.sql
"${P[@]}" -1 -f /tmp/intake-ui-parity.sql
MIG=supabase/migrations/20261105000000_intake_run_validate_bridge.sql
BEFORE=$("${P[@]}" -Atc "select md5(pg_get_functiondef('security.run_now_cohort_create_v1(text,uuid,text,text)'::regprocedure)) || md5(pg_get_functiondef('security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure))")
"${P[@]}" -1 -f "$MIG"
"${P[@]}" -1 -f "$MIG"
AFTER=$("${P[@]}" -Atc "select md5(pg_get_functiondef('security.run_now_cohort_create_v1(text,uuid,text,text)'::regprocedure)) || md5(pg_get_functiondef('security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure))")
[ "$BEFORE" = "$AFTER" ] || { echo 'Shared cohort or Run Now definition changed'; exit 1; }
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
cat tests/fixtures/intake-ui/helpers.sql tests/fixtures/intake-ui/seed.sql tests/fixtures/intake-ui/check.sql tests/fixtures/intake-ui/negative.sql > "$TMP"
"${P[@]}" -f "$TMP"
# Same-key concurrency: hold the facade's request lock, require a fast in-progress response without a new task.
COHORT=$("${P[@]}" -Atc "select v->>'cohort_id' from public.fixture_intake_ui where k='fixed'")
"${P[@]}" -c "begin; select pg_advisory_xact_lock(hashtextextended('intake ui request:'||'$COHORT',0)); select pg_sleep(3); commit" >/dev/null &
HOLDER=$!
sleep 1
R=$("${P[@]}" -Atc "do \$\$begin perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,false); end\$\$; select public.admin_intake_run_now_v1('$COHORT')")
wait "$HOLDER"
[[ "$R" == *'"state": "in_progress"'* ]] || { echo "Duplicate request not held: $R"; exit 1; }
echo 'PASS same-request concurrency refuses a second dispatch before the shared runner'
# Build the 20-course/10-university acceptance dataset and starvation/performance regression.
cat tests/fixtures/intake-ui/helpers.sql tests/fixtures/intake-ui/twenty.sql > "$TMP"
"${P[@]}" -f "$TMP"
cat tests/fixtures/intake-ui/helpers.sql tests/fixtures/intake-ui/outcomes.sql > "$TMP"
"${P[@]}" -f "$TMP"
node tests/fixtures/intake-ui/benchmark.mjs
echo 'PASS production-representative vertical integration SQL; 20-course browser fixture ready'
