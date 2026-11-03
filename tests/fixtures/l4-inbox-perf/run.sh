#!/usr/bin/env bash
# CF-247 Layer 4 Inbox performance (migration 20261104440000) on a production-scale fixture. Needs a scratch PostgreSQL 16 (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Steps:
#   1 ../l4-course-link/run.sh builds the live Layer 4 functions the way they reached production, with its own fixtures (it must pass);
#     the three Inbox definitions are then checked against the live md5 read 4 Nov 2026 06:55 AEDT.
#   2 indexes.sql (the production indexes these reads use), seed-scale.sql (about 5,000 waiting items over 200 universities) and before.sql
#     (what the live definitions return, and how long they take).
#   3 the migration, then again (the second run changes nothing).
#   4 fixtures.sql: same output, first-load reads under budget, paging returns every item exactly once, hooks plug in, decisions unchanged.
# Drops the database at the end (L4P_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${L4P_DB:-l4_inbox_perf_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104440000_cf247_l4_inbox_paging.sql
FX=tests/fixtures/l4-inbox-perf
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
[ -n "${L4P_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the live Layer 4 functions
L4CL_KEEP=1 L4CL_DB=$DB bash tests/fixtures/l4-course-link/run.sh > /dev/null
declare -A LIVE=(
  ["security.layer4_inbox_items_v1()"]=4fc05d14f4ba49335ff90496a20f582d
  ["public.admin_layer4_inbox(text,jsonb)"]=1fb975482d29c7c9f1ecdf3cdb011a10
  ["security.layer4_inbox_kinds_v1()"]=e79ce1815952b4a0e59108981bf62c36
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"

# 2 production scale, and the live definitions' answers
$P -d $DB -f $FX/indexes.sql -f $FX/seed-scale.sql
$P -d $DB -f $FX/before.sql 2>&1 | show

# 3 the migration, then again
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 2 ] || { echo "the migration did not apply both guarded replacements"; echo "$OUT"; exit 1; }
for s in "security.layer4_inbox_items_v1()" "public.admin_layer4_inbox(text,jsonb)"; do echo "after: $s ${LIVE[$s]} -> $(md5of "$s")"; done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text x from pipeline.platform_toolset_settings s
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 'h:' || h::text from pipeline.layer4_inbox_kind_hooks h
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT")" = 2 ] || { echo "a second run changed a guarded function"; echo "$OUT"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed settings, the register, hooks or functions"; exit 1; }
echo "applied twice: the second run changed nothing"
echo "new function md5s:"; q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'security' and p.proname in ('layer4_inbox_items_v2', 'layer4_inbox_counts_v1', 'layer4_inbox_hook_fn_v1', 'layer4_inbox_hooks_v1',
  'layer4_inbox_hook_counts_v1', 'layer4_inbox_hook_call_v1') order by 1"

# 4 the cases
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all Layer 4 Inbox performance fixtures passed"
