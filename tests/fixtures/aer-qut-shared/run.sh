#!/usr/bin/env bash
# Guards: AER QUT course-table matrix route and shared-page rule (Platform Admin directive 8 Nov 2026), G2, G3, "a passing qualification never switches anything on", "nothing is dropped or deleted by an applied migration".
# Real isolated PostgreSQL only (never a Supabase project): PGHOST/PGPORT/PGUSER point at a scratch server. Builds a throwaway database from stubs.sql (tables and helpers as live has them),
# installs the LIVE definition of security.course_entry_shared_page_v1 (taken from migration 20261103070000, md5 checked against live 8 Nov 2026), records the old rule's counts (before.sql),
# applies migrations 20261108030000 and 20261108030100 twice each, runs scenarios.sql, then applies the QUT data step with this fixture's md5 and runs scenarios2.sql.
# Every SQL error fails the run. The throwaway database is dropped at the end (AQS_KEEP=1 keeps it). No AI call, no network.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
DB=${AQS_DB:-g_aer_qut_shared}
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
cleanup() { local code=$?; trap - EXIT; [ -n "${AQS_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
trap cleanup EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
notices() { sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p'; }
$P -d $DB -f stubs.sql
bash live_shared_page.sh "$ROOT" > "$WORK/live_shared.sql"
[ -s "$WORK/live_shared.sql" ] || { echo 'could not extract the live shared-page definition'; exit 1; }
$P -d $DB -f "$WORK/live_shared.sql"
[ "$(md5of 'security.course_entry_shared_page_v1(uuid)')" = cc037bb72a83595406b1246570d1e977 ] || { echo "shared_page_v1 differs from live: $(md5of 'security.course_entry_shared_page_v1(uuid)')"; exit 1; }
echo 'before: security.course_entry_shared_page_v1 is the live definition (md5 checked)'
$P -d $DB -f data.sql
$P -d $DB -f before.sql 2>&1 | notices
echo 'before.sql done'
MA=$ROOT/supabase/migrations/20261108030000_cf247_aer_shared_page_rejected_binding.sql
MB=$ROOT/supabase/migrations/20261108030100_cf247_aer_course_table_matrix_route.sql
$P -d $DB -1 -f $MA 2>&1 | notices
AFTER=$(md5of 'security.course_entry_shared_page_v1(uuid)')
echo "shared_page_v1 md5 after: $AFTER"
SNAP="select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.admin_control_events) || '/' || (select md5(pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure)))"
S1=$($P -d $DB -Atc "$SNAP")
OUT=$($P -d $DB -1 -f $MA 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -q 'already applied' || { echo 'migration A: the second run did not report already applied'; exit 1; }
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo 'migration A: a second run changed something'; exit 1; }
echo 'migration 20261108030000 applied twice; the second run changed nothing'
$P -d $DB -1 -f $MB 2>&1 | notices
SNAP2="select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.admin_control_events) || '/' || (select count(*) from pipeline.aer_matrix_route) || '/' || (select count(*) from pg_trigger where tgname = 'provider_entry_matrix_a_route')"
S2=$($P -d $DB -Atc "$SNAP2")
$P -d $DB -1 -f $MB 2>&1 | notices
[ "$($P -d $DB -Atc "$SNAP2")" = "$S2" ] || { echo 'migration B: a second run changed something'; exit 1; }
echo 'migration 20261108030100 applied twice; the second run changed nothing'
$P -d $DB -f scenarios.sql 2>&1 | notices | tee "$WORK/out"
! grep -q 'FAIL\|ERROR' "$WORK/out" || { echo 'qut-shared scenarios FAILED'; exit 1; }
grep -q 'qut-shared: scenarios finished' "$WORK/out" || { echo 'qut-shared scenarios did not finish'; exit 1; }
echo "PASS count: $(grep -c '^NOTICE PASS' "$WORK/out")"
# second pass: the QUT data step with this fixture's md5 in place of the live one
FMD5=$($P -d $DB -Atc "select md5(string_agg(c.item_id::text || ':' || c.content_hash, ',' order by c.item_id)) from security.aer_matrix_route_candidates_v1('2c4f515c-c146-4e90-ba8a-294130aa1f40') c")
sed "s/e132941111515af718e4822f24275a03/$FMD5/g" $MB > "$WORK/mb_fixture.sql"
grep -q "$FMD5" "$WORK/mb_fixture.sql" || { echo 'md5 substitution failed'; exit 1; }
$P -d $DB -1 -f "$WORK/mb_fixture.sql" 2>&1 | notices | tee "$WORK/apply"
grep -q 'QUT route: 23 course pages mapped' "$WORK/apply" || { echo 'the guarded QUT step did not map 23'; exit 1; }
$P -d $DB -1 -f "$WORK/mb_fixture.sql" 2>&1 | notices | tee "$WORK/apply2"
grep -q 'QUT route: already applied' "$WORK/apply2" || { echo 'the guarded QUT step did not report already applied'; exit 1; }
$P -d $DB -f scenarios2.sql 2>&1 | notices | tee "$WORK/out2"
! grep -q 'FAIL\|ERROR' "$WORK/out2" || { echo 'qut-shared second pass FAILED'; exit 1; }
grep -q 'qut-shared-2: finished' "$WORK/out2" || { echo 'second pass did not finish'; exit 1; }
echo 'AER QUT matrix route and shared-page rule: all passed'
