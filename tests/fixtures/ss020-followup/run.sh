#!/usr/bin/env bash
# SS-020 follow-up (Decision 269 amendment, 4 Nov 2026): Layer 1 › Sources' Schedule edits the Layer 1 refresh policy and moves the register's
# next run. Throwaway local PostgreSQL 16 database (never a Supabase project): live shapes and live definitions (md5 = live), the migration
# twice (the second run changes nothing), then every case.
set -euo pipefail
cd "$(dirname "$0")"
DB=${SS020FU_DB:-ss020_followup_fixtures}
MIG=../../../supabase/migrations/20261104420000_cf247_ss020_followup_layer1_schedule.sql
P="psql -h ${PGHOST:-/var/run/postgresql} -U postgres -v ON_ERROR_STOP=1 -q -X"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
trap '$P -d postgres -c "drop database if exists $DB" >/dev/null' EXIT
$P -d $DB -f stubs.sql
q() { $P -d $DB -Atc "$1"; }
chk() { local got; got=$(q "$1"); [ "$got" = "$2" ] || { echo "FAIL: $3 (expected $2, got $got)"; exit 1; }; echo "ok $3"; }

# live definitions rebuilt exactly (md5 read live 4 Nov 2026 06:56 AEDT)
chk "select md5(pg_get_functiondef('public.admin_layer1_schedule(uuid,text,text)'::regprocedure))" "53b48153be94af028d322e2d5851962a" "admin_layer1_schedule rebuilt equals live"
chk "select md5(pg_get_functiondef('security.refresh_scheduler_tick_impl(timestamptz,integer)'::regprocedure))" "5f7b3ece8e91919d622b16af652b9250" "refresh_scheduler_tick_impl rebuilt equals live"

# registers as live: AU CRICOS (policy weekly, Sources 30 days), NZQA (policy weekly), a Canadian list without a policy
q "insert into pipeline.sources(id,url) values ('a0000000-0000-4000-8000-000000000001','https://data.gov.au/data/dataset/cricos'),('a0000000-0000-4000-8000-000000000002','https://www.nzqa.govt.nz/providers/index.do'),('a0000000-0000-4000-8000-000000000003','https://cambriancollege.ca/programs')"
q "insert into pipeline.layer1_source_operations(source_id,verification_cadence_days,ingestion_cadence_days,auto_ingest,next_verification_at) values
   ('a0000000-0000-4000-8000-000000000001',30,30,true,now()+interval '29 days'),('a0000000-0000-4000-8000-000000000002',7,7,true,now()+interval '6 days'),
   ('a0000000-0000-4000-8000-000000000003',30,30,true,now()+interval '3 days')"
q "insert into pipeline.refresh_policies(id,country_code,layer,source_id,freshness_class,cadence_interval,next_due_at,change_control_ref) values
   ('b0000000-0000-4000-8000-000000000001','AU',1,'a0000000-0000-4000-8000-000000000001','weekly','7 days',now()+interval '6 days','CF-CHG-20260826-043'),
   ('b0000000-0000-4000-8000-000000000002','NZ',1,'a0000000-0000-4000-8000-000000000002','weekly','7 days',now()+interval '6 days','CF-CHG-20260826-043')"

$P -d $DB -1 -f $MIG >/dev/null
snap() { q "select md5(pg_get_functiondef('public.admin_layer1_schedule(uuid,text,text)'::regprocedure)) || (select md5(string_agg(kind||name||status||coalesce(replaced_by,'')||coalesce(retire_after::text,''), ',' order by kind, name)) from pipeline.component_register)"; }
A=$(snap)
$P -d $DB -1 -f $MIG >/dev/null
[ "$A" = "$(snap)" ] || { echo "FAIL: a second run changed something"; exit 1; }
echo "ok second run: unchanged"
chk "select md5(pg_get_functiondef('public.admin_layer1_schedule(uuid,text,text)'::regprocedure))" "112c34fb7a4aa3198c383bf8d02ff324" "admin_layer1_schedule after md5"
chk "select count(*) from pipeline.component_register where introduced_in='20261104420000' and status='retiring' and replaced_by is not null and retire_after = current_date + 14" "9" "9 rows retiring with replaced_by and retire_after (14 days)"

# 1. the tick before any change: nothing due in the next 2 days
chk "select (security.refresh_scheduler_tick_impl(now()+interval '2 days', 100))->>'policy_requests_created'" "0" "before: no register run due within 2 days"
q "delete from pipeline.refresh_requests"

