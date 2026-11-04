#!/usr/bin/env bash
# SS-020 follow-up (Decision 269 amendment; Option A, direction 4 Nov 2026 10:00 §8): Layer 1 › Sources' Schedule and Run now act on the
# register's Layer 1 refresh policy through the legacy Refresh schedules controls (same ranks, reasons and audit), and a schedule change moves
# the next run. Throwaway local PostgreSQL 16 database (never a Supabase project): live shapes and live definitions (md5 = live), the
# migration twice (the second run changes nothing), then every case.
set -euo pipefail
cd "$(dirname "$0")"
DB=${SS020FU_DB:-ss020_followup_fixtures}
MIG=../../../supabase/migrations/20261104510000_cf247_ss020_followup_layer1_schedule.sql
P="psql -h ${PGHOST:-/var/run/postgresql} -U postgres -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
q() { $P -d $DB -Atc "$1"; }
chk() { local got; got=$(q "$1"); [ "$got" = "$2" ] || { echo "FAIL: $3 (expected $2, got $got)"; exit 1; }; echo "ok $3"; }
refused() { if q "$1" >/dev/null 2>&1; then echo "FAIL: $2 was allowed"; exit 1; fi; echo "ok refused: $2"; }
as() { q "update auth.fixture_actor set rank=$1"; }

# live definitions rebuilt exactly (md5 read live 4 Nov 2026 06:56 and 11:09 AEDT)
declare -A LIVE=( ['public.admin_layer1_schedule(uuid,text,text)']=53b48153be94af028d322e2d5851962a
  ['security.refresh_scheduler_tick_impl(timestamptz,integer)']=5f7b3ece8e91919d622b16af652b9250
  ['security.scheduler_policy_edit_v1_browser_bridge(uuid,timestamptz,integer,timestamptz,boolean,text)']=863025c7a7c6c39dd445ff5419ff58ce
  ['security.scheduler_policy_run_now_v1_browser_bridge(uuid,text)']=be60535243220790e08d56e4ee47d4e0 )
for sig in "${!LIVE[@]}"; do chk "select md5(pg_get_functiondef('$sig'::regprocedure))" "${LIVE[$sig]}" "$sig rebuilt equals live"; done

# registers as live: AU CRICOS (policy weekly, Sources 30 days), NZQA (policy weekly), a Canadian list without a policy
q "insert into pipeline.sources(id,url) values ('a0000000-0000-4000-8000-000000000001','https://data.gov.au/data/dataset/cricos'),('a0000000-0000-4000-8000-000000000002','https://www.nzqa.govt.nz/providers/index.do'),('a0000000-0000-4000-8000-000000000003','https://cambriancollege.ca/programs')"
q "insert into pipeline.layer1_source_operations(source_id,verification_cadence_days,ingestion_cadence_days,auto_ingest,next_verification_at) values
   ('a0000000-0000-4000-8000-000000000001',30,30,true,now()+interval '29 days'),('a0000000-0000-4000-8000-000000000002',7,7,true,now()+interval '6 days'),
   ('a0000000-0000-4000-8000-000000000003',30,30,true,now()+interval '3 days')"
q "insert into pipeline.refresh_policies(id,country_code,layer,source_id,freshness_class,cadence_interval,next_due_at,change_control_ref,updated_at) values
   ('b0000000-0000-4000-8000-000000000001','AU',1,'a0000000-0000-4000-8000-000000000001','weekly','7 days',now()+interval '6 days','CF-CHG-20260826-043',now()-interval '1 day'),
   ('b0000000-0000-4000-8000-000000000002','NZ',1,'a0000000-0000-4000-8000-000000000002','weekly','7 days',now()+interval '6 days','CF-CHG-20260826-043',now()-interval '1 day')"

$P -d $DB -1 -f $MIG >/dev/null
snap() { q "select md5(pg_get_functiondef('public.admin_layer1_schedule(uuid,text,text)'::regprocedure)) || md5(pg_get_functiondef('public.admin_layer1_policy_run_v1(uuid,text)'::regprocedure)) || (select md5(string_agg(kind||name||status||coalesce(replaced_by,'')||coalesce(retire_after::text,''), ',' order by kind, name)) from pipeline.component_register)"; }
A=$(snap)
$P -d $DB -1 -f $MIG >/dev/null
[ "$A" = "$(snap)" ] || { echo "FAIL: a second run changed something"; exit 1; }
echo "ok second run: unchanged"
chk "select md5(pg_get_functiondef('public.admin_layer1_schedule(uuid,text,text)'::regprocedure))" "cc0c680d0a1768410d0dd9c516ff4af7" "admin_layer1_schedule after md5"
chk "select md5(pg_get_functiondef('public.admin_layer1_policy_run_v1(uuid,text)'::regprocedure))" "574e4ece482e5907d539a171e389f01a" "admin_layer1_policy_run_v1 md5"
chk "select count(*) from pipeline.component_register where introduced_in='20261104510000' and status='retiring' and replaced_by is not null and retire_after = current_date + 14" "7" "7 rows retiring with replaced_by and retire_after (14 days)"
chk "select count(*) from pipeline.component_register where name like '%browser_bridge' and name ~ 'edit|run_now'" "0" "the edit and run-on-demand implementations are not retired (Layer 1 › Sources uses them)"

# 1. before any change: nothing due within 2 days
chk "select (security.refresh_scheduler_tick_impl(now()+interval '2 days', 100))->>'policy_requests_created'" "0" "before: no register run due within 2 days"
q "delete from pipeline.refresh_requests"

