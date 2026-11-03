#!/usr/bin/env bash
# CF-247 Layer 4 course link (migration 20261104260000) on isolated fixtures. Needs a scratch PostgreSQL (never a Supabase project):
# PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database with the live Layer 4 functions, rebuilt from the repository the way they reached
# production: ../p1-provider-descriptions (stubs, live-before definitions and migration 20261102090000), the item edit of 20261103110000,
# security.binding_refusal_route_v1 from 20261102030000 and security.layer4_url_key_v1 from 20261104120000; each edited definition is checked
# against the live md5 read 3 Nov 2026 20:52 AEDT. Then stubs.sql, the migration (its md5 guards and after-md5 checks run), again (nothing
# changes), seed.sql and fixtures.sql. Drops the database at the end (L4CL_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${L4CL_DB:-l4_course_link_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104260000_cf247_l4_course_link.sql
FX=tests/fixtures/l4-course-link
P1=tests/fixtures/p1-provider-descriptions
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${L4CL_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
TMP=$(mktemp -d); trap 'rm -rf "$TMP"; [ -n "${L4CL_KEEP:-}" ] || $P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the live Layer 4 functions, as they reached production
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f $P1/stubs.sql >/dev/null
for f in $P1/live-before/*.sql; do PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$f" >/dev/null; done
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -o /dev/null -f supabase/migrations/20261102090000_cf247_p1_provider_descriptions.sql 2>&1 | show
M=supabase/migrations/20261103110000_cf247_course_description_deadline_fields.sql
# the decision path as live: its text before 20261103110000 (../course-text/live), then that migration's edit of it and of the item list
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f tests/fixtures/course-text/live/security.layer4_review_decide_impl.sql >/dev/null
{ sed -n '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/p' $M; sed -n "/^select pg_temp.edit_once('security.layer4_inbox_items_v1()'/,/]], array\[/p" $M
  sed -n "/^select pg_temp.edit_once('security.layer4_review_decide_impl(uuid,text,text,jsonb)'/,/]], array\[/p" $M; } > "$TMP/items.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -At -f "$TMP/items.sql" >/dev/null
# the course-link apply as live (../iq67-coverage-admit/live)
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f tests/fixtures/iq67-coverage-admit/live/security.layer4_course_link_apply_impl.def >/dev/null
sed -n '/^create or replace function security.binding_refusal_route_v1/,/^end \$function\$;/p' supabase/migrations/20261102030000_cf247_e16_binding_validation.sql > "$TMP/brr.sql"
sed -n '/^create or replace function security.layer4_url_key_v1/,/^\$function\$;/p' supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql > "$TMP/key.sql"
PGOPTIONS='-c check_function_bodies=off' $P -d $DB -f "$TMP/brr.sql" -f "$TMP/key.sql" >/dev/null
$P -d $DB -f $FX/stubs.sql
declare -A LIVE=(
  ["security.layer4_inbox_kinds_v1()"]=f5fc812e0971a415b664926ec5dbdf8c
  ["security.layer4_inbox_items_v1()"]=a56bc3313e02ac0611deb5657da95ce0
  ["public.admin_layer4_inbox(text,jsonb)"]=f1f0d760b682d6d132af0e8b55151292
  ["security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)"]=488ef1836fa2ba842009168b9e499d73
  ["security.layer4_url_key_v1(text)"]=42e28a9caf6a28be1d19e7924d3a6067
  ["security.pipeline_list_v1(text,jsonb)"]=c33c2152bbadc8d01625ced9bf2c9bda
  ["security.layer4_review_decide_impl(uuid,text,text,jsonb)"]=55353f1903c97b268255c8c1e4f5ca6f
  ["security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)"]=75a53dbbcd5e20e1018a05b61f6763aa
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"

# 2 the migration, then again
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 4 ] || { echo "the migration did not apply all four guarded edits"; echo "$OUT"; exit 1; }
for s in "security.layer4_inbox_kinds_v1()" "security.layer4_inbox_items_v1()" "public.admin_layer4_inbox(text,jsonb)" "security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)"; do
  echo "after: $s ${LIVE[$s]} -> $(md5of "$s")"; done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text x from pipeline.platform_toolset_settings s
  union all select 'g:' || g.kind || g.name from pipeline.component_register g union all select 'r:' || r::text from pipeline.layer4_course_link_rules r
  union all select 't:' || t.tgname from pg_trigger t where not t.tgisinternal union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$(PGOPTIONS='-c check_function_bodies=off' $P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT")" = 4 ] || { echo "a second run changed a guarded function"; echo "$OUT"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed settings, rules, triggers or functions"; exit 1; }
echo "applied twice: the second run changed nothing"
echo "new function md5s:"; q "select '  ' || p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'security' and p.proname in ('layer4_stored_copy_v1', 'layer4_item_page_v1', 'layer4_evidence_link_trg_v1', 'layer4_evidence_backfill_v1', 'course_page_needed_add_v1',
  'course_page_needed_convert_v1', 'course_page_needed_decide_v1', 'layer4_course_link_refuse_v1', 'scholarship_duplicate_close_v1', 'layer4_refusal_search_cost_v1',
  'layer4_course_link_rule_validate_v1', 'layer4_course_link_rule_execute_v1') order by 1"

$P -d $DB -f $FX/seed.sql
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all Layer 4 course link fixtures passed"
