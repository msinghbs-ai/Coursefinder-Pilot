#!/usr/bin/env bash
# Guards: IQ-00313 (Deakin commencement-date contamination, Platform Admin directive 8 Nov 2026): migration 20261108050000 on an isolated PostgreSQL 16
# copy of the production-equivalent fixture (tests/fixtures/intake-fairness/run.sh, kept). The definitions the migration edits are checked by md5 against
# production (read 8 Nov 2026), the change-check functions of the Website and Zoho scans are loaded verbatim (md5 checked), every table the cases write
# is brought to the production NOT NULL set and defaults (and asserted), and the cases run in two phases: the defect on the production code, then the fix.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=intake_fairness_fixtures; DB=${DK_DB:-intake_deakin_calendar_fixtures}; F=tests/fixtures/deakin-intake-calendar
MIG=${DK_MIG:-supabase/migrations/20261108050000_cf247_deakin_intake_calendar_year.sql}
PASTE=docs/paste/PASTE-20261108-iq00313-deakin-intake-withdrawal.sql
P=(psql -X -q -v ON_ERROR_STOP=1)
if [ -z "${DK_REUSE:-}" ] || ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  INTAKE_FAIR_KEEP=1 bash tests/fixtures/intake-fairness/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
[ -n "${DK_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
md5of() { "${P[@]}" -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the production definitions (read 8 Nov 2026) this change replaces or edits
for x in 'security.calendar_proposal_dates_v1(uuid) 84aa52bcfa132b6308df5e402c82505f' 'security.intake_dates_plan_v3(uuid[],integer) 1d531a835fcaa6996ac32f88d218eea8' \
         'security.calendar_dated_periods_v2(uuid) 3a811a4a2e5f710ce6194bee2b3a5fa2' 'security.calendar_sources_v1(uuid) bc67c70514c968490600d0a891492c08' \
         'security.intake_dates_apply_v1(integer,uuid[]) b0ced44b21b07d36d21bdf480b1666a3' 'security.intake_course_applicability_v1(text,integer,integer,jsonb,boolean,text[],text) d3789be9c8dee10f31868700b11abf89' \
         'security.intake_date_withdraw_v1(uuid,text,text,boolean) ab124ac766f291520b12155ff0b0df55' 'public.admin_intake_date_withdraw_v1(uuid[],text) 7a36175f84ac6ad4a7755e06559f09f3'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from production ($(md5of "$1"), expected $2)"; exit 1; }
done
"${P[@]}" -d $DB -f $F/parity-tables.sql
# the Website and Zoho change checks, verbatim from production
for x in 'security.website_sync_item_v1(text,uuid,text) cd15a2cb4c5cdb72c19c7792d9db430f' 'security.zoho_sync_item_v1(text,uuid,text) a4dce41ec4fd06e5262fdc7eb3e851d0' \
         'security.website_sync_check_v1(integer) f8095625ca8c09526900c78c73a21a91' 'security.zoho_sync_check_v1(integer) ea89266fb8d0bccb6226b463b92aac4e' \
         'security.website_sync_candidates_v1(text) 7ec06b8f3d039acc243a23c1db755864' 'security.zoho_sync_candidates_v1(text) d11a91ed6690ee705599e26d4e99b58a' \
         'security.zoho_v2_course_extra_v1(jsonb,uuid) 95d188d374b3edbf0b5cdcdc910c2e1a'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from production ($(md5of "$1"), expected $2)"; exit 1; }
done
echo 'PASS parity: the eight production definitions this change edits or calls and the seven change-check functions of the Website and Zoho scans (md5 = production); NOT NULL sets of the written tables = production'
OUT=$("${P[@]}" -d $DB -f $F/cases-before.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-before'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
# the correction file before the migration is released (no rejection table, no reconcile function): the withdrawal and its guards stand alone, the scans bring the stored items
"${P[@]}" -d postgres -c "drop database if exists ${DB}_pre" -c "create database ${DB}_pre template $DB"
[ -n "${DK_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists ${DB}_pre" >/dev/null 2>&1' EXIT
python3 "$F/paste-for-fixture.py" "$PASTE" "${DB}_pre" cA,cB,cC,cD > "${UAT_ARTIFACTS:-/tmp}/dk-paste-fixture-pre.sql"
OUT=$("${P[@]}" -d ${DB}_pre -f "${UAT_ARTIFACTS:-/tmp}/dk-paste-fixture-pre.sql" 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-2000; echo 'FAIL paste before the migration'; exit 1; }
"${P[@]}" -d ${DB}_pre -Atc "select 1/(case when (select count(*) from catalogue.course_intakes where start_date is not null and intake_year = public.fixture_dk_y0() + 1) = 0
   and (select count(*) from pipeline.manual_locks l join public.dk_cases k on k.course_id = l.entity_id where k.name in ('cA','cB','cC','cD') and l.field = 'intakes') = 4
   and (select count(*) from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and e->>'start_date' = make_date(public.fixture_dk_y0() + 1, 11, 1)::text) = 4 then 1 else 0 end)" > /dev/null \
   || { echo 'FAIL paste before the migration: unexpected state'; exit 1; }
"${P[@]}" -d ${DB}_pre -Atc "select public.fixture_dk_scan()" > /dev/null
"${P[@]}" -d ${DB}_pre -Atc "select 1/(case when (select count(*) from pipeline.website_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and e->>'start_date' = make_date(public.fixture_dk_y0() + 1, 11, 1)::text) = 0
   and (select count(*) from pipeline.zoho_sync_items w, jsonb_array_elements(w.item->'intakes') e where w.entity = 'course' and e->>'start_date' = make_date(public.fixture_dk_y0() + 1, 11, 1)::text) = 0 then 1 else 0 end)" > /dev/null \
   || { echo 'FAIL the scans did not bring the stored items after the early correction'; exit 1; }
echo 'PASS correction before the migration: run first, it withdraws and holds the contaminated intakes with the guards intact; the stored Website and Zoho items still carry the old date at that moment and follow when the production scans run'
# the consumer API (G3): every function of schema api and public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_* as it is before the migration
API_SQL="select p.oid::regprocedure::text || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'api' or (n.nspname = 'public' and (p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'website\_api\_v2\_%' or p.proname like 'zoho\_edge\_%') or p.proname = 'svc_website_settings_v1') order by 1"
"${P[@]}" -d $DB -Atc "$API_SQL" > "${UAT_ARTIFACTS:-/tmp}/dk-api-before.txt"
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5of 'security.calendar_proposal_dates_v1(uuid)')$(md5of 'security.intake_dates_plan_v3(uuid[],integer)')$(md5of 'security.intake_projection_reconcile_v1(uuid[])')
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
[ "$(md5of 'security.calendar_proposal_dates_v1(uuid)')$(md5of 'security.intake_dates_plan_v3(uuid[],integer)')$(md5of 'security.intake_projection_reconcile_v1(uuid[])')" = "$AFTER" ] || { echo 'second application changed a definition'; exit 1; }
echo 'PASS migration 20261108050000 applied twice without change'
"${P[@]}" -d $DB -Atc "$API_SQL" > "${UAT_ARTIFACTS:-/tmp}/dk-api-after.txt"
cmp -s "${UAT_ARTIFACTS:-/tmp}/dk-api-before.txt" "${UAT_ARTIFACTS:-/tmp}/dk-api-after.txt" || { echo 'FAIL consumer API changed by the migration (G3)'; diff "${UAT_ARTIFACTS:-/tmp}/dk-api-before.txt" "${UAT_ARTIFACTS:-/tmp}/dk-api-after.txt" | head; exit 1; }
echo "PASS consumer API frozen: $(wc -l < "${UAT_ARTIFACTS:-/tmp}/dk-api-after.txt") api, website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_* functions identical (md5 of the definition) before and after the migration"
OUT=$("${P[@]}" -d $DB -f $F/cases-after.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-after'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
# the correction (paste file): the ids and the rejected value are the production ones in the file; the cases run the same block against the fixture's contaminated intakes
if [ -f "$PASTE" ]; then
  python3 "$F/paste-for-fixture.py" "$PASTE" "$DB" > "${UAT_ARTIFACTS:-/tmp}/dk-paste-fixture.sql"
  OUT=$("${P[@]}" -d $DB -f "${UAT_ARTIFACTS:-/tmp}/dk-paste-fixture.sql" 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL paste'; exit 1; }
  echo "$OUT" | grep -o 'NOTICE:  IQ-00313.*' || true
  # the operation is recorded: replaying it is refused and changes nothing
  if "${P[@]}" -d $DB -f "${UAT_ARTIFACTS:-/tmp}/dk-paste-fixture.sql" >/dev/null 2>&1; then echo 'FAIL the correction file ran twice'; exit 1; fi
  echo 'PASS replay: the correction file recorded its operation and refuses to run a second time'
  OUT=$("${P[@]}" -d $DB -f $F/cases-paste.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL|LINE|HINT' | cut -c1-3000; echo 'FAIL cases-paste'; exit 1; }
  echo "$OUT" | grep -o 'PASS.*'
fi
"${P[@]}" -d $DB -Atc "select p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where (n.nspname, p.proname) in (('security','calendar_proposal_dates_v1'),('security','intake_dates_plan_v3'),('security','intake_projection_reconcile_v1')) order by 1" | tee "${UAT_ARTIFACTS:-/tmp}/deakin-intake-calendar-md5.txt"
