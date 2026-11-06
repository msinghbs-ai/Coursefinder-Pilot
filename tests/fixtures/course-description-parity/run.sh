#!/usr/bin/env bash
# Guards: Platform Admin 6 Nov 2026 08:12, 09:44 sections 2/4 and decision 19:14 section 8.
# Real isolated PostgreSQL only. Every producer, fixture, parity and scenario error
# must fail the execution. No successful tee/grep may hide a failed SQL command.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${CDESC_DB:-g_cdesc_baseline}
DB2=${CDESC_DB2:-g_cdesc_after}
[[ "$DB" =~ ^g_[a-z0-9_]+$ && "$DB2" =~ ^g_[a-z0-9_]+$ && "$DB" != "$DB2" ]] || { echo 'refused: distinct scratch database names beginning g_ required' >&2; exit 1; }
P="psql -v ON_ERROR_STOP=1 -q -X"
# Check the server before any scratch DDL; the generated fixtures repeat this guard.
$P -d postgres <<'SQL'
do $g$ begin
  if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
    raise exception 'prod-parity fixtures are for a local database only'; end if;
  if exists (select 1 from pg_namespace where nspname = 'supabase_migrations')
     and exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    raise exception 'refusing a Supabase project database'; end if;
end $g$;
SQL
WORK=$(mktemp -d)
cleanup() {
  local code=$?
  trap - EXIT
  if [ -z "${CDESC_KEEP:-}" ]; then
    $P -d postgres -c "drop database if exists $DB" -c "drop database if exists $DB2" >/dev/null || code=1
  fi
  rm -rf "$WORK"
  exit "$code"
}
trap cleanup EXIT
# Separate production of SQL from execution: neither failure can be hidden by a
# downstream consumer. A bad manifest never progresses to a parity PASS message.
node "$ROOT/scripts/prod-parity-capture.mjs" fixture manifest-register.json >"$WORK/register.sql"
node "$ROOT/scripts/prod-parity-capture.mjs" fixture manifest.json >"$WORK/fixture.sql"
node "$ROOT/scripts/prod-parity-capture.mjs" check-sql manifest.json >"$WORK/check.sql"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
EXT="create schema if not exists extensions; create or replace function extensions.gen_random_uuid() returns uuid language sql as 'select pg_catalog.gen_random_uuid()'"
$P -d "$DB" -c "$EXT" >/dev/null
$P -d "$DB" -f "$WORK/register.sql"
$P -d "$DB" -f "$WORK/fixture.sql"
$P -d "$DB" -At -f "$WORK/check.sql" >"$WORK/diff"
SERVER_VERSION=$($P -d "$DB" -Atc 'show server_version_num')
# Only PG16 lacks the PG17 MAINTAIN privilege. All other differences fail closed.
if (( SERVER_VERSION < 170000 )); then
  DIFF=$(awk '!/^grant[|].*MAINTAIN/' "$WORK/diff")
else
  DIFF=$(cat "$WORK/diff")
fi
[ -z "$DIFF" ] || { echo 'fixture differs from the production manifest:'; echo "$DIFF"; exit 1; }
declare -A LIVE=(
  ["security.course_description_check_v1(uuid,jsonb)"]=ff3d6dd7b0f88c85b1fdff6c8a8cd86b
  ["security.enrich_course_text_record_v1(bigint,jsonb)"]=b47c00b19bc6eaa36828dbe4d2371501
  ["security.course_description_trusted_v1(uuid)"]=3f056fa4495963ec1d3bca61bfe0642d
  ["security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)"]=ba97236f3010e248bac44a0a7c09611a
  ["security.course_description_release_held_v1(uuid)"]=dd4b178afcd26b696d70710038e34f1c
  ["security.course_description_review_trg_v1()"]=d143eba24f5896f36a3a93e8e5c075aa
)
for s in "${!LIVE[@]}"; do
  got=$($P -d "$DB" -Atc "select md5(pg_get_functiondef('$s'::regprocedure))")
  [ "$got" = "${LIVE[$s]}" ] || { echo "loaded $s is $got, not live ${LIVE[$s]}"; exit 1; }
done
echo "parity: fixture equals the production manifest; ${#LIVE[@]} live md5s confirmed"
$P -d "$DB" -f settings.sql
for f in baseline.sql held-real.sql; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
  $P -d "$DB" -1 -f "$f" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
done
echo 'course-description baseline (before the migration): all passed'
$P -d postgres -c "drop database if exists $DB2" -c "create database $DB2" >/dev/null
$P -d "$DB2" -c "$EXT" >/dev/null
$P -d "$DB2" -f "$WORK/register.sql"
$P -d "$DB2" -f "$WORK/fixture.sql"
$P -d "$DB2" -f settings.sql
# Reproduce the existing consumer visibility view before the new metric is created.
$P -d "$DB2" -f publication.sql
MIG=$ROOT/supabase/migrations/20261106500000_cf247_course_descriptions_complete.sql
$P -d "$DB2" -1 -f $MIG 2>&1 | sed -n 's/^.*\(WARNING\|ERROR\):  /\1 /p'
$P -d "$DB2" -1 -f $MIG 2>&1 | sed -n 's/^.*\(WARNING\|ERROR\):  /\1 /p'
echo 'migration 20261106500000 applied twice without error'
for f in baseline.sql held-real.sql; do
  $P -d "$DB2" -1 -v after=1 -f "$f" 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
done
echo 'course-description baseline (after the migration): identical outcomes'
$P -d "$DB2" -f queue.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p'
echo 'course-description queue, reconciliation and sample tests: all passed'
