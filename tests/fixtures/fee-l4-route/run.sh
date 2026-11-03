#!/usr/bin/env bash
# CF-247 IQ-00111 D12 (fee re-check route, migration 20261104270000) on isolated fixtures. Scratch PostgreSQL only (PGHOST/PGUSER). Builds a
# throwaway database: stubs.sql, the live Layer 4 inbox definition (checked against its live md5) and the Layer 4 owner's 20261104150000 edit of it
# (l4-inbox-4fc05d14.sql; the version the cards render through), workstream A's contract (stub-ops-contract.sql, byte for byte), the migration
# twice (second run changes nothing; the inbox is never edited by it), fixtures.sql (every case), then the governed paste on its own stub.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=../../..
DB=${FEE_L4_DB:-cf_fee_l4_route_fixtures}
MIG=$ROOT/supabase/migrations/20261104270000_cf247_fee_admitted_recheck.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
INBOX='security.layer4_inbox_items_v1()'; LIVE=a56bc3313e02ac0611deb5657da95ce0; L4=4fc05d14f4ba49335ff90496a20f582d
trap '[ -n "${FEE_L4_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
$P -d $DB -f stubs.sql
$P -d $DB -c "set check_function_bodies = off" -f live/layer4_inbox_items_v1.def
[ "$(q "select md5(pg_get_functiondef('$INBOX'::regprocedure))")" = $LIVE ] || { echo "loaded inbox differs from live"; exit 1; }
echo "live definition loaded (= live md5)"
$P -d $DB -At -f l4-inbox-4fc05d14.sql >/dev/null
[ "$(q "select md5(pg_get_functiondef('$INBOX'::regprocedure))")" = $L4 ] || { echo "the Layer 4 owner's inbox edit did not give 4fc05d14"; exit 1; }
echo "Layer 4 inbox as released by 20261104150000 (= $L4)"
$P -d $DB -f stub-ops-contract.sql
q "select security.ops_root_cause_register_v1('fee_reader_hold_bypass', '{\"class\": \"rule\", \"title\": \"as registered by 20261104140000\"}')" >/dev/null
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(q "select md5(pg_get_functiondef('$INBOX'::regprocedure))")" = $L4 ] || { echo "the migration changed the Layer 4 inbox"; exit 1; }
echo "applied; the Layer 4 inbox is unchanged ($L4)"
snap() { q "select md5(string_agg(x, '|' order by x)) from (select 'm:' || m::text x from pipeline.ops_remedies m union all select 's:' || s.key || s.value::text from pipeline.platform_toolset_settings s
  union all select 'g:' || g.name from pipeline.component_register g union all select 't:' || tgname from pg_trigger where not tgisinternal
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security') z"; }
S1=$(snap)
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed something"; exit 1; }
echo "applied twice: the second run changed nothing"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "cases: $(grep -c "fx.ok(" fixtures.sql)"
# the governed paste, on its own database: the 5 live ids with stand-in notes (the notes md5 guard is rewritten to the stand-ins only)
PD=${DB}_paste
$P -d postgres -c "drop database if exists $PD" -c "create database $PD" >/dev/null 2>&1
$P -d $PD -f stubs.sql; $P -d $PD -c "set check_function_bodies = off" -f live/layer4_inbox_items_v1.def; $P -d $PD -At -f l4-inbox-4fc05d14.sql >/dev/null; $P -d $PD -f stub-ops-contract.sql
$P -d $PD -Atc "select security.ops_root_cause_register_v1('fee_reader_hold_bypass', '{\"class\": \"rule\", \"title\": \"as registered by 20261104140000\"}')" >/dev/null
$P -d $PD -1 -q -o /dev/null -f $MIG
for id in 04b4c75e-f020-4d17-a9c4-3310156d8b76 0f7d0c66-05d9-413d-bdde-15d08ac2d30f 51ebae9d-67d3-4221-9cb3-1308260f4801 5d897b64-1f04-4171-8321-228ff54f2388 a4f9c399-8194-4b58-bcec-62df728c98af; do
  $P -d $PD -c "insert into catalogue.course_fees(id, course_id, fee_type, amount, notes) values ('$id', gen_random_uuid(), 'provider_current_tuition', 10000, 'AI fee reader (https://x/$id)')"; done
G=$($P -d $PD -Atc "select md5(string_agg(f.id::text || ':' || md5(f.notes), ',' order by f.id)) from catalogue.course_fees f")
tmp=$(mktemp); sed "s/ccc44c30f3bf04340cdc7a2ec11223b2/$G/g" $ROOT/docs/paste/PASTE-20261104-fee-admitted-recheck.sql > $tmp
$P -d $PD -f $tmp
echo "paste: raised=$($P -d $PD -Atc "select count(*) from pipeline.enrichment_flags where field = 'fee_ai_recheck' and state = 'raised'") cards=$($P -d $PD -Atc "select count(*) from security.layer4_inbox_items_v1() where kind = 'fee_check' and why like 'Re-check an admitted AI fee:%'") fees_changed=$($P -d $PD -Atc "select count(*) from catalogue.course_fees where status <> 'active'")"
if $P -d $PD -f $tmp >/dev/null 2>&1; then echo "SECOND PASTE RUN CHANGED SOMETHING"; exit 1; else echo "paste: second run refused (guard)"; fi
rm -f $tmp; [ -n "${FEE_L4_KEEP:-}" ] || $P -d postgres -c "drop database if exists $PD" >/dev/null 2>&1
