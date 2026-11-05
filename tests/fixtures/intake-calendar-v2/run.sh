#!/usr/bin/env bash
# Guards: Platform Admin decision 5 Nov 2026 (intake recovery and process accountability) §9: migration 20261105020000 on an isolated copy of
# the production-parity intake fixture database (built and kept by tests/fixtures/intake-ui/run.sh), with the production shapes of the central
# calendar tables and the four live functions it edits (md5-checked against live), applied twice (idempotent), then the regression cases.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=${INTAKE_UI_DB:-intake_ui_fixtures}; DB=intake_calendar_v2_fixtures; F=tests/fixtures/intake-calendar-v2
MIG=supabase/migrations/20261105020000_cf247_intake_calendar_v2.sql
P=(psql -X -q -v ON_ERROR_STOP=1)
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
[ -n "${INTAKE_CAL_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { "${P[@]}" -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the five intake functions this change edits or replaces are the live ones (read 5 Nov 2026)
[ "$(md5of 'security.intake_dates_apply_v1(integer,uuid[])')" = d47fbe685ae62287264a1909c988e9d6 ] || { echo 'apply differs from live'; exit 1; }
[ "$(md5of 'security.intake_ui_selection_v1(text,integer)')" = a61e8114a65bc5e13007b8ff1d262976 ] || { echo 'selection differs from live'; exit 1; }
[ "$(md5of 'security.run_now_cohort_create_v1(text,uuid,text,text)')" = 410db5ca480e038e32d12c16f66eefa9 ] || { echo 'cohort differs from live'; exit 1; }
[ "$(md5of 'security.intake_dates_plan_v2(uuid[],integer)')" = 8e3e11c3b78e4e52ea0709e48a666ff6 ] || { echo 'plan v2 differs from live'; exit 1; }
[ "$(md5of 'security.calendar_dated_periods_v1(uuid)')" = ac4fa97ddf0c572750113404ae1804bb ] || { echo 'calendar periods v1 differs from live'; exit 1; }
"${P[@]}" -d $DB -f $F/parity-tables.sql
"${P[@]}" -d $DB -f $F/live-functions.sql
for x in 'public.svc_provider_policy_record(uuid,jsonb) 16b04b3170fae3fc97a5c632d7111fe5' 'public.svc_central_ai_next(integer) fc8273f89031a309311d5e247f453fea' \
         'public.svc_central_ai_record(bigint,jsonb,numeric,text) 2f386c25a249d5c8edfb557a3fbc3d84' 'security.policy_auto_approve_v1() 12cce3d801e7c4b75e021430357fcca2'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from live"; exit 1; }
done
echo 'PASS parity: production table shapes and the nine live definitions this change depends on (md5 = live)'
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5of 'security.intake_dates_apply_v1(integer,uuid[])')
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
[ "$(md5of 'security.intake_dates_apply_v1(integer,uuid[])')" = "$AFTER" ] || { echo 'second application changed a definition'; exit 1; }
echo "PASS migration applied twice without change; apply_v1 now $AFTER"
for f in equivalence cases; do
  OUT=$("${P[@]}" -d $DB -f $F/$f.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-2000; echo "FAIL $f"; exit 1; }
  echo "$OUT" | grep -o 'PASS.*'
done
# the definitions this release puts live (for the Integration Controller's deploy check)
"${P[@]}" -d $DB -Atc "select p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where (n.nspname, p.proname) in (('security','intake_dates_apply_v1'),('security','intake_ui_selection_v1'),('security','run_now_cohort_create_v1'),('public','svc_central_ai_next'),
        ('public','svc_central_ai_record'),('security','policy_auto_approve_v1'),('security','intake_dates_plan_v3'),('security','calendar_dated_periods_v2'),('public','admin_process_results_v1'))
    and p.oid::regprocedure::text <> 'security.intake_dates_apply_v1(integer)' order by 1" | tee "${UAT_ARTIFACTS:-/tmp}/intake-calendar-v2-md5.txt"
