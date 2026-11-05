#!/usr/bin/env bash
# Guards: Platform Admin decision 5 Nov 2026 16:36 §8, 19:14 §8 and 20:03 (production-representative, isolated PostgreSQL; the generic progress
# observer reused): builds the Automation Progress fixture database from the production shapes (parity-tables.sql, progress-tables.sql) and the live
# definitions it calls or edits (live-functions.sql, progress-live.sql, each md5 = production), proves the scholarship and AER chains unchanged
# (regression.sql), applies migration 20261106400000 twice (idempotent), loads the run history and runs the cases. Never targets a remote database.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
DB=${INTAKE_PROGRESS_DB:-d_intake_progress}; F=tests/fixtures/intake-progress
MIG=supabase/migrations/20261106400000_cf247_intake_automation_progress.sql
P=(psql -X -q -v ON_ERROR_STOP=1 -d "$DB")
psql -X -q -d postgres -c "drop database if exists $DB" -c "create database $DB" > /dev/null
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f $F/parity-tables.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f $F/progress-tables.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f $F/live-functions.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f $F/progress-live.sql
md5of() { "${P[@]}" -Atc "select md5(pg_get_functiondef('$1'::regprocedure))"; }
# the live definitions (production fxcwkweaxjtknorudmwp, read 5 Nov 2026 19:18-20:08 AEDT)
for x in 'security.current_role_rank() d709d92dbd7a648ccf78e594d68ca980' 'security.pipeline_num_v1(text,numeric) 09f9b1551daf42b4a0c9795e6f30c6d4' \
         'security.toolset_setting(text,text) 678dbbc416c5188ab99b3526e68b0c4d' 'security.intake_ui_scopes_v1() 94bae55f4ecfeca5957f17a0327ba660' \
         'security.integration_issue_allowed_v1(text,text) 0854285323de4ea519089ce6394f96fc' 'security.integration_issue_upsert_v1(jsonb,text) f9d7bf1a6dbe94ba97c34f10817f56c1' \
         'security.automation_batch(text) 9d0f6ac4fecba4469ef01b25354e34e3' 'security.admin_automations_read_v1() 419aef5d1f13e46081a35f23b01d6a15' \
         'security.job_idle_flag_person_release_v1(text,text) 1f69edfe8ca8f8515a2559991076f2c9' 'security.admin_automation_control_v1(text,text,jsonb) 431aff603f21b8c8a030073b07a08259' \
         'public.admin_automation_control(text,text,jsonb) b032f84e705b926ce7026f209116111a' 'security.ops_remedy_guard_active_v1() 5f2ec6b47ce55213c0e90bb46649c844' \
         'security.ops_guard_issue_v1() bb7c1d67a645f52e27a6f7ad184553af' 'security.intake_failure_class_v1(text,text,boolean,text,uuid,integer,integer) 969ebc2cb266f0024d3f4511dc4515a0' \
         'security.intake_failure_class_trg_v1() 1ce780aa6cbde2c9a1d9307c3cd68a53' 'public.admin_process_results_v1(text,jsonb) 6b1097934385d72ac15afce6b781d6ab' \
         'security.progress_measure_v1(text,timestamptz) 40c0c972abc353be8f6eee35c79750e9' 'security.progress_zero_reason_v1(text,jsonb) 746d7baedb0a79dc0a6fbfead82f67c2' \
         'security.progress_read_v1() f11ed22d149eb06aa10387e67467ec6f'; do
  set -- $x; [ "$(md5of "$1")" = "$2" ] || { echo "$1 differs from live ($(md5of "$1"))"; exit 1; }
done
echo 'PASS parity: 19 live definitions (md5 = production), the production table shapes with their checks, keys, triggers, RLS and grants'
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -o /dev/null -f $F/seed.sql
# regression: the scholarship and AER chains give identical measures and observer readings before and after (in one rolled-back transaction)
OUT=$(PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -At -f $F/regression.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|FAIL|CONTEXT' | cut -c1-3000; echo 'FAIL regression'; exit 1; }
echo "$OUT" | grep -E '^(PASS|FAIL)' ; echo "$OUT" | grep -q '^FAIL' && exit 1
# a progress_measure_v1 that is not the live definition (for example #875 applied first) is refused
if "${P[@]}" -c "begin" -c "do \$\$begin execute replace(pg_get_functiondef('security.progress_measure_v1(text,timestamptz)'::regprocedure), 'declare v jsonb;', 'declare v jsonb; -- other'); end\$\$" -f $MIG > /dev/null 2>&1; then echo 'FAIL a changed progress_measure_v1 not refused'; exit 1; fi
echo 'PASS the migration refuses a progress_measure_v1 that is not the live definition (md5 40c0c972)'
JOBS=$("${P[@]}" -Atc "select md5(string_agg(jobname || schedule || command, ';' order by jobname)) from cron.job")
NEW="('public.admin_intake_progress_v1'),('security.intake_progress_status_v1'),('security.intake_progress_window_v1'),('security.intake_progress_universities_v1'),('security.intake_progress_runs_v1'),('security.intake_progress_failures_v1'),('security.intake_progress_alerts_v1'),('security.intake_progress_checks_v1'),('security.intake_progress_repeats_v1'),('security.progress_measure_v1'),('security.progress_read_v1')"
sig() { "${P[@]}" -Atc "select string_agg(p.oid::regprocedure || ' ' || md5(pg_get_functiondef(p.oid)), E'\n' order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname || '.' || p.proname in (select x from (values $NEW) v(x))"; "${P[@]}" -Atc "select md5(string_agg(row(t.*)::text, '|' order by key)) || ' ' || (select pg_get_constraintdef(oid) from pg_constraint where conname = 'progress_transitions_chain_check') from pipeline.progress_transitions t"; }
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -1 -o /dev/null -f $MIG
AFTER=$(sig)
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -1 -o /dev/null -f $MIG
[ "$(sig)" = "$AFTER" ] || { echo 'second application changed a definition or a transition'; exit 1; }
[ "$("${P[@]}" -Atc "select md5(string_agg(jobname || schedule || command, ';' order by jobname)) from cron.job")" = "$JOBS" ] || { echo 'a job changed'; exit 1; }
echo 'PASS migration 20261106400000 applied twice without change; no job added or changed'
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -o /dev/null -f $F/data.sql
OUT=$(PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -At -f $F/cases.sql 2>&1) || { echo "$OUT" | grep -E 'ERROR|FAIL|CONTEXT' | cut -c1-3000; echo 'FAIL cases'; exit 1; }
echo "$OUT" | grep -o 'PASS.*'
# the browser test starts from the loaded run history (the cases roll back what they add, except one observer reading and two audit rows)
sig | tee "${UAT_ARTIFACTS:-/tmp}/intake-progress-md5.txt" > /dev/null
echo "PASS fixture database $DB ready for the browser test"
