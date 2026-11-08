#!/usr/bin/env bash
# CF-247 AER one definition of "ready to decide" and readiness for new items (migration 20261108040000; Platform Admin directive 8 Nov 2026) on isolated
# fixtures. Needs a scratch PostgreSQL 16 (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database:
#   1 the AER review queue database of ../aer-review-queue (production-shaped: 605 waiting items, the live settlement, route and queue definitions);
#   2 the two scheduling functions as live (work-continuity adopt migration), each checked against its live md5 (read 8 Nov 2026), and the live NOT NULL
#     columns of the tables this change reads or writes (the fixture tables were looser than live);
#   3 the readiness run before the change, every item gated again: the snapshot; the migration (guarded edits to their after md5), again (no change);
#     the readiness run after the change, every item gated again: the same snapshot (the per-item function is the run's own steps);
#   4 fixtures.sql: the one definition, the live shapes, readiness for a new item, nothing decided.
# Drops the database at the end (AERR_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERR_DB:-aer_review_ready_fixtures}
P="psql -v ON_ERROR_STOP=1 -q -X"
MIG=supabase/migrations/20261108040000_cf247_aer_review_ready_single_definition.sql
AD=supabase/migrations/20261104320000_cf247_work_continuity_adopt.sql
FX=tests/fixtures/aer-review-ready
q() { $P -d $DB -Atc "$1"; }
md5of() { q "select md5(pg_get_functiondef('$1'::regprocedure))"; }
after() { grep -F -- "--   $1 " $MIG | head -1 | sed 's/.*-> *\([0-9a-f]*\).*/\1/'; }
[ -n "${AERR_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists '$DB'" >/dev/null 2>&1' EXIT

# 1 the AER review queue database
AERQ_KEEP=1 AERQ_DB=$DB bash tests/fixtures/aer-review-queue/run.sh >/dev/null

# 2 live definitions and live constraints
{ awk '/^create or replace function security.work_review_ready_v1/,/^revoke all on function security.work_review_ready_v1/' $AD | head -n -1
  awk '/^create or replace function security.aer_provider_load_v1/,/^revoke all on function security.aer_provider_load_v1/' $AD | head -n -1; } | $P -d $DB >/dev/null
declare -A LIVE=(
  ["security.layer4_readiness_tick_v1()"]=06e5f4394b0c2831404fc7a766d669c4
  ["security.work_review_ready_v1(text)"]=6d90b76b58f0593f7a8d6af038c8c916
  ["security.aer_provider_load_v1()"]=3f0aede5f6f670fa75aeeb8640f4dc63
  ["security.aer_settlement_v1(uuid)"]=49fb7e5071453b7eff4cf343d80b5737
  ["security.aer_route_v1(text,jsonb)"]=5763be109e7cdafd5d5d4b7603b87d78
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "definitions this change edits or calls (loaded = live 8 Nov 2026): ${#LIVE[@]}"
# the live NOT NULL columns (information_schema, project fxcwkweaxjtknorudmwp, 8 Nov 2026) that the fixture tables did not enforce: a fixture may not insert a null live forbids
$P -d $DB <<'SQL' >/dev/null
do $$
declare r record;
begin
  for r in select * from (values
    ('pipeline', 'coverage_course_pages', 'provider_id'), ('pipeline', 'coverage_course_pages', 'status'),
    ('pipeline', 'layer4_item_readiness', 'entity_type'), ('pipeline', 'layer4_item_readiness', 'entity_id'), ('pipeline', 'layer4_item_readiness', 'field_code'),
    ('pipeline', 'layer4_item_readiness', 'item_created_at'), ('pipeline', 'layer4_item_readiness', 'item_status'), ('pipeline', 'layer4_item_readiness', 'readiness'),
    ('pipeline', 'layer4_item_readiness', 'reasons'), ('pipeline', 'layer4_item_readiness', 'route'), ('pipeline', 'layer4_item_readiness', 'blockers'),
    ('pipeline', 'layer4_item_readiness', 'classified_at'),
    ('pipeline', 'manual_locks', 'entity'), ('pipeline', 'manual_locks', 'entity_id'), ('pipeline', 'manual_locks', 'field'), ('pipeline', 'manual_locks', 'mode'), ('pipeline', 'manual_locks', 'set_at'),
    ('pipeline', 'aer_read_supersessions', 'course_id'), ('pipeline', 'aer_read_supersessions', 'source_url'), ('pipeline', 'aer_read_supersessions', 'enrich_item_id'), ('pipeline', 'aer_read_supersessions', 'reason'),
    ('pipeline', 'evidence_artifacts', 'evidence_type'), ('pipeline', 'evidence_artifacts', 'captured_at')) v(s, t, c) loop
    if exists (select 1 from information_schema.columns where table_schema = r.s and table_name = r.t and column_name = r.c and is_nullable = 'YES') then
      -- rows the fixture seed left null get a value of the column's type first (live has none)
      execute format('update %I.%I set %I = %s where %I is null', r.s, r.t, r.c,
        (select case data_type when 'uuid' then 'gen_random_uuid()' when 'text' then quote_literal('fixture') when 'jsonb' then '''{}''::jsonb' when 'ARRAY' then '''{}''' when 'bigint' then '0' when 'integer' then '0'
                              when 'boolean' then 'false' else 'now()' end
           from information_schema.columns where table_schema = r.s and table_name = r.t and column_name = r.c), r.c);
      execute format('alter table %I.%I alter column %I set not null', r.s, r.t, r.c);
    end if;
  end loop;
end $$;
SQL
echo "live NOT NULL columns mirrored"

snap() { q "select md5(string_agg(item_id::text || readiness || coalesce(reasons::text, '') || route || coalesce(blockers::text, '') || coalesce(gate::text, '') || coalesce(est_minutes::text, ''), '|' order by item_id)), count(*) from pipeline.layer4_item_readiness"; }
regate() { q "update pipeline.layer4_item_readiness set classified_at = classified_at - interval '3 hours', gate_checked_at = null"; for i in $(seq 1 35); do q "select security.layer4_readiness_tick_v1()" >/dev/null; done; }

# 3 the readiness run before and after
regate; B=$(snap)
FNS="select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('security', 'public', 'api') and p.prokind = 'f' and p.proname not in ('layer4_readiness_tick_v1', 'work_review_ready_v1', 'aer_provider_load_v1', 'aer_review_ready_v1', 'layer4_readiness_item_v1', 'layer4_readiness_items_v1')"
F0=$(q "$FNS"); S0=$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': applied$' <<<"$OUT")" = 3 ] || { echo "the migration did not apply its 3 guarded edits"; echo "$OUT" | tail -5; exit 1; }
for s in "security.layer4_readiness_tick_v1()" "security.work_review_ready_v1(text)" "security.aer_provider_load_v1()"; do
  [ "$(md5of "$s")" = "$(after "$s")" ] || { echo "$s after: $(md5of "$s"), recorded: $(after "$s")"; exit 1; }; done
[ "$(q "$FNS")" = "$F0" ] || { echo "the migration changed a function it does not own"; exit 1; }
[ "$(q "select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings")" = "$S0" ] || { echo "the migration changed settings"; exit 1; }
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT" | tail -5; exit 1; }
[ "$(grep -c ': already applied$' <<<"$OUT")" = 3 ] || { echo "the second run was not a no-op"; exit 1; }
echo "migration: three guarded edits to their after md5; nothing else changed; applied again: no change"
regate; A=$(snap)
[ "$A" = "$B" ] || { echo "the readiness run after the change classifies differently: before $B, after $A"; exit 1; }
echo "readiness run: every item classified identically before and after the change ($B)"

# 4 the assertions
$P -d $DB -f $FX/fixtures.sql 2>&1 | sed -n "s/^.*\(NOTICE\|ERROR\):  /\1 /p; s/^\(aer-review-ready fixtures: passed\)$/\1/p"
echo "aer-review-ready fixtures: done"
