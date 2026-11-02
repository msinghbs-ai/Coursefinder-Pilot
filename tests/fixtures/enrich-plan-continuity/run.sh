#!/usr/bin/env bash
# Plan continuity (CF-247 Workstream E, Platform Admin direction 3 Nov 2026 09:32) on isolated fixtures. Needs a scratch PostgreSQL (never a
# Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes); the seven live definitions in live/
# (read with pg_get_functiondef on 3 Nov 2026 10:12-10:30 AEDT), each checked against its live md5; fixtures-before.sql (the cross-check's
# findings and the cancel defect on the live definitions); the 20261103120000 migration unchanged (its md5 guards and after-md5 checks run),
# then again (already applied, nothing added twice); fixtures.sql; then the paste file and its rollback on the measured ids. Drops the database.
set -euo pipefail
cd "$(dirname "$0")"
DB=${PLANFIX_DB:-enrich_plan_continuity_fixtures}
MIG=../../../supabase/migrations/20261103120000_cf247_enrich_plan_continuity.sql
PASTE=../../../docs/paste/PASTE-20261103-layer2-refresh-requests-close.sql
ROLLBACK=../../../docs/paste/PASTE-20261103-layer2-refresh-requests-close-rollback.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null 2>&1
[ -n "${PLANFIX_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
q() { $P -d $DB -Atc "$1"; }
$P -d $DB -f stubs.sql
declare -A LIVE=(
  ["public.admin_enrich_fields(text,jsonb)"]=184f74ae316051ec0cb4dd62c22b190d
  ["public.admin_enrich_plan(text,jsonb)"]=bd460fcd0e5b4e1dfd41ec1065c2a60c
  ["security.enrich_plan_auto_v1()"]=f9409768bf82bbb29f17ce514c8f9b11
  ["security.field_crosscheck_v1()"]=1023e1373007f09773d2d529d489e9ba
  ["security.enrich_plan_priority_v1()"]=366ff12040bac05d4e494956319a2b76
  ["security.enrich_plan_start_step_v1(uuid,text)"]=4e240fab607122eff455ea3c57b5447f
  ["security.enrich_unit_costs_v1()"]=9ffc69020b6f84c3b4b0af11650b634f
)
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 4 || { echo "the migration did not apply all four guarded changes"; exit 1; }
declare -A AFTER=(
  ["security.enrich_plan_auto_v1()"]=2d8944d7624b90cbbefb9925d602c92b
  ["security.field_crosscheck_v1()"]=b8a5b2de244c277aa4b9e47547017dd7
  ["public.admin_enrich_fields(text,jsonb)"]=349584fc0e9b605e1067cbbd488e435a
  ["public.admin_enrich_plan(text,jsonb)"]=0c9d3ec1b7d043e2d9f3ac83f9d99e1d
)
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "after: $s is $(md5of "$s")"; exit 1; }; done
echo "after: four definitions at their expected md5"
SETTINGS=$(q "select count(*) from pipeline.platform_toolset_settings"); REG=$(q "select count(*) from pipeline.component_register")
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 4 || { echo "a second run changed something"; exit 1; }
for s in "${!AFTER[@]}"; do [ "$(md5of "$s")" = "${AFTER[$s]}" ] || { echo "second run changed $s"; exit 1; }; done
[ "$(q "select count(*) from pipeline.platform_toolset_settings")" = "$SETTINGS" ] && [ "$(q "select count(*) from pipeline.component_register")" = "$REG" ] || { echo "second run added rows"; exit 1; }
[ "$(q "select value::text from pipeline.platform_toolset_settings where key = 'plans.replan_per_hour'")" = 0 ] || { echo "re-planning does not ship off"; exit 1; }
[ "$(q "select count(*) from pipeline.component_register where status = 'retiring' and retire_after is not null and replaced_by is not null and name like 'Scheduled jobs › Refresh schedules%'")" = 2 ] || { echo "Layer 2 schedules not marked retiring"; exit 1; }
echo "second run: already applied, unchanged; re-planning ships off; Layer 2 schedules and Run on demand marked retiring"
$P -d $DB -f fixtures.sql 2>&1 | show
# the paste file and its rollback on the measured ids (206 queued Layer 2 requests, 9 enabled Layer 2 schedules)
$P -d $DB -f paste-rehearsal-seed.sql >/dev/null
[ "$(q "select count(*) || ' ' || md5(string_agg(id::text, ',' order by id)) from pipeline.refresh_requests where requested_layer = 2 and status = 'queued'")" = "206 c3a6579ae9eb22e751d0c5be11ea8cb6" ] || { echo "rehearsal seed is not the measured set"; exit 1; }
$P -d $DB -f $PASTE >/dev/null
[ "$(q "select count(*) from pipeline.refresh_requests where requested_layer = 2 and status = 'cancelled' and schedule_error like 'Closed 3 Nov 2026%'")" = 205 ] || { echo "paste did not close 205"; exit 1; }
[ "$(q "select count(*) from pipeline.refresh_requests where status = 'queued'")" = 2 ] || { echo "paste touched the important-date or Layer 1 request"; exit 1; }
[ "$(q "select count(*) from pipeline.refresh_policies where layer = 2 and enabled")" = 0 ] && [ "$(q "select enabled from pipeline.refresh_policies where layer = 1")" = t ] || { echo "paste schedules"; exit 1; }
[ "$(q "select count(*) from pipeline.refresh_requests")" = 207 ] || { echo "paste deleted rows"; exit 1; }
if $P -d $DB -f $PASTE >/dev/null 2>&1; then echo "rehearsal: a second paste run was not refused"; exit 1; fi
$P -d $DB -f $ROLLBACK >/dev/null 2>&1
[ "$(q "select count(*) || ' ' || md5(string_agg(id::text, ',' order by id)) from pipeline.refresh_requests where requested_layer = 2 and status = 'queued'")" = "206 c3a6579ae9eb22e751d0c5be11ea8cb6" ] || { echo "rollback did not restore the 206"; exit 1; }
[ "$(q "select count(*) || ' ' || md5(string_agg(id::text, ',' order by id)) from pipeline.refresh_policies where layer = 2 and enabled")" = "9 de1f728ba4f8e6ca04420ea1e5ac2f42" ] || { echo "rollback did not re-enable the 9"; exit 1; }
if $P -d $DB -f $ROLLBACK >/dev/null 2>&1; then echo "rehearsal: a second rollback was not refused"; exit 1; fi
echo "ok paste rehearsal: guard matches the measured set; 205 closed (cancelled, nothing deleted), the important-date and Layer 1 requests left, 9 Layer 2 schedules off, Layer 1 on; second run refused; rollback restores 206 and 9; second rollback refused"
