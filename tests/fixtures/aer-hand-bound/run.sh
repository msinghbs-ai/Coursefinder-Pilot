#!/usr/bin/env bash
# Guards: S670 AER shared-page rule for hand-bound courses (Platform Admin 18 Nov 2026 17:52), G2, G3, "nothing is dropped or deleted by an applied migration".
# Real isolated PostgreSQL only (never a Supabase project): PGHOST/PGPORT/PGUSER point at a scratch server. Builds a throwaway database from the aer-qut-shared stubs and data,
# installs security.course_entry_shared_page_v1 as migration 20261103070000 created it, applies migration 20261108030000 (checked against the live md5 read 18 Nov 2026),
# adds this fixture's courses, applies migration 20261118220000 twice and runs scenarios.sql. Every SQL error fails the run. No AI call, no network.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
Q=$ROOT/tests/fixtures/aer-qut-shared
DB=${AHB_DB:-g_aer_hand_bound}
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
cleanup() { local code=$?; trap - EXIT; [ -n "${AHB_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
trap cleanup EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
notices() { sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p'; }
$P -d $DB -f $Q/stubs.sql
bash $Q/live_shared_page.sh "$ROOT" > "$WORK/live_shared.sql"
$P -d $DB -f "$WORK/live_shared.sql"
$P -d $DB -f $Q/data.sql
$P -d $DB -1 -f $ROOT/supabase/migrations/20261108030000_cf247_aer_shared_page_rejected_binding.sql 2>&1 | notices
[ "$(md5of 'security.course_entry_shared_page_v1(uuid)')" = 7b43d0c61419ec08ea2fbb2889b1f444 ] || { echo "shared_page_v1 differs from live: $(md5of 'security.course_entry_shared_page_v1(uuid)')"; exit 1; }
echo 'before: security.course_entry_shared_page_v1 is the live definition of 18 Nov 2026 (md5 checked)'
$P -d $DB -f data.sql
M=$ROOT/supabase/migrations/20261118220000_cf247_aer_shared_page_hand_bound.sql
$P -d $DB -1 -f $M 2>&1 | notices
AFTER=$(md5of 'security.course_entry_shared_page_v1(uuid)')
echo "shared_page_v1 md5 after: $AFTER"
grep -q -- "7b43d0c61419ec08ea2fbb2889b1f444 -> $AFTER" $M || { echo "the migration header does not record the after md5 $AFTER"; exit 1; }
SNAP="select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.admin_control_events) || '/' || (select md5(string_agg(key || value::text, ',' order by key)) from pipeline.platform_toolset_settings) || '/' || (select md5(pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure)))"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -f $M 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -q 'already applied' || { echo 'the second run did not report already applied'; exit 1; }
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo 'a second run changed something'; exit 1; }
echo 'migration 20261118220000 applied twice; the second run changed nothing'
$P -d $DB -f scenarios.sql 2>&1 | notices | tee "$WORK/out"
! grep -q 'FAIL\|ERROR' "$WORK/out" || { echo 'hand-bound scenarios FAILED'; exit 1; }
grep -q 'hand-bound: scenarios finished' "$WORK/out" || { echo 'hand-bound scenarios did not finish'; exit 1; }
echo "PASS count: $(grep -c '^NOTICE PASS' "$WORK/out")"
echo 'AER shared-page rule for hand-bound courses: all passed'
