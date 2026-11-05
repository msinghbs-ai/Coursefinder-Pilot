#!/usr/bin/env bash
# Guards: Provider Description autonomy mandate §8–11, PostgreSQL 17.6 schema and governed workflow.
# Scratch Docker PostgreSQL ONLY. No production connection variables are accepted.
set -euo pipefail
cd "$(dirname "$0")/../../.."
FX=tests/fixtures/provider-description-autonomy
D=(env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH docker --host=unix:///var/run/docker.sock)
if ! "${D[@]}" inspect pdesc-autonomy-pg >/dev/null 2>&1; then
  "${D[@]}" run -d --name pdesc-autonomy-pg -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1:55434:5432 postgres:17.6 >/dev/null
else
  "${D[@]}" start pdesc-autonomy-pg >/dev/null
fi
for attempt in $(seq 1 30); do
  "${D[@]}" exec pdesc-autonomy-pg pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
P=("${D[@]}" exec -i pdesc-autonomy-pg psql -U postgres -X -v ON_ERROR_STOP=1 -q -d pdesc_autonomy)
"${D[@]}" exec pdesc-autonomy-pg dropdb -U postgres --if-exists pdesc_autonomy
"${D[@]}" exec pdesc-autonomy-pg createdb -U postgres pdesc_autonomy
"${D[@]}" exec pdesc-autonomy-pg psql -U postgres -q -c "alter database pdesc_autonomy set jit=off; alter database pdesc_autonomy set work_mem='7168kB'; alter database pdesc_autonomy set max_parallel_workers_per_gather=1;"
{ echo 'set check_function_bodies=off;'; cat tests/fixtures/p1-provider-descriptions/stubs.sql; } | "${P[@]}"
for f in tests/fixtures/p1-provider-descriptions/live-before/*.sql; do { echo 'set check_function_bodies=off;'; cat "$f"; } | "${P[@]}"; done
{ echo 'set check_function_bodies=off;'; cat supabase/migrations/20261102090000_cf247_p1_provider_descriptions.sql; } | "${P[@]}"
node "$FX/parity.mjs" | "${P[@]}"
"${P[@]}" < "$FX/identity.sql"
"${P[@]}" < "$FX/roles.sql"
"${P[@]}" < "$FX/role-flags.sql"
"${P[@]}" < "$FX/diagnostics.sql"
node "$FX/knowledge-parity.mjs" | "${P[@]}"
node "$FX/registration-parity.mjs" | "${P[@]}"
{ echo 'set check_function_bodies=off;'; for f in "$FX"/live/*.sql; do cat "$f"; echo ';'; done; } | "${P[@]}"
# Remaining live helpers/trigger installation and known unrelated table projections.
"${P[@]}" < "$FX/helpers.sql"
node "$FX/zoho-parity.mjs" | "${P[@]}"
"${P[@]}" < "$FX/lineage.sql"
"${P[@]}" < "$FX/manual-column-guard.sql"
node "$FX/lineage-parity.mjs"
"${P[@]}" < "$FX/triggers.sql"
"${P[@]}" < "$FX/indexes.sql"
"${P[@]}" < "$FX/knowledge-triggers.sql"
"${P[@]}" < "$FX/zoho-triggers.sql"
"${P[@]}" < "$FX/zoho-grants.sql"
node "$FX/load-crlf.mjs"
node "$FX/grants.mjs" | "${P[@]}"
node "$FX/verify-parity.mjs"
# Current main contains the Controller's #872/#874 outcome correction. Reproduce it after historical snapshot parity.
HOTFIX=supabase/migrations/20261104640000_cf247_run_now_outcome_code.sql
[ -f "$HOTFIX" ] || { echo 'Current-main outcome-code correction is required; rebase onto main first' >&2; exit 1; }
{ echo 'set check_function_bodies=off;'; cat "$HOTFIX"; } | "${P[@]}" -1
[ "$("${P[@]}" -Atc "select md5(pg_get_functiondef('security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure))")" = '2640319be221ab00f39e6e767b78a7b3' ] || { echo 'Current-main Run Now outcome signature differs' >&2; exit 1; }
if [ "${PDESC_SETUP_ONLY:-}" = 1 ]; then
  "${P[@]}" < "$FX/seed.sql"
  exit 0
fi
MIG=supabase/migrations/20261106200000_cf247_provider_description_autonomy.sql
[ -f "$MIG" ] || { echo 'Provider autonomy migration missing' >&2; exit 1; }
{ echo 'set check_function_bodies=off;'; cat "$MIG"; } | "${P[@]}" -1
node "$FX/verify-migration.mjs"
"${P[@]}" < "$FX/seed.sql"
"${P[@]}" < "$FX/check.sql"

node --no-warnings "$FX/integration.mjs"
node --no-warnings "$FX/negative.mjs"
node --no-warnings "$FX/claim-policy.mjs"
node --no-warnings "$FX/dispatch-recovery.mjs"
node --no-warnings "$FX/cap-change.mjs"
node --no-warnings "$FX/navigation.mjs"
node --no-warnings "$FX/benchmark.mjs"
