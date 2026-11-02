#!/usr/bin/env bash
# IQ-00043 link reactivation guard on isolated fixtures (CF-247 Workstream E, Platform Admin decision 3 Nov 2026 08:44 §5). Needs a scratch
# PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database: stubs.sql (live shapes); the five live
# definitions in live/ (read with pg_get_functiondef on 3 Nov 2026 08:50-08:58 AEDT), each checked against its live md5; the manual_lock_guard
# trigger as live; fixtures-before.sql (the defect reproduced on the live definitions); the 20261103080000 migration unchanged (its md5 guards
# and after-md5 checks run), then again (already applied, nothing added twice); then fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${LINKREACT_DB:-link_reactivation_fixtures}
MIG=../../../supabase/migrations/20261103080000_cf247_link_reactivation_guard.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${LINKREACT_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d $DB -f stubs.sql
# live definitions and their live md5 (3 Nov 2026)
declare -A LIVE=(
  ["security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)"]=c2cbc9ab616a77487d447991f33daaeb
  ["security.coverage_admission_apply_v1(integer,text,text[])"]=7dea1ac5a96edc31ec4dd152d612aae1
  ["security.coverage_norm_url(text)"]=8bd718f741cad98b44accf5121aacecf
  ["security.course_held_v1(uuid)"]=7d12ababc9ca4ba3d4da7c6d0200dbdc
  ["security.manual_fact_guard()"]=d0490f3707199988e87b5f37ca5e7342
)
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
echo "before (loaded = live): ${#LIVE[@]} definitions"
$P -d $DB -c "create trigger manual_lock_guard before insert or delete or update on catalogue.course_links for each row execute function security.manual_fact_guard()"
$P -d $DB -f fixtures-before.sql 2>&1 | show
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 2 || { echo "the migration did not apply both guarded edits"; exit 1; }
A1=$(md5of "security.coverage_admission_apply_v1(integer,text,text[])"); A2=$(md5of "security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)")
[ "$A1" = "2e85e6cbb5d2e64ea1b50fe490c4da76" ] && [ "$A2" = "66dbfd0739ce75f9ef0e20ca2d5975bd" ] || { echo "after md5: admission $A1, apply $A2"; exit 1; }
echo "after: coverage_admission_apply_v1 $A1, coverage_apply_course_v1 $A2"
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 2 || { echo "a second run changed something"; exit 1; }
[ "$(md5of "security.coverage_admission_apply_v1(integer,text,text[])")" = "$A1" ] && [ "$(md5of "security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)")" = "$A2" ] || { echo "a second run changed a definition"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pg_trigger where tgname = 'reactivation_guard'")" = 1 ] || { echo "trigger added twice"; exit 1; }
[ "$($P -d $DB -Atc "select count(*) from pipeline.platform_toolset_settings where key like 'course_link.%'")" = 2 ] || { echo "settings added twice"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
# the paste file and its rollback, unchanged, on the measured 13 (real ids); each must change exactly 13 and leave the shown links as they were
$P -d $DB -f paste-rehearsal-seed.sql >/dev/null
$P -d $DB -c "alter sequence pipeline.admin_control_events_id_seq restart with 30000" >/dev/null
[ "$($P -d $DB -Atc "select count(*) from security.course_link_reactivated_v1() where link_id::text in (select jsonb_array_elements_text(detail->'made_inactive') from pipeline.admin_control_events where id = 28622)")" = 13 ] || { echo "rehearsal: the listing does not find the 13"; exit 1; }
$P -d $DB -f ../../../docs/paste/PASTE-20261103-iq43-reactivated-links.sql >/dev/null
[ "$($P -d $DB -Atc "select count(*) from catalogue.course_links l join pipeline.admin_control_events e on e.id = 28622 and e.detail->'made_inactive' ? l.id::text where l.status = 'inactive'")" = 13 ] || { echo "rehearsal: paste did not restore 13"; exit 1; }
[ "$($P -d $DB -Atc "select (detail->>'count')::int from pipeline.admin_control_events where action = 'iq43_reactivated_link_restore'")" = 13 ] || { echo "rehearsal: no audit row"; exit 1; }
if $P -d $DB -f ../../../docs/paste/PASTE-20261103-iq43-reactivated-links.sql >/dev/null 2>&1; then echo "rehearsal: a second paste run was not refused"; exit 1; fi
$P -d $DB -f ../../../docs/paste/PASTE-20261103-iq43-reactivated-links-rollback.sql >/dev/null
[ "$($P -d $DB -Atc "select count(*) from catalogue.course_links l join pipeline.admin_control_events e on e.id = 28622 and e.detail->'made_inactive' ? l.id::text where l.status = 'active'")" = 13 ] || { echo "rehearsal: rollback did not restore 13"; exit 1; }
echo "ok paste rehearsal: listing finds the 13; paste sets 13 inactive with an audit row, shown links unchanged; a second run is refused; rollback re-activates 13"
