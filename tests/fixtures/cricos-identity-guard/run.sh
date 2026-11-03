#!/usr/bin/env bash
# CF-247 D7 CRICOS identity guard (migration 20261104200000) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds the database the E16 fixture builds (../e16-binding-validation: its five live definitions rebuilt
# from the repository, its stubs, then the E16 migration), so the binding guard, the refusal route and the course page check are as live; adds
# security.layer4_url_key_v1 (20261104120000) and security.pipeline_list_v1 (20261103140000), checks the definitions this change relies on
# against the live md5s read 3 Nov 2026 22:26 AEDT, applies the migration twice (the second run changes nothing), then seed.sql and fixtures.sql.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${CIG_DB:-cricos_identity_guard_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104200000_cf247_cricos_identity_guard.sql
FX=tests/fixtures/cricos-identity-guard
E16=tests/fixtures/e16-binding-validation
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
TMP=$(mktemp -d)
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
trap 'rm -rf "$TMP"; [ -n "${CIG_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
node $E16/before.mjs > "$TMP/before.sql"
$P -d $DB -c "create schema security; create schema search; create schema pipeline; create schema catalogue" >/dev/null
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -o /dev/null -f "$TMP/before.sql"
$P -d $DB -f $E16/stubs.sql >/dev/null
$P -d $DB -q -c "alter table pipeline.evidence_artifacts add column if not exists metadata jsonb not null default '{}', add column if not exists captured_at timestamptz default now()" # stub gaps: live has both
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102030000_cf247_e16_binding_validation.sql 2>&1 | show
sed -n '/^create or replace function security.layer4_url_key_v1/,/^\$function\$;/p' supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql > "$TMP/key.sql"
sed -n '/^create or replace function security.pipeline_list_v1/,/^\$function\$;/p' supabase/migrations/20261103140000_cf247_hidden_failures_country_config.sql > "$TMP/list.sql"
$P -d $DB -f "$TMP/key.sql" -f "$TMP/list.sql" >/dev/null
declare -A LIVE=(
  ["security.coverage_page_refused_host_guard()"]=f2e4102f8788816c3f22f26945785f55
  ["security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)"]=488ef1836fa2ba842009168b9e499d73
  ["security.layer4_url_key_v1(text)"]=42e28a9caf6a28be1d19e7924d3a6067
  ["security.pipeline_list_v1(text,jsonb)"]=c33c2152bbadc8d01625ced9bf2c9bda
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "relied on (loaded = live): ${#LIVE[@]} definitions"
F0=$(q "select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by 1)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'search', 'public') and p.prokind = 'f' and p.proname not like 'cricos\_identity\_%' escape '\\'")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(q "select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by 1)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'search', 'public') and p.prokind = 'f' and p.proname not like 'cricos\_identity\_%' escape '\\'")" = "$F0" ] || { echo "the migration changed an existing function"; exit 1; }
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text x from pipeline.platform_toolset_settings s union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 't:' || t.tgname from pg_trigger t where not t.tgisinternal union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed something"; exit 1; }
echo "applied: no existing function changed; applied twice: the second run changed nothing"
q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname like 'cricos\_identity\_%' escape '\\' order by 1"
$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all CRICOS identity guard fixtures passed"