# 2. role check unchanged: a Pipeline Operator is refused, a short reason is refused
q "update auth.fixture_actor set rank=4"
if q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','daily','operator tries')" 2>/dev/null; then echo "FAIL: rank 4 changed a schedule"; exit 1; fi; echo "ok rank 4 refused (Platform Admin required)"
q "update auth.fixture_actor set rank=6"
if q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','daily','no')" 2>/dev/null; then echo "FAIL: short reason accepted"; exit 1; fi; echo "ok short reason refused"
chk "select cadence_interval::text from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000001'" "7 days" "refused calls changed nothing"

# 3. AU CRICOS weekly -> daily on Layer 1 › Sources: the policy changes and the next run moves from +6 days to +0 days (previous due + 1 day)
q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','daily','CRICOS daily during intake')" >/dev/null
chk "select freshness_class||'|'||cadence_interval::text from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000001'" "critical|1 day" "policy edited: daily (critical, 1 day)"
chk "select next_due_at < now()+interval '1 day' and next_due_at >= now() - interval '1 minute' from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000001'" "t" "next run moved from 6 days to within a day"
chk "select verification_cadence_days||'|'||ingestion_cadence_days||'|'||auto_ingest||'|'||(next_verification_at > now()+interval '28 days') from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000001'" "30|1|true|true" "verification_cadence_days and next_verification_at not written; load days and auto ingest as before"
chk "select (security.refresh_scheduler_tick_impl(now()+interval '2 days', 100))->>'policy_requests_created'" "1" "after: the tick queues the CRICOS run within 2 days"
chk "select count(*) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000001' and requested_layer=1 and trigger_type='freshness_expired'" "1" "the queued request is the CRICOS Layer 1 run"
chk "select count(*) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000002'" "0" "NZQA (unchanged, weekly) not run early"
chk "select detail->'before'->'refresh_policy'->>'cadence_interval'||'>'||(detail->'after'->'refresh_policy'->>'cadence_interval') from pipeline.admin_control_events where action='layer1_schedule_set' and target='a0000000-0000-4000-8000-000000000001'" "7 days>1 day" "audit event records the policy before and after"
q "delete from pipeline.refresh_requests"

# 4. NZQA weekly -> monthly: the next run moves later (previous due + 30 days)
q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000002','monthly','NZQA monthly is enough')" >/dev/null
chk "select freshness_class||'|'||cadence_interval::text||'|'||(next_due_at between now()+interval '28 days 23 hours' and now()+interval '29 days 1 hour') from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000002'" "monthly|30 days|true" "NZQA next run moved from 6 days to 29 days"
q "select security.refresh_scheduler_tick_impl(now()+interval '7 days', 100)" >/dev/null
chk "select count(*) from pipeline.refresh_requests where source_id='a0000000-0000-4000-8000-000000000002'" "0" "NZQA no longer runs at its old weekly due time"

# 5. Manual: monthly status check kept on the policy, automatic loading off
q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000002','manual','load by hand from now')" >/dev/null
chk "select freshness_class||'|'||cadence_interval::text||'|'||enabled from pipeline.refresh_policies where id='b0000000-0000-4000-8000-000000000002'" "monthly|30 days|true" "manual: monthly status check on the policy"
chk "select auto_ingest from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000002'" "f" "manual: automatic loading off"

# 6. A register without a refresh policy keeps today's behaviour (its runs come from next_verification_at)
q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000003','weekly','Cambrian weekly')" >/dev/null
chk "select verification_cadence_days||'|'||ingestion_cadence_days||'|'||(next_verification_at <= now()+interval '3 days') from pipeline.layer1_source_operations where source_id='a0000000-0000-4000-8000-000000000003'" "7|7|true" "no policy: verification cadence written as before"
chk "select count(*) from pipeline.refresh_policies where source_id='a0000000-0000-4000-8000-000000000003'" "0" "no policy created (nothing switched on)"

# 7. bad schedule and non-Layer-1 source refused as before
if q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-000000000001','hourly','not a choice')" 2>/dev/null; then echo "FAIL: hourly accepted"; exit 1; fi; echo "ok unknown schedule refused"
if q "select public.admin_layer1_schedule('a0000000-0000-4000-8000-0000000000ff','daily','no such source')" 2>/dev/null; then echo "FAIL: unknown source accepted"; exit 1; fi; echo "ok unknown source refused"
echo "SS-020 follow-up fixture: all cases passed"
