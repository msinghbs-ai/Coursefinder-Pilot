#!/usr/bin/env bash
# Guards: Platform Admin mandate 5 Nov 2026 12:44 §11 (production-parity DB tests): migration 20261105040000 on an isolated copy of the
# calendar-v2 fixture database (tests/fixtures/intake-calendar-v2/run.sh, kept), whose live definitions this change edits are checked by md5
# against production, applied twice (idempotent), then the §11 cases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=intake_calendar_v2_fixtures; DB=intake_recovery_final_fixtures; F=tests/fixtures/intake-recovery-final
MIG=supabase/migrations/20261105040000_cf247_intake_recovery_final.sql
P=(psql -X -q -v ON_ERROR_STOP=1)
if [ -z "${INTAKE_RF_REUSE:-}" ] || ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  bash tests/fixtures/intake-preview-timeout/run.sh > /dev/null   # a clean #872 + #876 base (an earlier browser run changes its data)
  INTAKE_CAL_KEEP=1 bash tests/fixtures/intake-calendar-v2/run.sh
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
[ -n "${INTAKE_RF_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" -c "drop database if exists $BASE" >/dev/null' EXIT
md5of() { "${P[@]}" -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the live definitions (read 5 Nov 2026 12:58) this change edits or calls
for x in 'public.admin_process_results_v1(text,jsonb) 1eadf70533349cdbe605b9e9aee164cb' 'security.intake_ui_selection_v1(text,integer) 36ecb3ad4d8fbd7a398e570159dfe4c8' \
         'security.run_now_cohort_create_v1(text,uuid,text,text) a8b976cbb37c1f92121ed51ce49fa019' 'security.intake_dates_apply_v1(integer,uuid[]) b0ced44b21b07d36d21bdf480b1666a3' \
         'security.intake_dates_plan_v3(uuid[],integer) 0eb4f9fdec574d089f9e869aa7d443dd' 'public.svc_calendar_reread_next(integer) 3d9e979dcbf3621d85d7ed2c9be04887' \
         'public.svc_calendar_reread_record(uuid,jsonb,boolean,text,text) e3c2d330d379f14a3b9daf316940d72c' 'security.calendar_dated_periods_v2(uuid) 972f5c48e8d13ca2216027658e50fac5'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from live ($(md5of "$1"))"; exit 1; }
done
"${P[@]}" -d $DB -f $F/parity-tables.sql
echo 'PASS parity: the eight live definitions this change edits or calls (md5 = live) and the production shape of pipeline.firecrawl_calls'
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5of 'public.admin_process_results_v1(text,jsonb)')
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
[ "$(md5of 'public.admin_process_results_v1(text,jsonb)')" = "$AFTER" ] || { echo 'second application changed a definition'; exit 1; }
echo "PASS migration applied twice without change"
OUT=$("${P[@]}" -d $DB -f $F/cases.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-3000; echo "FAIL cases"; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
"${P[@]}" -d $DB -Atc "select p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where (n.nspname, p.proname) in (('public','admin_process_results_v1'),('security','intake_ui_selection_v1'),('security','run_now_cohort_create_v1'),('public','svc_calendar_reread_next_v2'),
        ('public','svc_calendar_refresh_v1'),('security','intake_publication_check_v1'),('security','intake_failure_class_v1')) order by 1" | tee "${UAT_ARTIFACTS:-/tmp}/intake-recovery-final-md5.txt"
