#!/usr/bin/env bash
# Guards: F-INT.01/SRC-01 (Platform Admin data population first delivery mandate, 9 Nov 2026): migration 20261109060000, the calendar qualification route (default off), on an isolated
# PostgreSQL copy of the production-equivalent fixture chain (tests/fixtures/deakin-intake-calendar, then tests/fixtures/intake-self-driving, both kept). The one production function the
# migration edits (security.policy_auto_approve_v1) is loaded verbatim and checked by md5 against production (read 9 Nov 2026); the production functions it calls are checked by md5; the
# fixture tables are upgraded to the production constraints and asserted against the production lists (parity-tables.sql); a changed policy_auto_approve_v1 makes the migration refuse
# (tested); the migration is applied twice without change; the consumer API (G3) is compared before and after; then the cases and the performance proof. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=intake_self_driving_fixtures; DB=${CQ_DB:-intake_calendar_qualify_fixtures}; DB2=${DB}_refusal; F=tests/fixtures/intake-calendar-qualify
MIG=${CQ_MIG:-supabase/migrations/20261109060000_cf247_intake_calendar_qualify.sql}
P=(psql -X -q -v ON_ERROR_STOP=1)
if [ -z "${CQ_REUSE:-}" ] || ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  SD_REUSE=${SD_REUSE:-} SD_KEEP=1 bash tests/fixtures/intake-self-driving/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists $DB2" -c "create database $DB template $BASE"
[ -n "${CQ_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists '$DB2'" >/dev/null 2>&1' EXIT
md5of() { "${P[@]}" -d "${2:-$DB}" -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# 1 the production function this change edits, exactly as production holds it (read 9 Nov 2026)
"${P[@]}" -d $DB -c 'set check_function_bodies = off' -f $F/live-policy-auto-approve.sql
[ "$(md5of 'security.policy_auto_approve_v1()')" = 189d5c4349f604653f20c8fc854d1cd1 ] || { echo "security.policy_auto_approve_v1 differs from production ($(md5of 'security.policy_auto_approve_v1()'))"; exit 1; }
# the production functions the route calls (the fixture chain holds the production definitions of these; security.pipeline_num_v1 is the fixture's own reader of the settings table)
for x in 'security.calendar_dated_periods_v2(uuid) 3a811a4a2e5f710ce6194bee2b3a5fa2' 'security.calendar_period_canonical_v1(text) b5c0bd7596d00d2ebba82e416aadad6c' \
         'security.calendar_proposal_dates_v1(uuid) 91b613abaeb14527c8ef9b3addcf31d2' 'security.calendar_scope_v1(jsonb,text,text) f2eb75916e9a1e35187dfc1aa165f3de' \
         'security.calendar_set_v1(uuid) 5935b787b0d34a45a36e3c0a96808ae6' 'security.calendar_sources_v1(uuid) bc67c70514c968490600d0a891492c08' \
         'security.intake_date_withdraw_v1(uuid,text,text,boolean) ab124ac766f291520b12155ff0b0df55'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from production ($(md5of "$1"), expected $2)"; exit 1; }
done
echo 'PASS parity: security.policy_auto_approve_v1 (edited) and the 7 production functions the route calls match production by md5 (read 9 Nov 2026)'
# 2 the fixture tables carry the production constraints (asserted against the production lists)
"${P[@]}" -d $DB -f $F/parity-tables.sql 2>&1 | grep -o 'PASS.*'
# 3 the guarded refusal: a policy_auto_approve_v1 that is not the one this change edits stops the migration, and nothing is written
"${P[@]}" -d postgres -c "create database $DB2 template $DB"
"${P[@]}" -d $DB2 -c "do \$\$ begin execute replace(pg_get_functiondef('security.policy_auto_approve_v1()'::regprocedure), 'begin', 'begin /* drifted */'); end \$\$"
[ "$(md5of 'security.policy_auto_approve_v1()' $DB2)" != 189d5c4349f604653f20c8fc854d1cd1 ] || { echo 'FAIL the refusal fixture did not change the function'; exit 1; }
if OUT=$("${P[@]}" -d $DB2 -1 -o /dev/null -f $MIG 2>&1); then echo 'FAIL the migration ran over a changed live definition'; exit 1; fi
echo "$OUT" | grep -q 'live security.policy_auto_approve_v1 differs from the definition this change edits' || { echo "FAIL wrong refusal: $OUT" | cut -c1-600; exit 1; }
[ "$("${P[@]}" -d $DB2 -Atc "select to_regclass('pipeline.calendar_qualify_decisions') is null and not exists (select 1 from pipeline.platform_toolset_settings where key like 'central.calendar_qualify%')")" = t ] || { echo 'FAIL the refused migration left something behind'; exit 1; }
echo 'PASS refusal: a changed live security.policy_auto_approve_v1 stops the migration with "live ... differs from the definition this change edits", and it leaves no table or setting behind'
# 4 the consumer API (G3) before and after
API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%') or p.proname = 'svc_website_settings_v1') order by 1"
ART=${UAT_ARTIFACTS:-/tmp}
"${P[@]}" -d $DB -Atc "$API_SQL" > "$ART/cq-api-before.txt"
SIG="select string_agg(p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)), E'\n' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('security', 'public') and p.proname in ('calendar_qualify_check_v1', 'calendar_qualify_dry_run_v1', 'calendar_qualify_v1', 'calendar_qualify_withdraw_v1', 'admin_calendar_qualify_withdraw_v1', 'policy_auto_approve_v1')"
STATE="select md5(coalesce((select string_agg(row(s.*)::text, '|' order by s.key) from pipeline.platform_toolset_settings s where s.key like '%calendar_qualify%'), '') || coalesce((select string_agg(row(c.*)::text, '|' order by c.jobname) from pipeline.automation_catalogue c where c.jobname = 'policy-auto-approve'), '')
       || coalesce((select string_agg(row(r.*)::text, '|' order by r.kind, r.name) from pipeline.component_register r where r.introduced_in = '20261109060000'), '') || (select count(*) from pipeline.calendar_qualify_decisions))"
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
AFTER=$("${P[@]}" -d $DB -Atc "$SIG"); S1=$("${P[@]}" -d $DB -Atc "$STATE")
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
[ "$("${P[@]}" -d $DB -Atc "$SIG")" = "$AFTER" ] || { echo 'second application changed a definition'; exit 1; }
[ "$("${P[@]}" -d $DB -Atc "$STATE")" = "$S1" ] || { echo 'second application changed a setting, the job description, the register or a decision row'; exit 1; }
echo 'PASS migration 20261109060000 applied twice without change (definitions, settings, job description, register rows and decision rows identical)'
"${P[@]}" -d $DB -Atc "$API_SQL" > "$ART/cq-api-after.txt"
cmp -s "$ART/cq-api-before.txt" "$ART/cq-api-after.txt" || { echo 'FAIL consumer API changed by the migration (G3)'; diff "$ART/cq-api-before.txt" "$ART/cq-api-after.txt" | head; exit 1; }
echo "PASS consumer API frozen: $(wc -l < "$ART/cq-api-after.txt") api, website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_* functions identical (md5 of the definition) before and after the migration"
# 5 the cases, then the performance proof on a fresh copy (so the cases leave no volume behind)
OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-after'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
"${P[@]}" -d postgres -c "drop database if exists $DB2" -c "create database $DB2 template $BASE"
"${P[@]}" -d $DB2 -c 'set check_function_bodies = off' -f $F/live-policy-auto-approve.sql
"${P[@]}" -d $DB2 -f $F/parity-tables.sql > /dev/null 2>&1
"${P[@]}" -d $DB2 -1 -o /dev/null -f $MIG
OUT=$("${P[@]}" -d $DB2 -f $F/perf.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL perf'; exit 1; }
echo "$OUT" | grep -oE 'PASS.*|PERF.*'
echo "$AFTER" | tee "$ART/intake-calendar-qualify-md5.txt"
