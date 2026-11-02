#!/usr/bin/env bash
# IQ-00055 provider description picker within its time-out, on isolated fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database, loads the live definitions (live-before/, read from the live project on
# 3 Nov 2026 09:15-09:20 AEDT) and checks their md5s against the live ones, loads synthetic data and records the OLD definitions' choices
# (data.sql), applies the migration unchanged (its own md5 guards and after-md5 checks run), applies it again (no change), then compares the
# NEW choices with the OLD ones (fixtures.sql). Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${PDESCPERF_DB:-pdesc_picker_perf_fixtures}
FX=tests/fixtures/pdesc-picker-perf
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261103100000_cf247_pdesc_picker_perf.sql
SIGS="array['security.provider_description_stored_v1(uuid)', 'public.svc_provider_description_next(integer)']"
READ="array['security.provider_description_page_v1(uuid,text)', 'security.provider_hosts_v1(uuid)', 'security.provider_page_host_v1(uuid,text)', 'security.provider_description_scope_v1(uuid)', 'security.toolset_setting(text,text)', 'security.pipeline_num_v1(text,numeric)']"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true
createdb "$DB"
[ -n "${PDESCPERF_KEEP:-}" ] || trap 'dropdb --if-exists "$DB" >/dev/null 2>&1 || true' EXIT
PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -f $FX/stubs.sql
for f in $FX/live-before/*.sql; do PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -f "$f"; done
md5s() { $P -d "$DB" -Atc "select string_agg(md5(pg_get_functiondef(f::regprocedure)), ' ' order by o) from unnest($1) with ordinality t(f, o)"; }
BEFORE=$(md5s "$SIGS"); [ "$BEFORE" = "6ddc25869e9865c9aeebf11c819feee2 33d735da514a7d37e2815bbb0073af03" ] || { echo "loaded definitions differ from live: $BEFORE"; exit 1; }
# the definitions read and not edited, as live
R=$(md5s "$READ"); [ "$R" = "f68e0130757c71ec8d8de24eb730da96 000b9c49c899c6d33ec99501ae6194d4 2af79164c5f92d0e6e5aeceb7783e7ee 3f16959316449464576f5d77a951460a 678dbbc416c5188ab99b3526e68b0c4d 09f9b1551daf42b4a0c9795e6f30c6d4" ] || { echo "the read definitions differ from live: $R"; exit 1; }
echo "before (loaded = live): $BEFORE"
$P -d "$DB" -o /dev/null -f $FX/data.sql
PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -1 -o /dev/null -f $MIG
AFTER=$(md5s "$SIGS"); echo "after: $AFTER"
PGOPTIONS='-c check_function_bodies=off' $P -d "$DB" -1 -At -f $MIG | grep -c 'already applied' | grep -qx 2 || { echo "a second run changed something"; exit 1; }
[ "$(md5s "$SIGS")" = "$AFTER" ] || { echo "a second run changed a definition"; exit 1; }
[ "$(md5s "$READ")" = "$R" ] || { echo "the migration changed a definition it only reads"; exit 1; }
echo "second run: already applied, unchanged"
$P -d "$DB" -f $FX/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
