#!/usr/bin/env bash
# Guards: Platform Admin direction 5 Nov 2026 15:50 §6 (pre-production gate on the production-equivalent fixture) and P0 IQ-00313:
# migration 20261105060000 on an isolated copy of the v2.15.481 fixture database (tests/fixtures/intake-recovery-final/run.sh, kept), whose
# live definitions this change edits are checked by md5 against production, applied twice (idempotent), then the §6 regressions.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
BASE=intake_recovery_final_fixtures; DB=intake_fairness_fixtures; F=tests/fixtures/intake-fairness
MIG=supabase/migrations/20261105060000_cf247_intake_fairness_precedence.sql
P=(psql -X -q -v ON_ERROR_STOP=1)
if [ -z "${INTAKE_FAIR_REUSE:-}" ] || ! "${P[@]}" -d postgres -Atc "select 1 from pg_database where datname = '$BASE'" | grep -q 1; then
  INTAKE_RF_KEEP=1 bash tests/fixtures/intake-recovery-final/run.sh > /dev/null
fi
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB template $BASE"
[ -n "${INTAKE_FAIR_KEEP:-}" ] || trap '"${P[@]}" -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
md5of() { "${P[@]}" -d $DB -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the live definitions (read 5 Nov 2026 16:05) this change edits or replaces
for x in 'security.calendar_sources_v1(uuid) 3064e2096d87ce93756d52bc99f5ab4b' 'security.calendar_dated_periods_v2(uuid) 972f5c48e8d13ca2216027658e50fac5' \
         'security.intake_dates_plan_v3(uuid[],integer) 0eb4f9fdec574d089f9e869aa7d443dd' 'security.intake_failure_class_v1(text,text,boolean,text,uuid,integer,integer) e9344ecf77edd58240bf1d73a6073974' \
         'security.intake_dates_apply_v1(integer,uuid[]) b0ced44b21b07d36d21bdf480b1666a3' 'security.calendar_proposal_dates_v1(uuid) 84aa52bcfa132b6308df5e402c82505f'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from live ($(md5of "$1"))"; exit 1; }
done
"${P[@]}" -d $DB -f $F/parity-tables.sql
echo 'PASS parity: the six live definitions this change edits or calls (md5 = live); ten universities, one with 5,200 courses; production shape of pipeline.manual_locks'
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
AFTER=$(md5of 'security.intake_dates_plan_v3(uuid[],integer)')
"${P[@]}" -d $DB -1 -o /dev/null -f $MIG
[ "$(md5of 'security.intake_dates_plan_v3(uuid[],integer)')" = "$AFTER" ] || { echo 'second application changed a definition'; exit 1; }
echo "PASS migration applied twice without change"
OUT=$("${P[@]}" -d $DB -f $F/cases.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|CONTEXT|DETAIL' | cut -c1-3000; echo "FAIL cases"; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
"${P[@]}" -d $DB -Atc "select p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where (n.nspname, p.proname) in (('security','calendar_sources_v1'),('security','calendar_dated_periods_v2'),('security','intake_dates_plan_v3'),('security','intake_failure_class_v1'),
        ('security','calendar_period_canonical_v1'),('security','intake_course_applicability_v1'),('security','intake_date_withdraw_v1'),('public','admin_intake_date_withdraw_v1')) order by 1" | tee "${UAT_ARTIFACTS:-/tmp}/intake-fairness-md5.txt"
