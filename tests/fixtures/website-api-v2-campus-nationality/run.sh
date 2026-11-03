#!/usr/bin/env bash
# CF-247 Website API v2 developer request (mandate 3 Nov 2026 11:46): campus and nationality fields on isolated fixtures. Needs a scratch
# PostgreSQL (never a Supabase project): PGHOST/PGPORT/PGUSER point at it. Builds a throwaway database (stubs.sql: live shapes and the live
# view text); loads the three live definitions in live/ (read with pg_get_functiondef on 3 Nov 2026 12:02 AEDT) and checks each md5 against
# live; seeds and reproduces the defects (fixtures-before.sql); shows the migration REFUSES without the approval setting and changes nothing;
# records the approval setting (as the Platform Admin would); applies the 20261103180000 migration unchanged (its md5 guards and after-md5
# checks run), applies it again (already applied, unchanged), then runs fixtures.sql. Drops the throwaway database at the end.
set -euo pipefail
cd "$(dirname "$0")"
DB=${APIV2CN_DB:-apiv2_campus_nationality_fixtures}
MIG=../../../supabase/migrations/20261103180000_cf247_website_api_v2_campus_nationality.sql
P="psql -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
[ -n "${APIV2CN_KEEP:-}" ] || trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
show() { sed -n 's/^.*\(NOTICE\|ERROR\):  /\1 /p'; }
md5of() { $P -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
$P -d $DB -f stubs.sql
for f in live/*.sql; do $P -d $DB -c "set check_function_bodies = off" -f "$f"; done
declare -A LIVE=(
  ["security.place_presentable(text)"]=a7b720fc9b34203d0a23315376fd483a
  ["api.website_v2_provider_campuses(uuid)"]=57115d3b8ddbc40729ec04078ee15d41
  ["api.website_v2_scholarship_item(uuid)"]=d1792cc7161101ce8c22abad70ecbd36
)
for s in "${!LIVE[@]}"; do [ "$(md5of "$s")" = "${LIVE[$s]}" ] || { echo "loaded $s differs from live: $(md5of "$s")"; exit 1; }; done
[ "$($P -d $DB -Atc "select md5(pg_get_viewdef('security.layer4_search_blocked_courses'::regclass))")" = 35cdaa19a775ffaaf60fc2be302affec ] || { echo "view differs from live"; exit 1; }
echo "before (loaded = live): ${#LIVE[@]} definitions and the Layer 4 view"
$P -d $DB -f fixtures-before.sql 2>&1 | show
# without approval the migration refuses and changes nothing
if OUT=$($P -d $DB -1 -At -f $MIG 2>&1); then echo "the migration applied without approval"; exit 1; fi
echo "$OUT" | grep -q 'PENDING Platform Admin approval' || { echo "refusal message missing: $OUT"; exit 1; }
[ "$(md5of 'api.website_v2_provider_campuses(uuid)')" = 57115d3b8ddbc40729ec04078ee15d41 ] && [ "$(md5of 'api.website_v2_scholarship_item(uuid)')" = d1792cc7161101ce8c22abad70ecbd36 ] || { echo "a refused run changed a definition"; exit 1; }
echo "no approval: refused, nothing changed"
# approval recorded (what the Platform Admin's approval paste does; proposal §9)
$P -d $DB -c "insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, used_by) values ('pipeline', 'api.v2_campus_nationality_approved', 'Website API v2 campus and nationality fields: approved (1)', 'number', '1', 0, 1, 'flag', 'migration 20261103180000 (approval gate)')"
$P -d $DB -1 -At -f $MIG | grep -c ': applied' | grep -qx 2 || { echo "the migration did not apply both guarded changes"; exit 1; }
A1=$(md5of 'api.website_v2_provider_campuses(uuid)'); A2=$(md5of 'api.website_v2_scholarship_item(uuid)')
echo "after: website_v2_provider_campuses $A1, website_v2_scholarship_item $A2"
$P -d $DB -1 -At -f $MIG 2>/dev/null | grep -c 'already applied' | grep -qx 2 || { echo "a second run changed something"; exit 1; }
[ "$(md5of 'api.website_v2_provider_campuses(uuid)')" = "$A1" ] && [ "$(md5of 'api.website_v2_scholarship_item(uuid)')" = "$A2" ] || { echo "a second run changed a definition"; exit 1; }
echo "second run: already applied, unchanged"
$P -d $DB -f fixtures.sql 2>&1 | show
echo "all fixture checks passed"
