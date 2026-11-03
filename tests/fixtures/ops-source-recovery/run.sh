#!/usr/bin/env bash
# CF-247 P0 autonomous operations, workstream B (source discovery and coverage recovery; migration 20261104030000) on isolated fixtures. Needs a
# scratch PostgreSQL (never a Supabase project): PGHOST/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes);
# stub-ops-contract.sql (workstream A's shared contract, exact names); the three live definitions this change edits, rebuilt from the repository's
# live files (source-proof/live, course-enrichment/live) plus the edits migrations 20261103190000 and 20261103210000 made to them, each checked
# against the live md5 read 3 Nov 2026 15:42 AEDT; seed.sql; fixtures-before.sql (today's defects on the live definitions); the migration
# unchanged, then again (already applied, nothing changed); fixtures.sql. Drops the database at the end (OSR_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${OSR_DB:-ops_source_recovery_fixtures}
MIG=../../../supabase/migrations/20261104030000_cf247_ops_source_recovery.sql
M190=../../../supabase/migrations/20261103190000_cf247_source_proof_lane_field_backlog.sql
MRB=../../../supabase/migrations/20261103210000_cf247_release_b_course_enrichment.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${OSR_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
$P -d $DB -f stub-ops-contract.sql
# the live definitions: their text before the two migrations, then exactly the edits those migrations made (extracted from them)
$P -d $DB -c "set check_function_bodies = off" -f ../source-proof/live/security.course_relink_provider_v1.def
$P -d $DB -c "set check_function_bodies = off" -f ../source-proof/live/security.course_relink_tick_v1.def
$P -d $DB -c "set check_function_bodies = off" -f ../course-enrichment/live/security.source_proof_feed_v1.sql
{ sed -n '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/p' $M190
  sed -n "/^select pg_temp.edit_once('security.course_relink_tick_v1/,/]], array\[1\]);/p" $M190
  sed -n "/^select pg_temp.edit_once('security.course_relink_provider_v1/,/]], array\[1\]);/p" $M190; } | $P -d $DB -At >/dev/null
{ sed -n '/^create or replace function pg_temp.edit_once/,/^end \$f\$;/p' $MRB
  sed -n "/^select pg_temp.edit_once('security.source_proof_feed_v1()'/,/]], array\[1\]);/p" $MRB; } | $P -d $DB -At >/dev/null
declare -A LIVE=(
  ["security.source_proof_feed_v1()"]=cade6b2de219c216709129ce4bc447ff
  ["security.course_relink_provider_v1(uuid,integer)"]=8f2f82c7e2ad360a0ade7cdee1f63cce
  ["security.course_relink_tick_v1(integer)"]=b159c75a0ed1517fc9305b62984aa141
  ["security.course_page_key_v1(uuid)"]=eed0e852746ed662c2a7df77dcd7f417
  ["security.source_proof_relink_asked_v1(uuid,timestamp with time zone)"]=097641b28ede4fcf7a6dfa40a66012cf
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -f seed.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT"; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 3 ] || { echo "the migration did not apply all three guarded edits"; echo "$OUT"; exit 1; }
declare -A AFTER
for s in "security.source_proof_feed_v1()" "security.course_relink_provider_v1(uuid,integer)" "security.course_relink_tick_v1(integer)"; do
  AFTER[$s]=$(md5of "$s"); echo "after: $s ${LIVE[$s]} -> ${AFTER[$s]}"
done
SNAP="select md5(string_agg(x, '|' order by x)) from (select jobname || schedule || command x from cron.job union all select toolset_key || key || value::text || coalesce(used_by, '') from pipeline.platform_toolset_settings
      union all select kind || name from pipeline.component_register union all select jobname || description from pipeline.automation_catalogue
      union all select code || class || coalesce(detect::text, '') from pipeline.ops_root_causes union all select code || authority || coalesce(action_fn::text, '') || coalesce(verify_fn::text, '') from pipeline.ops_remedies) z"
S1=$($P -d $DB -Atc "$SNAP")
OUT2=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT2"; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT2")" = 3 ] || { echo "a second run changed a guarded function"; echo "$OUT2"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "second run changed $s"; exit 1; }; done
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed jobs, settings, registers, root causes or remedies"; exit 1; }
echo "second run: already applied, nothing changed"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "fixtures: all passed"
