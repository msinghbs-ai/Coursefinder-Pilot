#!/usr/bin/env bash
# Scheduled AER reading on isolated fixtures (CF-247, Platform Admin direction 3 Nov 2026 09:32). Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the D-R2/D-R3 fixture database (E13 and D-R2 stubs, the reader and
# gate rebuilt from this repository, then 20261103070000 itself, as live has it); stubs.sql; the four live definitions in live/ (read with
# pg_get_functiondef on 3 Nov 2026 10:14 AEDT), each checked against its live md5, as are the D-R2 functions the new code calls; then the
# 20261103130000 migration unchanged (its md5 guards and after-md5 checks run), then again (already applied, nothing added twice); then
# fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERJOB_DB:-aer_scheduled_reading_fixtures}
MIG=supabase/migrations/20261103130000_cf247_aer_scheduled_reading.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${AERJOB_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the D-R2/D-R3 database, as tests/fixtures/aer-dr2-dr3/run.sh builds it
$P -d $DB -f tests/fixtures/e13-completeness-gate/stubs.sql
$P -d $DB -f tests/fixtures/aer-dr2-dr3/stubs.sql
node tests/fixtures/e13-completeness-gate/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql
node tests/fixtures/aer-dr2-dr3/before.mjs | $P -d $DB -o /dev/null
$P -d $DB -1 -o /dev/null -f supabase/migrations/20261103070000_cf247_aer_dr2_dr3_supersede_and_matrix_gate.sql
$P -d $DB -f tests/fixtures/aer-scheduled-reading/stubs.sql
for f in tests/fixtures/aer-scheduled-reading/live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
declare -A LIVE=(
  ["security.entry_matrix_enabled_v1(uuid)"]=15fc1b28e855be2d4234057527a1a086
  ["security.entry_matrix_fire_v1()"]=869da9fbdbba2a8321d3f4f3dfba2197
  ["security.course_entry_read_enqueue_v1(uuid,uuid,text)"]=df0f2a2826e61b92b168847f1557435b
  ["security.course_entry_cost_v1()"]=3f247034427a03584856d1a5fe5dd8e1
  ["security.course_entry_correction_v1(uuid,uuid,text)"]=1e2947b30a02a38327e2b67e312339af
  ["security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)"]=2e93bd9b3bc0c2ca7628f3a407b8f57f
  ["security.course_entry_gate_v1(uuid,uuid[])"]=4fc06c081e451f2d0fb0a504a4fbe10f
  ["security.enrich_entry_record_v1(bigint,jsonb)"]=7faf2de4c2afe0a671f8f54c4a140fe4
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 2 || { echo "the migration did not apply both guarded edits"; exit 1; }
A1=$(md5of "security.entry_matrix_enabled_v1(uuid)"); A2=$(md5of "security.entry_matrix_fire_v1()")
echo "after: entry_matrix_enabled_v1 $A1, entry_matrix_fire_v1 $A2"
snap() { $P -d $DB -Atc "select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.integration_issues) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from pipeline.automation_catalogue) || '/' || (select count(*) from pipeline.component_register) || '/' || (select count(*) from pipeline.aer_schedule_runs) || '/' || (select string_agg(md5(i.payload::text), ',') from pipeline.integration_issues i)"; }
S1=$(snap)
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 2 || { echo "a second run changed something"; exit 1; }
[ "$(md5of "security.entry_matrix_enabled_v1(uuid)")" = "$A1" ] && [ "$(md5of "security.entry_matrix_fire_v1()")" = "$A2" ] || { echo "a second run changed a definition"; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed rows: $S1 -> $(snap)"; exit 1; }
echo "second run: already applied, unchanged ($S1)"
$P -d $DB -f tests/fixtures/aer-scheduled-reading/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
