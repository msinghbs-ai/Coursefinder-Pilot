#!/usr/bin/env bash
# Guards: S741 AER matrix machine row rules (Platform Admin 19 Nov 2026 05:42, session S2-BOOST-AER): completion rows read without the English-language clause; course rows linked by
# printed title or printed award, never a stream, two candidates, a twin or a label a person decided has no catalogue course; both switches at 0 restore 18 Nov exactly.
# Real isolated PostgreSQL only (never a Supabase project). Loads the live helper functions and security.aer_matrix_machine_exclusions_v1 copied from the canonical baseline
# (md5 checked against the live definition of 19 Nov 2026), records every case before the change, applies the settings and the exclusions edit of migration 20261119052500 twice,
# and runs scenarios.sql. Every SQL error fails the run. No AI call, no network.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
DB=${S741_DB:-g_aer_matrix_s741}
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
cleanup() { local code=$?; trap - EXIT; [ -n "${S741_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null || code=1; rm -rf "$WORK"; exit "$code"; }
trap cleanup EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
notices() { sed -n 's/^.*\(NOTICE\|ERROR\|WARNING\):  /\1 /p'; }
$P -d $DB -f stubs.sql
$P -d $DB -f live-functions.sql
EXM=$($P -d $DB -Atc "select md5(pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure))")
[ "$EXM" = 51e0eb454501a4b87e419b1125bcf8c3 ] || { echo "exclusions_v1 differs from live: $EXM"; exit 1; }
echo 'before: security.aer_matrix_machine_exclusions_v1 is the live definition of 19 Nov 2026 (md5 checked)'
$P -d $DB -f data.sql
M=$ROOT/supabase/migrations/20261119052500_cf247_s741_aer_matrix_completion_clauses_course_link.sql
# the settings and the exclusions edit of the migration, byte for byte (the check and admit edits and the validation need the live schema: rolled-back live dry run)
{ sed -n '/^-- 1 settings (G2)/,/^-- 2 the edits/p' "$M"; sed -n '/^do \$ex\$$/,/^end \$ex\$;$/p' "$M"; } > "$WORK/part.sql"
grep -q 'on conflict (toolset_key, key) do nothing' "$WORK/part.sql" && grep -q '^end \$ex\$;$' "$WORK/part.sql" || { echo 'could not take the settings and the exclusions edit from the migration'; exit 1; }
$P -d $DB -1 -f "$WORK/part.sql" 2>&1 | notices
AFTER=$($P -d $DB -Atc "select md5(pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure))")
grep -q -- "51e0eb454501a4b87e419b1125bcf8c3 -> $AFTER" "$M" || { echo "the migration header does not record the exclusions after md5 $AFTER"; exit 1; }
OUT=$($P -d $DB -1 -f "$WORK/part.sql" 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -q 'already applied' || { echo 'the second run did not report already applied'; exit 1; }
[ "$($P -d $DB -Atc "select md5(pg_get_functiondef('security.aer_matrix_machine_exclusions_v1(uuid)'::regprocedure))")" = "$AFTER" ] || { echo 'a second run changed the function'; exit 1; }
echo "exclusions edit applied twice (md5 $AFTER); the second run changed nothing"
$P -d $DB -f scenarios.sql 2>&1 | notices | tee "$WORK/out"
! grep -q 'FAIL\|ERROR' "$WORK/out" || { echo 's741 scenarios FAILED'; exit 1; }
grep -q 's741: scenarios finished' "$WORK/out" || { echo 's741 scenarios did not finish'; exit 1; }
echo "PASS count: $(grep -c '^NOTICE PASS' "$WORK/out")"
echo 'AER matrix S741 row rules: all passed'
