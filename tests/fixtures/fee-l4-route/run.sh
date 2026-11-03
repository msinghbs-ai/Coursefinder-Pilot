#!/usr/bin/env bash
# CF-247 IQ-00111 D12 (fee re-check route, migration 20261104180000) on isolated fixtures. Scratch PostgreSQL only (PGHOST/PGUSER). Builds a
# throwaway database: stubs.sql, the live Layer 4 inbox definition (checked against its live md5), workstream A's contract (stub-ops-contract.sql,
# byte for byte), the migration twice (second run changes nothing), fixtures.sql (every case), then the governed paste on its own stub.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${FEE_L4_DB:-cf_fee_l4_route_fixtures}
MIG=$ROOT/supabase/migrations/20261104180000_cf247_fee_admitted_recheck.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
INBOX='security.layer4_inbox_items_v1()'; LIVE=a56bc3313e02ac0611deb5657da95ce0
AFTER=$(grep -F "select pg_temp.edit_once('$INBOX', '$LIVE', '" $MIG | sed -n "s/.*', '$LIVE', '\([0-9a-f]\{32\}\)'.*/\1/p")
trap '[ -n "${FEE_L4_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
$P -d $DB -f stubs.sql
$P -d $DB -c "set check_function_bodies = off" -f live/layer4_inbox_items_v1.def
[ "$(q "select md5(pg_get_functiondef('$INBOX'::regprocedure))")" = $LIVE ] || { echo "loaded inbox differs from live"; exit 1; }
echo "live definition loaded (= live md5)"
$P -d $DB -f stub-ops-contract.sql
q "select security.ops_root_cause_register_v1('fee_reader_hold_bypass', '{\"class\": \"rule\", \"title\": \"as registered by 20261104140000\"}')" >/dev/null
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -qxF "$INBOX: applied" || { echo "the guarded edit did not apply"; exit 1; }
[ "$(q "select md5(pg_get_functiondef('$INBOX'::regprocedure))")" = "$AFTER" ] || { echo "inbox after md5 differs"; exit 1; }
echo "applied: layer4_inbox_items_v1 $LIVE -> $AFTER"
snap() { q "select md5(string_agg(x, '|' order by x)) from (select 'm:' || m::text x from pipeline.ops_remedies m union all select 's:' || s.key || s.value::text from pipeline.platform_toolset_settings s
  union all select 'g:' || g.name from pipeline.component_register g union all select 't:' || tgname from pg_trigger where not tgisinternal
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security') z"; }
S1=$(snap)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
echo "$OUT" | grep -qxF "$INBOX: already applied" || { echo "second run did not report already applied"; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed something"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "cases: $(grep -c "fx.ok(" fixtures.sql)"
