#!/usr/bin/env bash
# Guards: "Do not spend Firecrawl credits" / AER source discovery without paid acquisition (Platform Admin mandate 7 Nov 2026 21:57), G1, G2, "a passing qualification never switches anything on".
# Real isolated PostgreSQL only (never a Supabase project): PGHOST/PGPORT/PGUSER point at a scratch server. Builds a throwaway database from stubs.sql (the tables and
# helpers the migration reads, as live has them), loads the LIVE definitions of security.entry_matrix_attach_v1 and entry_matrix_enabled_v1 (live/, each checked against
# the live md5 read 7 Nov 2026), reproduces the circular gate on them (before.sql), applies migration 20261107150000 twice, then runs scenarios.sql.
# Every SQL error fails the run. The throwaway database is dropped at the end (ASSD_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${ASSD_DB:-g_aer_stored_source_discovery}
[[ "$DB" =~ ^g_[a-z0-9_]+$ ]] || { echo 'refused: scratch database name must begin g_' >&2; exit 1; }
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres <<'SQL'
do $g$ begin
  if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then raise exception 'local database only'; end if;
  if exists (select 1 from pg_namespace where nspname = 'supabase_migrations') and exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise exception 'refusing a Supabase project database'; end if;
end $g$;
SQL
WORK=$(mktemp -d)
cleanup() { local code=$?; trap - EXIT; [ -n "${ASSD_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
trap cleanup EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d $DB -f stubs.sql
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
[ "$(md5of 'security.entry_matrix_attach_v1()')" = b34e95379b61ef98a65837686825857f ] || { echo "attach_v1 differs from live: $(md5of 'security.entry_matrix_attach_v1()')"; exit 1; }
[ "$(md5of 'security.entry_matrix_enabled_v1(uuid)')" = 582a5024ffeca0ac3c5446a903b39b3f ] || { echo "enabled_v1 differs from live: $(md5of 'security.entry_matrix_enabled_v1(uuid)')"; exit 1; }
echo 'before: entry_matrix_attach_v1 and entry_matrix_enabled_v1 are the live definitions (md5 checked)'
$P -d $DB -f data.sql
$P -d $DB -f before.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
MIG=$ROOT/supabase/migrations/20261107150000_cf247_aer_source_stored_discovery.sql
$P -d $DB -1 -f $MIG 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
SNAP="select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from pipeline.automation_catalogue) || '/' || (select count(*) from pipeline.component_register)"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -q 'already applied' || { echo 'the second run did not report already applied'; exit 1; }
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo 'a second run added rows'; exit 1; }
echo 'migration 20261107150000 applied twice; the second run changed nothing'
# 7 Nov 2026 speed fix (the first live measure: 33 s for three providers): same behaviour, applied twice, the scenarios below run on it
MIG2=$ROOT/supabase/migrations/20261107160000_cf247_aer_stored_find_speed.sql
$P -d $DB -1 -f $MIG2 && $P -d $DB -1 -f $MIG2
echo 'migration 20261107160000 (speed) applied twice'
[ "$(md5of 'security.entry_matrix_enabled_v1(uuid)')" = 582a5024ffeca0ac3c5446a903b39b3f ] || { echo 'enabled_v1 was changed'; exit 1; }
$P -d $DB -f scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p' | tee "$WORK/out"
! grep -q 'FAIL\|ERROR' "$WORK/out" || { echo 'stored-source scenarios FAILED'; exit 1; }
grep -q 'stored-source: all passed' "$WORK/out" || { echo 'stored-source scenarios did not finish'; exit 1; }
echo 'AER stored-source discovery: all passed'
