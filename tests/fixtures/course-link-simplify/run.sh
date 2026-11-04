#!/usr/bin/env bash
# CF-247 Course Link simplification (migration 20261104570000) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds the Layer 4 course link base exactly as it reached production (../l4-course-link/run.sh, which runs its
# own cases), the rule-run migrations 20261104280000, 20261104330000 and 20261104350000, and workstream L4's settlement pieces of 20261104120000;
# checks every definition this change reads or edits against the live md5 read 4 Nov 2026 17:10-17:27 AEDT; applies the migration, then again
# (nothing changes); loads the production-shaped backlog (seed.sql) and runs every case (fixtures.sql). Drops the database at the end
# (CLS_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${CLS_DB:-course_link_simplify_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
FX=tests/fixtures/course-link-simplify
MIG=supabase/migrations/20261104570000_cf247_course_link_simplify.sql
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [ -n "${CLS_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the base, as it reached production
L4CL_KEEP=1 L4CL_DB=$DB bash tests/fixtures/l4-course-link/run.sh >/dev/null
$P -d $DB -f $FX/stubs.sql
for m in 20261104280000_cf247_l4_rule_runs_table 20261104330000_cf247_l4_rule_sfu_perf 20261104350000_cf247_l4_rule_target_scheme; do
  PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f supabase/migrations/$m.sql >/dev/null
done
M=supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql
{ sed -n '/^create table if not exists pipeline.layer4_item_readiness/,/^);/p' $M
  sed -n '/^create table if not exists pipeline.layer4_supersessions/,/^);/p' $M
  for f in layer4_value_key_v1 layer4_scope_key_v1 layer4_resolution_for_v1 layer4_resolution_v1 layer4_supersession_reverse_v1; do
    sed -n "/^create or replace function security.$f(/,/^\$function\$;\|^end \$function\$;/p" $M; done; } > "$TMP/l4r.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/l4r.sql" >/dev/null
declare -A LIVE=(
  ["security.layer4_resolution_for_v1(uuid,text,uuid,text,jsonb,jsonb,uuid,timestamp with time zone)"]=487fc2ec6283c95c4961255a860aa9fa
  ["security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)"]=717fb44dd693550cb58f41a400aff455
  ["security.layer4_supersession_reverse_v1(bigint,text)"]=e96e3685cb0914b76b401e33851921e7
  ["security.layer4_course_link_rule_validate_v1(text,uuid)"]=0cf77b67b8d90c98ef3b160306b67faa
  ["security.layer4_course_link_rule_execute_v1(text,integer,boolean)"]=cafae1b603ee3d42513ef87f34cb1639
  ["security.course_page_needed_convert_v1(uuid,integer,boolean)"]=6c9671c68633fe1baa4144d23783a49f
  ["security.course_page_needed_add_v1(uuid,text,text,text,uuid,uuid)"]=d147e3f70cfc42adf5e4b2d82800e0fb
  ["security.layer4_stored_copy_v1(text)"]=fd67a938f1450c0527d447f3bf8742a5
  ["security.layer4_url_key_v1(text)"]=42e28a9caf6a28be1d19e7924d3a6067
  ["security.pipeline_list_v1(text,jsonb)"]=c33c2152bbadc8d01625ced9bf2c9bda
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"

# 2 the migration, then again
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 2 ] || { echo "the migration did not apply both guarded edits"; echo "$OUT"; exit 1; }
for s in "security.layer4_resolution_for_v1(uuid,text,uuid,text,jsonb,jsonb,uuid,timestamp with time zone)" "security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)"; do
  echo "after: $s ${LIVE[$s]} -> $(md5of "$s")"; done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text x from pipeline.platform_toolset_settings s
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT")" = 2 ] || { echo "a second run changed a guarded function"; echo "$OUT"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed settings, the register or functions"; exit 1; }
echo "applied twice: the second run changed nothing"
echo "new function md5s:"; q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'security' and p.proname in ('course_link_site_v1', 'course_link_route_class_v1', 'course_link_reconcile_v1', 'course_link_backlog_report_v1') order by 1"

# 3 the backlog and the cases
$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all Course Link simplification fixtures passed"
