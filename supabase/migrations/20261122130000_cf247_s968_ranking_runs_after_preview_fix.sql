-- CF-247 s968 (session S1-API-Frontend-Delivery, second fix to s966, 22 Nov 2026 12:00 AEDT; IR-005 / RM1J).
-- After s967 the THE 2027 re-run still stopped on the service role's 8 s statement limit, this time before apply: ranking-layer1-etl sent all
-- 3,146 rows to svc_ranking_reconciliation_preview_system (the Australian preview; its slowest completed call was 7.6 s). ranking-layer1-etl
-- v1.8.1 (this release) sends it the Australian rows only; its answer covers Australia only and is unchanged.
-- This migration replaces the s967 runs that are waiting to retry (no worker holds them) with fresh THE and QS 2027 runs for the existing
-- layer1-run-driver, starting after the edge function deploy that follows this migration in Deploy on merge. No function changes here.
-- Live on deploy. $0. G1: no job. G2: no operational value. G3 checked before and after; locks and cron unchanged.
-- Parity: live head 20261122120000 read 22 Nov 2026 11:55 AEDT; this file is numbered strictly above it.
-- Replaces: the s967 re-runs. Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s968_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s968_cron on commit drop as select count(*) n from cron.job where active;

update pipeline.layer1_run_queue set status = 'cancelled', current_stage = 'cancelled', completed_at = now(), heartbeat_at = now(), updated_at = now(),
       error_text = 'Replaced by the s968 re-run (the reconciliation preview time-out is fixed)'
 where (idempotency_key like 's966-initial:%' or idempotency_key like 's967-rerun:%') and status in ('queued', 'running') and (lease_until is null or lease_until < now());

insert into pipeline.layer1_run_queue (source_id, country_code, mode, status, idempotency_key, requested_by, expected_count, resume_cursor, processed_count,
  source_hash, warning_acknowledged, current_stage, heartbeat_at, result)
select s.id, 'GLOBAL', 'apply', 'queued', 's968-rerun:' || s.id::text, 'c0ffee00-0000-4000-8000-000000000150', null, 0, 0, null, false, 'queued',
       now() + interval '7 minutes',  -- fixed: fire guard, so the run starts after the edge function deploy that follows this migration
       jsonb_build_object('start_cursor', 0, 'requested_reason', 's968: THE and QS 2027 read again after the reconciliation preview fix (ranking-layer1-etl v1.8.1)')
  from pipeline.sources s
 where s.metadata->>'ranking_system_code' in ('the_wur', 'qs_wur') and (s.metadata->>'edition_year')::int = 2027 and s.metadata->>'acquisition_mode' = 'publisher_public_json'
   and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = s.id and q.status in ('queued', 'running'))
on conflict (idempotency_key) do nothing;

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if (select count(*) from pipeline.layer1_run_queue where idempotency_key like 's968-rerun:%') <> 2 then raise exception 'post-check: the THE and QS 2027 re-runs were not queued'; end if;
  if (select count(*) from cron.job where active) <> (select n from s968_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s968_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
