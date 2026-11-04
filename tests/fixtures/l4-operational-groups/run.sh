#!/usr/bin/env bash
# CF-247 Layer 4 operational groups (migration 20261104560000; Platform Admin mandate 4 Nov 2026 16:32 §2, §7, §8, §10) on isolated fixtures.
# Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database:
#   1 ../l4-action-lifecycle/run.sh (it must pass; it builds the live Layer 4 functions as released in v2.15.471), then stubs.sql (the readiness
#     table as live, the card-evidence columns, and the decide routes this change guards); the six definitions it edits are checked against the
#     live md5s read 4 Nov 2026 17:11-17:27 AEDT;
#   2 the migration, then again (the second run changes nothing);
#   3 seed.sql (Course Link, AER, scholarship and onboarding records in production shapes) and fixtures.sql (G1-G8).
# Drops the database at the end (L4G_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${L4G_DB:-l4_operational_groups_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261104560000_cf247_l4_operational_groups.sql
FX=tests/fixtures/l4-operational-groups
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
[ -n "${L4G_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT

# 1 the live Layer 4 functions (v2.15.471) and the stubs
L4LC_KEEP=1 L4LC_DB=$DB bash tests/fixtures/l4-action-lifecycle/run.sh > /dev/null
$P -d $DB -f $FX/stubs.sql > /dev/null
declare -A LIVE=(
  ["public.admin_layer4_inbox(text,jsonb)"]=c0a972a6d6cc0652ce2dcc8f4d9cbbfc
  ["security.layer4_lifecycle_one_v1(text,text,boolean)"]=a93b2bee90704eb3fbd3e09da350ba53
  ["security.layer4_items_lifecycle_v1(jsonb)"]=f6eeef05b818c8818d9eef144ff91a18
  ["security.layer4_item_lifecycle_v1(text,text)"]=a908288151604a4e3d936be5f05a2fad
  ["security.layer4_ack_headline_v1(text,jsonb,jsonb,timestamptz)"]=c715ccb353dcdd77cc6c8f88402595e6
  ["security.layer4_ack_normalise_v1(text,text,boolean,jsonb,text,jsonb)"]=50f4b7b6224c852bcecf4f054b3a81ae
  ["security.layer4_inbox_items_v2(uuid,text,text[],boolean)"]=1e3af24861d931c1d63d30bb87ffa0d6
  ["security.layer4_aer_recovery_detail_v1(text)"]=dbf06336a7ee14fd0a84697d616cb67c
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live 4 Nov 2026 17:11 AEDT): ${#LIVE[@]} definitions"

# 2 the migration, then again
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -v '^psql:' <<<"$OUT" | grep -c ': applied$')" = 6 ] || { echo "the migration did not apply its six guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "public.admin_layer4_inbox(text,jsonb)" "security.layer4_lifecycle_one_v1(text,text,boolean)" "security.layer4_items_lifecycle_v1(jsonb)" "security.layer4_item_lifecycle_v1(text,text)" \
         "security.layer4_ack_headline_v1(text,jsonb,jsonb,timestamptz)" "security.layer4_ack_normalise_v1(text,text,boolean,jsonb,text,jsonb)"; do
  A=$(after "$s"); [ -n "$A" ] && [ "$(md5of "$s")" = "$A" ] || { echo "after md5 of $s: $(md5of "$s") (header: $A)"; exit 1; }
  echo "after: $s ${LIVE[$s]} -> $A"; done
for s in "security.layer4_inbox_items_v2(uuid,text,text[],boolean)" "security.layer4_aer_recovery_detail_v1(text)"; do
  [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "the migration changed $s, which it does not own"; exit 1; }; done
SNAP="select md5(string_agg(x, '|' order by x)) from (select 's:' || s.key || s.value::text || s.updated_at x from pipeline.platform_toolset_settings s
  union all select 'g:' || g.kind || g.name from pipeline.component_register g
  union all select 'f:' || p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('security', 'public') and p.prokind = 'f') z"
S1=$(q "$SNAP")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -v '^psql:' <<<"$OUT" | grep -c ': already applied$')" = 6 ] || { echo "the second run did not find its edits applied"; exit 1; }
[ "$(q "$SNAP")" = "$S1" ] || { echo "a second run changed settings, registers or functions"; exit 1; }
echo "applied twice: the second run changed nothing; the item list and the AER recovery detail are untouched"

# 3 the cases
$P -d $DB -f $FX/seed.sql > /dev/null
$P -d $DB -f $FX/fixtures.sql 2>&1 | show
echo "all Layer 4 operational groups fixtures passed"
