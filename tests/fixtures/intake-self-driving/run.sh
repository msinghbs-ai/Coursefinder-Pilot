#!/usr/bin/env bash
# Guards: F-INT (valid course intake dates; Platform Admin data population first delivery mandate, 9 Nov 2026), defects D3 (rows held for evidence are looked at again on a
# revisit time, from stored inputs) and D2 (the fingerprint holds the page wording): migration 20261109020000 on an isolated PostgreSQL copy of the production-equivalent
# fixture (tests/fixtures/deakin-intake-calendar/run.sh, kept). The definitions the migration edits are checked by md5 against production (read 9 Nov 2026), the repeat
# check function is loaded verbatim from production (md5 checked), the migration is applied twice, the consumer API (G3) is compared before and after, and the cases run
# in two phases: the defects on the production code, then the fix. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=intake_deakin_calendar_fixtures; DB=${SD_DB:-intake_self_driving_fixtures}; F=tests/fixtures/intake-self-driving
MIG=${SD_MIG:-supabase/migrations/20261109020000_cf247_intake_revisit_page_fingerprint.sql}
P=(psql -X -q -v ON_ERROR_STOP=1)
if [ -z "${SD_REUSE:-}" ] || ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  DK_KEEP=1 bash tests/fixtures/deakin-intake-calendar/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
[ -n "${SD_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
md5of() { "${P[@]}" -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the two tables the repeat check reads, and the check itself exactly as production holds it
"${P[@]}" -d $DB -f $F/stubs.sql 2>&1 | grep -v NOTICE || true
"${P[@]}" -d $DB -c 'set check_function_bodies = off' -f $F/live-repeats-function.sql
# the production definitions (read 9 Nov 2026) this change edits or calls
for x in 'security.intake_dates_plan_v3(uuid[],integer) 27f5b2a6573aca6c508cd75ab4b3f151' 'security.intake_failure_class_trg_v1() 1ce780aa6cbde2c9a1d9307c3cd68a53' \
         'security.intake_revisit_at_v1(text) 30790a1cdb910a25012d2cc8fa938dbc' 'security.intake_progress_repeats_v1() 4f3d0930df6777edb2a915533e379efb' \
         'security.intake_inputs_fp_v1(text,uuid,text,text) 95cd1801cbccf31253a95f264b9ca168' 'security.intake_page_wording_v1(uuid,uuid,text) 35f52941b6e2c2cfa1a4c9b9463c2de2'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from production ($(md5of "$1"), expected $2)"; exit 1; }
done
echo 'PASS parity: the six production definitions this change edits or calls (md5 = production, read 9 Nov 2026)'
OUT=$("${P[@]}" -d $DB -f $F/cases-before.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-before'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
# the consumer API (G3): every function of schema api and public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_* as it is before the migration
API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%') or p.proname = 'svc_website_settings_v1') order by 1"
ART=${UAT_ARTIFACTS:-/tmp}
"${P[@]}" -d $DB -Atc "$API_SQL" > "$ART/sd-api-before.txt"
SIG="select string_agg(p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)), E'\n' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'security' and p.proname in ('intake_revisit_at_v1', 'intake_failure_class_trg_v1', 'intake_progress_repeats_v1', 'intake_dates_plan_v3', 'intake_revisit_stored_inputs_v1', 'intake_wording_fp_v1')"
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
AFTER=$("${P[@]}" -d $DB -Atc "$SIG")
STATE="select md5(string_agg(row(d.*)::text, '|' order by d.intake_id)) from pipeline.course_intake_dates d"
S1=$("${P[@]}" -d $DB -Atc "$STATE")
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
[ "$("${P[@]}" -d $DB -Atc "$SIG")" = "$AFTER" ] || { echo 'second application changed a definition'; exit 1; }
[ "$("${P[@]}" -d $DB -Atc "$STATE")" = "$S1" ] || { echo 'second application changed a decision row'; exit 1; }
echo 'PASS migration 20261109020000 applied twice without change (definitions and decision rows identical)'
"${P[@]}" -d $DB -Atc "$API_SQL" > "$ART/sd-api-after.txt"
cmp -s "$ART/sd-api-before.txt" "$ART/sd-api-after.txt" || { echo 'FAIL consumer API changed by the migration (G3)'; diff "$ART/sd-api-before.txt" "$ART/sd-api-after.txt" | head; exit 1; }
echo "PASS consumer API frozen: $(wc -l < "$ART/sd-api-after.txt") api, website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_* functions identical (md5 of the definition) before and after the migration"
OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-after'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
echo "$AFTER" | tee "$ART/intake-self-driving-md5.txt"