# 2. role and reason rules: as the legacy controls (rank 4, reason of 5) on a register with a policy
as 3; refused "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','daily','curator tries')" "Curator (rank 3) schedule"
as 3; refused "select public.admin_layer1_policy_run_v1('a0000000-0000-4000-8000-000000000001','curator tries')" "Curator (rank 3) run"
as 4; refused "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','daily','four')" "a 4-character reason"
as 4; refused "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','manual','operator goes manual')" "Pipeline Operator choosing Manual"
as 5; refused "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000003','weekly','PIM admin, no policy')" "PIM Admin on a source without a policy"
as 4; refused "select public.admin_layer1_policy_run_v1('a0000000-0000-4000-8000-000000000003','operator runs a source without a policy')" "Pipeline Operator run of a source without a policy"
chk "select cadence_interval::text||'|'||(select count(*) from pipeline.refresh_policy_action_events) from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000001'" "7 days|0" "refused calls changed nothing"

# 3. Pipeline Operator: CRICOS weekly -> daily moves the next run from +6 days to within a day; only the policy changes; legacy audit row
as 4; q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','daily','CRICOS daily during intake')" >/dev/null
chk "select cadence_interval::text||'|'||(next_due_at < now()+interval '1 day' and next_due_at >= now()-interval '1 minute')||'|'||change_control_ref from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000001'" "1 day|true|CF-CHG-20260910-092" "operator: policy 1 day, next run within a day (legacy edit)"
chk "select verification_cadence_days||'|'||ingestion_cadence_days||'|'||auto_ingest||'|'||(next_verification_at > now()+interval '28 days') from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000001'" "30|30|true|true" "operator: no profile column written (verification, load days, automatic loading as before)"
chk "select action||'|'||outcome||'|'||(before_state->>'cadence_interval')||'>'||(after_state->>'cadence_days')||'|'||(actor_id='00000000-0000-4000-8000-000000000006') from pipeline.refresh_policy_action_events" "edit_schedule|applied|7 days>1|true" "legacy audit row (refresh_policy_action_events)"
chk "select count(*) from pipeline.admin_control_events where action='layer1_schedule_set' and target='a0000000-0000-4000-8000-000000000001'" "1" "Layer 1 audit event as before"
chk "select (security.refresh_scheduler_tick_impl(now()+interval '2 days', 100))->>'policy_requests_created'" "1" "after: the tick queues the CRICOS run within 2 days"
chk "select count(*) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000001' and requested_layer=1 and trigger_type='freshness_expired'" "1" "the queued request is the CRICOS Layer 1 run"
chk "select count(*) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000002'" "0" "NZQA (unchanged, weekly) not run early"
q "delete from pipeline.refresh_requests"

# 4. Pipeline Operator Run now: one manual_governed request, no duplicate, audited as run_on_demand; the schedule is unchanged
as 4; q "select public.admin_layer1_policy_run_v1('a0000000-0000-4000-8000-000000000002','NZQA register updated today')" >/dev/null
q "select public.admin_layer1_policy_run_v1('a0000000-0000-4000-8000-000000000002','NZQA register updated today')" >/dev/null
chk "select count(*)||'|'||min(trigger_type)||'|'||min(status) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000002'" "1|manual_governed|queued" "operator run: one queued manual request, not duplicated"
chk "select string_agg(outcome, ',' order by created_at, outcome) from pipeline.refresh_policy_action_events where action='run_on_demand'" "queued,existing_active" "run audited (queued, then existing_active)"
chk "select cadence_interval::text from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000002'" "7 days" "run never changes the recurring schedule"
q "delete from pipeline.refresh_requests"

# 5. Platform Admin: NZQA weekly -> monthly moves the next run later and sets the load days as before; Manual allowed
as 6; q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000002','monthly','NZQA monthly is enough')" >/dev/null
chk "select cadence_interval::text||'|'||(next_due_at between now()+interval '28 days 23 hours' and now()+interval '29 days 1 hour') from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000002'" "30 days|true" "NZQA next run moved from 6 days to 29 days"
q "select security.refresh_scheduler_tick_impl(now()+interval '7 days', 100)" >/dev/null
chk "select count(*) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000002'" "0" "NZQA no longer runs at its old weekly due time"
chk "select ingestion_cadence_days||'|'||verification_cadence_days from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000002'" "30|7" "admin: load days set as before; verification cadence not written"
q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000002','manual','load by hand from now')" >/dev/null
chk "select (select cadence_interval::text||'|'||enabled from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000002')||'|'||auto_ingest from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000002'" "30 days|true|false" "admin manual: monthly status check, automatic loading off"

# 6. A register without a refresh policy keeps today's behaviour (Platform Admin only; its runs come from next_verification_at)
as 6; q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000003','weekly','Cambrian weekly')" >/dev/null
chk "select verification_cadence_days||'|'||ingestion_cadence_days||'|'||(next_verification_at <= now()+interval '3 days') from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000003'" "7|7|true" "no policy: verification cadence written as before"
chk "select count(*) from pipeline.refresh_policies where source_id='a0000000-0000-4000-8000-000000000003'" "0" "no policy created (nothing switched on)"

# 7. bad schedule and non-Layer-1 source refused as before
refused "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','hourly','not a choice')" "unknown schedule"
refused "select public.admin_layer1_schedule('a0000000-0000-4000-8000-0000000000ff','daily','no such source')" "unknown source"
echo "SS-020 follow-up fixture: all cases passed"
