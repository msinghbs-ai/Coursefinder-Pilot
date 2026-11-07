#!/usr/bin/env bash
# Guards: "No unauthorised Layer 4 admission" (Platform Admin P0 mandate 3 Nov 2026 10:44 section 7) and the held_first_admission promise.
# Real isolated PostgreSQL only (production-parity fixture, same capture as ../course-description-parity). Every SQL error fails the run.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
PAR=../course-description-parity
DB=${CDPH_DB:-g_cdph_after}
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
cleanup() { local code=$?; trap - EXIT; [ -n "${CDPH_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
trap cleanup EXIT
node "$ROOT/scripts/prod-parity-capture.mjs" fixture $PAR/manifest-register.json >"$WORK/register.sql"
node "$ROOT/scripts/prod-parity-capture.mjs" fixture $PAR/manifest.json >"$WORK/fixture.sql"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
$P -d "$DB" -c "create schema if not exists extensions; create or replace function extensions.gen_random_uuid() returns uuid language sql as 'select pg_catalog.gen_random_uuid()'" >/dev/null
$P -d "$DB" -f "$WORK/register.sql"
$P -d "$DB" -f "$WORK/fixture.sql"
$P -d "$DB" -f $PAR/settings.sql
$P -d "$DB" -f $PAR/publication.sql
$P -d "$DB" -1 -f $ROOT/supabase/migrations/20261106500000_cf247_course_descriptions_complete.sql 2>&1 | sed -n 's/^.*\(WARNING\|ERROR\):  /\1 /p'
MIG=$ROOT/supabase/migrations/20261107120000_cf247_course_description_promote_held.sql
$P -d "$DB" -1 -f $MIG
$P -d "$DB" -1 -f $MIG
echo 'migration 20261107120000 applied twice without error'
$P -d "$DB" -f scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p' | tee "$WORK/out"
! grep -q 'FAIL\|ERROR' "$WORK/out" || { echo 'promote-held scenarios FAILED'; exit 1; }
grep -q 'promote-held: all' "$WORK/out" || { echo 'promote-held scenarios did not finish'; exit 1; }
echo 'course-description promote-held: all passed'
