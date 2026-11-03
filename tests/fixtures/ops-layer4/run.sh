#!/usr/bin/env bash
# CF-247 P0 Layer 4 readiness and admission throughput (migration 20261104120000) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database the way workstream A's fixture does: the integration queue
# stubs and the queue (repository migration 20261102120000), ../ops-controller/stubs-extra.sql, then workstream A's migration 20261104010000 itself
# (the real controller, its authority triggers and the shared contract, as live since v2.15.429); the contract functions this change calls are
# checked against the live md5s read 3 Nov 2026 18:27 AEDT. Then stubs.sql (the other live shapes), the migration without A's contract in a
# rolled-back database (it must refuse), the migration (no live function may change), again (nothing changes), seed.sql and fixtures.sql.
# Drops the databases at the end (L4_KEEP=1 keeps them).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${L4_DB:-ops_layer4_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql
FX=tests/fixtures/ops-layer4
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_noa" -c "create database $DB" -c "create database ${DB}_noa" >/dev/null 2>&1
[ -n "${L4_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_noa" >/dev/null 2>&1' EXIT

# 1 without workstream A's contract the migration refuses and leaves nothing behind
$P -d ${DB}_noa -f tests/fixtures/integration-queue/stubs.sql
$P -d ${DB}_noa -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
if OUT=$($P -d ${DB}_noa -1 -At -f $MIG 2>&1); then echo "the migration applied without workstream A's contract"; exit 1; fi
grep -q "workstream A's operations contract (migration 20261104010000) must be applied before this change" <<<"$OUT" || { echo "$OUT" | tail -3; exit 1; }
[ "$($P -d ${DB}_noa -Atc "select count(*) from pg_proc where proname like 'layer4\_%' escape '\\' and proname in ('layer4_readiness_tick_v1','layer4_resolution_for_v1')")" = 0 ] || { echo "a refused run left functions"; exit 1; }
echo "without A's contract: refused, nothing left"

# 2 the database as live: queue, A's controller (as merged in v2.15.429), the other live shapes
$P -d $DB -f tests/fixtures/integration-queue/stubs.sql
# Integration Controller 3 Nov 2026: the live kind check on the component register (the first deploy failed on it; the shared stub lacks it)
$P -d $DB -c "alter table pipeline.component_register add constraint component_register_kind_check check (kind = any (array['job','table','view','edge_function','screen','function']))"
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102120000_cf247_integration_queue.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-controller/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104010000_cf247_ops_controller.sql 2>&1 | show
# Integration Controller 3 Nov 2026: the reopen rule (v2.15.436, 20261104100000) is live, so it is loaded as released (its own prerequisites first)
$P -d $DB -1 -o /dev/null -f tests/fixtures/ops-reopen/ai-guards.sql 2>&1 | show
$P -d $DB -f tests/fixtures/ops-reopen/stubs-extra.sql
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql 2>&1 | show
$P -d $DB -f $FX/stubs.sql
declare -A LIVE=(
  ["security.integration_issue_upsert_v1(jsonb,text)"]=c5ce0cb9c431a337789d67bc1878be62
  ["security.ops_remedy_register_v1(text,jsonb)"]=cec6cd2f6518b453fbc8ec3137ce39bd
  ["security.ops_root_cause_register_v1(text,jsonb)"]=591616a6a0bd60d607f65c41c18e2968
  ["security.pipeline_list_v1(text,jsonb)"]=c33c2152bbadc8d01625ced9bf2c9bda
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "functions this change calls (loaded = live): ${#LIVE[@]}"
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public') and p.prokind = 'f' and p.proname not like 'layer4\_%' escape '\\'"
F0=$(q "$FNS")

# 3 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed an existing function"; exit 1; }
echo "applied: no existing function changed"
SNAP="select md5(string_agg(x, '|' order by x)) from (select 'r:' || r::text x from pipeline.ops_root_causes r union all select 'm:' || m::text from pipeline.ops_remedies m
  union all select 's:' || s.key || s.value::text from pipeline.platform_toolset_settings s union all select 'j:' || j.jobname || j.schedule || j.command || j.active from cron.job j
  union all select 'c:' || c.jobname from pipeline.automation_catalogue c union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 't:' || t.tgname from pg_trigger t where not t.tgisinternal union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed the registers, settings, jobs, triggers or functions"; exit 1; }
echo "applied twice: the second run changed nothing"
echo "after md5s:"; q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'security' and p.proname like 'layer4\_%' escape '\\' and p.proname not in ('layer4_reroute_trg_v1') order by 1"

$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all Layer 4 readiness fixtures passed"
