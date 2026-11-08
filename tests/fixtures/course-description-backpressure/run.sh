#!/usr/bin/env bash
# Guards: Platform Admin directive 8 Nov 2026 14:06 (course descriptions: review packets and capacity, no auto-approval, claim and evidence guards unchanged) and
# the 8 Nov 2026 mandate lane C-DESC ("do not create endless new proposals when no reviewer can decide").
# Real isolated PostgreSQL only (production-parity fixture, same capture as ../course-description-parity). Every SQL error fails the run.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
PAR=../course-description-parity
DB=${CDBP_DB:-g_cdesc_bp}
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
cleanup() { local code=$?; trap - EXIT; [ -n "${CDBP_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
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
$P -d "$DB" -1 -f $ROOT/supabase/migrations/20261107120000_cf247_course_description_promote_held.sql
# stand-ins the fixture does not carry (shapes read from production 8 Nov 2026) and the live definition this migration replaces, captured byte for byte
$P -d "$DB" -f stubs.sql
$P -d "$DB" -f live/security.enrich_course_text_gaps_v1.sql
$P -d "$DB" -At -c "select 'gaps md5 before: ' || md5(pg_get_functiondef('security.enrich_course_text_gaps_v1(text[])'::regprocedure)), 'queue md5 before: ' || md5(pg_get_functiondef('public.admin_course_description_queue(text,jsonb)'::regprocedure))" | tee "$WORK/md5"
grep -q 'gaps md5 before: a6d0da8f6d6fd7d31c6c39c707e2d824' "$WORK/md5" || { echo 'the captured gap-queue definition is not the live one (a6d0da8f...)'; exit 1; }
MIG=$ROOT/supabase/migrations/20261108130000_cf247_cdesc_review_pack_capacity_backpressure.sql
$P -d "$DB" -1 -f $MIG
$P -d "$DB" -1 -f $MIG
echo 'migration 20261108130000 applied twice without error'
$P -d "$DB" -f scenarios.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p' | tee "$WORK/out"
! grep -q 'FAIL\|ERROR' "$WORK/out" || { echo 'cdesc scenarios FAILED'; exit 1; }
grep -q 'cdesc: all' "$WORK/out" || { echo 'cdesc scenarios did not finish'; exit 1; }
echo 'course-description review pack, capacity and back-pressure: all passed'
