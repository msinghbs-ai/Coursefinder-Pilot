#!/usr/bin/env bash
# Scheduled AER reading on isolated fixtures (CF-247, Platform Admin direction 3 Nov 2026 09:32). Needs a scratch PostgreSQL (never a Supabase
# project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: the D-R2/D-R3 fixture database (E13 and D-R2 stubs, the reader and
# gate rebuilt from this repository, then 20261103070000 itself, as live has it); stubs.sql; the live definitions in live/ (read with
# pg_get_functiondef on 3 Nov 2026 10:14 AEDT and, for the Read next batch selector, Course-level reading and the outcome register, 13:12 AEDT
# after v2.15.423), each checked against its live md5, as are the D-R2 functions the new code calls; then the
# 20261103220000 migration unchanged (its md5 guards and after-md5 checks run), then again (already applied, nothing added twice); then
# fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AERJOB_DB:-aer_scheduled_reading_fixtures}
MIG=supabase/migrations/20261103220000_cf247_aer_scheduled_reading.sql
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
  ["security.course_entry_eligible_v1()"]=5cfd5355834aad3b6af7ca7a882b0d29
  ["security.course_entry_programme_v1(boolean)"]=3261df74758287c168fc297d8a2093bb
  ["security.aer_course_outcomes_build_v1(text)"]=51fb4c3896cfff47626711f98cf62dc1
  ["security.course_entry_batch_v1(uuid,integer,text,uuid,boolean)"]=c4f088b127f207c31e9f1ff41970c6a5
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 5 || { echo "the migration did not apply all five guarded edits"; exit 1; }
EDITED=("security.entry_matrix_enabled_v1(uuid)" "security.entry_matrix_fire_v1()" "security.course_entry_eligible_v1()" "security.course_entry_programme_v1(boolean)" "security.aer_course_outcomes_build_v1(text)")
after() { for s in "${EDITED[@]}"; do echo -n "$s=$(md5of "$s") "; done; }
A=$(after); echo "after: $A"
snap() { $P -d $DB -Atc "select (select count(*) from pipeline.platform_toolset_settings) || '/' || (select count(*) from pipeline.integration_issues) || '/' || (select count(*) from cron.job) || '/' || (select count(*) from pipeline.automation_catalogue) || '/' || (select count(*) from pipeline.component_register) || '/' || (select count(*) from pipeline.aer_schedule_runs) || '/' || (select string_agg(md5(i.payload::text), ',') from pipeline.integration_issues i)"; }
S1=$(snap)
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 5 || { echo "a second run changed something"; exit 1; }
[ "$(after)" = "$A" ] || { echo "a second run changed a definition"; exit 1; }
[ "$(snap)" = "$S1" ] || { echo "a second run changed rows: $S1 -> $(snap)"; exit 1; }
echo "second run: already applied, unchanged ($S1)"
$P -d $DB -f tests/fixtures/aer-scheduled-reading/fixtures.sql 2>&1 | sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'
