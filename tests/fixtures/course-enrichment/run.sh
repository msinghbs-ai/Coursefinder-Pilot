#!/usr/bin/env bash
# CF-247 Release B (course enrichment from verified stored evidence; Platform Admin mandate 3 Nov 2026 13:09 §4 Release B, D2, D3, §6) on isolated
# fixtures. Needs a scratch PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (live
# shapes); the live definitions in live/ (read on 3 Nov 2026 13:11-13:30 AEDT with pg_get_functiondef, each checked here against its live md5);
# seed.sql; fixtures-before.sql (today's blanket "not on page"); the 20261103210000 migration unchanged (its md5 guards and after-md5 checks run),
# then again (already applied, nothing changed); then fixtures.sql. Drops the throwaway database at the end (RELB_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")"
DB=${RELB_DB:-release_b_fixtures}
MIG=../../../supabase/migrations/20261103210000_cf247_release_b_course_enrichment.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${RELB_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d $DB -f stubs.sql
# live definitions and their live md5 (3 Nov 2026 13:11-13:30 AEDT): the five edited, and the five read against
declare -A LIVE=(
  ["security.enrich_fields_slice_v1(uuid,integer)"]=4babdac64e58459fe38d79def27842ea
  ["public.svc_enrich_ai_next(integer)"]=dfaff31828c7d99d46f25719e5d985cf
  ["public.svc_enrich_ai_record(jsonb)"]=ae1ced1c1f1fd092afe885cfc37be0b4
  ["security.field_enrich_items_flag_v1()"]=d2180b8be792558f8c9f3fa1eb3daf98
  ["security.course_coverage_build_v1()"]=f698bf7f6cc2130adf3c9a4e174c3810
  ["security.enrich_fields_v1()"]=80ee183b324c196b4c9559cec6e3360f
  ["security.enrich_item_in_flight_v1(uuid,uuid,text)"]=35caac7c2ae66aa43ea0ffc9a6d5f654
  ["security.field_sources_for_v1(text,text)"]=d8c74083ed675fb2383fedd4b4a1ec49
  ["security.field_gap_queue_run_v1()"]=429835d4d27375da95901104838a0cad
)
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -c "create trigger field_enrich_items_gate before insert on pipeline.field_enrich_items for each row execute function security.field_enrich_items_gate_v1()" \
          -c "create trigger field_enrich_items_flag after update of state on pipeline.field_enrich_items for each row execute function security.field_enrich_items_flag_v1()"
$P -d $DB -f seed.sql
$P -d $DB -f fixtures-before.sql 2>&1 | show
OUT=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT"; exit 1; }
[ "$(grep -c ': applied' <<<"$OUT")" = 5 ] || { echo "the migration did not apply all five guarded edits"; echo "$OUT"; exit 1; }
show <<<"$OUT"
declare -A AFTER
for s in "security.enrich_fields_slice_v1(uuid,integer)" "public.svc_enrich_ai_next(integer)" "public.svc_enrich_ai_record(jsonb)" "security.field_enrich_items_flag_v1()" "security.course_coverage_build_v1()"; do
  AFTER[$s]=$(md5of "$s"); echo "after: $s ${LIVE[$s]} -> ${AFTER[$s]}"
done
SNAP="select md5(string_agg(x, '|' order by x)) from (select jobname || schedule || command x from cron.job union all select toolset_key || key || value::text || coalesce(used_by, '') from pipeline.platform_toolset_settings
      union all select kind || name from pipeline.component_register union all select jobname || description from pipeline.automation_catalogue
      union all select code || label from pipeline.field_absence_classes union all select priority || reason_pattern from pipeline.field_absence_rules
      union all select course_id || field || absence_class from pipeline.course_field_absence) z"
S1=$($P -d $DB -Atc "$SNAP")
OUT2=$($P -d $DB -1 -At -f $MIG 2>&1) || { echo "$OUT2"; exit 1; }
[ "$(grep -c 'already applied' <<<"$OUT2")" = 5 ] || { echo "a second run changed a guarded function"; echo "$OUT2"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "second run changed $s"; exit 1; }; done
[ "$($P -d $DB -Atc "$SNAP")" = "$S1" ] || { echo "a second run changed jobs, settings, registers or absences"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pg_trigger where tgname = 'field_enrich_items_absence'")" = 1 ] || { echo "trigger count"; exit 1; }
echo "second run: already applied, nothing changed"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "fixtures: all passed"
