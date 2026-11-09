-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): after migration 20261110020000 the same questions give the same answers (apart from the documented cache-derived fields, which agree within the cache's age),
-- the job history says honestly how old it is, a failed or missing summary is shown as stale or unknown and never as current, and the migration changes nothing else.
create or replace function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$ begin if p_cond is not true then raise exception 'FAILED: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
create or replace function pg_temp.jobs(p jsonb) returns table(job text, j jsonb) language sql as $$ select x->>'job', x from jsonb_array_elements(p->'lanes') l, jsonb_array_elements(l->'jobs') x $$;

-- 1. the same answers -------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok('lane funnel, all lanes: the same answer as before apart from the cache-derived job fields and the added job_history / history_known',
  ols.norm_lane(security.lane_funnel_v1(null)) = ols.norm_lane((select j from ols.old_out where k = 'lane')));
select pg_temp.ok('lane funnel, one lane: the same answer', ols.norm_lane(security.lane_funnel_v1('int')) = ols.norm_lane((select j from ols.old_out where k = 'lane_int')));
select pg_temp.ok('the job fields themselves are the same right after the summary is made (last attempt, last success, runs, failed, succeeded, running)',
  (select count(*) from pg_temp.jobs(security.lane_funnel_v1(null)) n join pg_temp.jobs((select j from ols.old_out where k = 'lane')) o using (job)
    where (n.j - 'next_run' - 'history_known') = (o.j - 'next_run')) = 56);
select pg_temp.ok('the seeded history is really read: a run in progress, a failure outside the window, a long message cut at 240, a job outside the history',
  (select (j->>'running')::boolean from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'first-run-verify')
  and (select (j->>'failed')::int = 1 and (j->>'runs')::int = 47 and j->>'last_status' = 'succeeded' from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard')
  and (select length(j->>'last_message') = 240 from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'fee-reader')
  and (select j->>'last_start' is null and (j->>'runs')::int = 0 from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'calendar-reread')
  and (select (j->>'runs')::int = 0 and j->>'last_start' is not null from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'intake-dates-apply'));
select pg_temp.ok('an unscheduled job and a paused job keep their shape', (select not (j->>'scheduled')::boolean and (j->>'runs')::int = 0 and j->>'last_start' is null from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'integration-validate')
  and (select (j->>'scheduled')::boolean and not (j->>'active')::boolean from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'fee-period-settle'));
select pg_temp.ok('the repeat check gives the same answer (every kind of repeat is in the data)',
  security.intake_progress_repeats_v1() = (select j from ols.old_out where k = 'rep')
  and (security.intake_progress_repeats_v1()->>'confirmed')::int = 1 and (security.intake_progress_repeats_v1()->>'excluded_source_update')::int = 1
  and (security.intake_progress_repeats_v1()->>'excluded_reader_revision')::int = 2 and (security.intake_progress_repeats_v1()->>'excluded_setting_change')::int = 2
  and (security.intake_progress_repeats_v1()->>'excluded_scheduled_revisit')::int = 1 and (security.intake_progress_repeats_v1()->>'unverified_repeat')::int = 1);
select pg_temp.ok('the recovery measurement gives the same answer (the five jobs by name, last run over the whole history)', ols.norm_rec(security.process_results_recovery_v1()) = ols.norm_rec((select j from ols.old_out where k = 'rec'))
  and (select count(*) from jsonb_array_elements(security.process_results_recovery_v1()->'jobs')) = 5
  and (select x->>'last_status' from jsonb_array_elements(security.process_results_recovery_v1()->'jobs') x where x->>'job' = 'calendar-reread') = 'failed');

-- 2. the job history says how old it is ----------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok('right after the summary: known, current, with its window and history', (security.lane_funnel_v1(null)->'job_history'->>'known')::boolean and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
  and (security.lane_funnel_v1(null)->'job_history'->>'window_hours')::int = 24 and (security.lane_funnel_v1(null)->'job_history'->>'history_hours')::int = 48
  and (security.lane_funnel_v1(null)->'job_history'->>'stale_after_minutes')::int = 5);
select pg_temp.ok('a job not in the cache is not counted as having no runs: every listed job is known, and an unknown job would say so',
  (select count(*) from pg_temp.jobs(security.lane_funnel_v1(null)) where (j->>'history_known')::boolean) = 56);
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now(), now(), 'succeeded', 'new run' from cron.job where jobname = 'consumer-api-guard';
select pg_temp.ok('a new run is not shown until the summary is made again (the summary is not due for 45 seconds), and the job says so', security.lane_funnel_job_runs_refresh_v1() = '{"refreshed": false, "skipped": "not due"}'::jsonb
  and (select (j->>'runs')::int = 47 from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard'));
select pg_temp.ok('made again (forced): the new run is counted', (security.lane_funnel_job_runs_refresh_v1(true)->>'refreshed')::boolean and (select (j->>'runs')::int = 48 and j->>'last_message' = 'new run' from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard'));
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '10 minutes';
select pg_temp.ok('a summary older than its threshold is stale and shows its age, not current', (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean and (security.lane_funnel_v1(null)->'job_history'->>'age_seconds')::int >= 600);
select pg_temp.ok('the next look makes it again (older than 45 seconds) and it is current', (security.lane_funnel_job_runs_refresh_v1()->>'refreshed')::boolean and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);

-- 3. a changed window is picked up at once, and shown stale until then --------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set value = to_jsonb(12) where toolset_key = 'pipeline' and key = 'lane_funnel.gain_window_hours';
select pg_temp.ok('a changed window makes the old summary stale (it was made for another window)', (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);
select pg_temp.ok('and the next look makes it for the new window at once', (security.lane_funnel_job_runs_refresh_v1()->>'refreshed')::boolean and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
  and (select (j->>'runs')::int = (select count(*) from cron.job_run_details d join cron.job c on c.jobid = d.jobid where c.jobname = 'consumer-api-guard' and d.start_time > now() - interval '12 hours')
         from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard'));
update pipeline.platform_toolset_settings set value = to_jsonb(24) where toolset_key = 'pipeline' and key = 'lane_funnel.gain_window_hours';
select security.lane_funnel_job_runs_refresh_v1();

-- 4. the run in progress is not counted as the job's last attempt ---------------------------------------------------------------------------------------------------
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message, job_pid) select jobid, now(), null, 'running', null, pg_backend_pid() from cron.job where jobname = 'consumer-api-guard';
select security.lane_funnel_job_runs_refresh_v1(true);
select pg_temp.ok('the run the summary is made in (this backend) is not shown as running or as the last attempt', (select not (j->>'running')::boolean and j->>'last_status' = 'succeeded' from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard'));
delete from cron.job_run_details where job_pid = pg_backend_pid();

-- 5. a failed summary keeps the last good one and is shown as stale with its error --------------------------------------------------------------------------------
do $t$
declare v jsonb; r jsonb;
begin
  alter table cron.job_run_details rename column status to status_x;
  r := security.lane_funnel_job_runs_refresh_v1(true);
  alter table cron.job_run_details rename column status_x to status;
  v := security.lane_funnel_v1(null);
  if (r->>'refreshed')::boolean or r->>'error' is null then raise exception 'FAILED: the failing summary did not report its error: %', r; end if;
  if not (v->'job_history'->>'stale')::boolean or v->'job_history'->>'error' is null or not (v->'job_history'->>'known')::boolean then raise exception 'FAILED: the failed summary is not shown as stale with its error: %', v->'job_history'; end if;
  if (select (j->>'runs')::int from pg_temp.jobs(v) where job = 'consumer-api-guard') is distinct from 48 then raise exception 'FAILED: the last good rows were not kept'; end if;
  if security.lane_funnel_job_runs_refresh_v1() is distinct from '{"refreshed": false, "skipped": "not due"}'::jsonb then raise exception 'FAILED: a failed summary is tried again at every look'; end if;
  raise notice 'ok: a failed summary keeps the last good rows, shows them stale with the error and is not tried again at every look (%)', left(v->'job_history'->>'error', 60);
end $t$;
select pg_temp.ok('and the next look (after its wait) heals it', (select failed_at is not null from pipeline.lane_funnel_job_runs) and (security.lane_funnel_job_runs_refresh_v1(true)->>'refreshed')::boolean and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
  and (select error is null and failed_at is null from pipeline.lane_funnel_job_runs));

-- 6. never made: unknown, never zero ----------------------------------------------------------------------------------------------------------------------------------
create temp table keep_jr as select * from pipeline.lane_funnel_job_runs;
delete from pipeline.lane_funnel_job_runs;
select pg_temp.ok('no summary: job_history unknown and stale, every job unknown (not 0 runs), and the read still answers', not (security.lane_funnel_v1(null)->'job_history'->>'known')::boolean and (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
  and (select count(*) from pg_temp.jobs(security.lane_funnel_v1(null)) where not (j->>'history_known')::boolean) = 56 and jsonb_array_length(security.lane_funnel_v1(null)->'lanes') = 9);
select pg_temp.ok('and the next look makes it', (security.lane_funnel_job_runs_refresh_v1()->>'refreshed')::boolean and (security.lane_funnel_v1(null)->'job_history'->>'known')::boolean);

-- 7. job lane-funnel makes the summary --------------------------------------------------------------------------------------------------------------------------------
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '1 hour';
select security.lane_funnel_refresh_v1();
select pg_temp.ok('the lane-funnel job makes the summary when it runs (and still counts the stages)', (select measured_at > now() - interval '1 minute' from pipeline.lane_funnel_job_runs) and (select count(*) from pipeline.lane_funnel_readings) > 0);

-- 8. what the migration set up -------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok('the two settings are in Pipeline settings with label, range, unit and used_by', (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('lane_funnel.job_runs_refresh_seconds', 'lane_funnel.job_runs_stale_minutes')
  and label is not null and min_value is not null and max_value is not null and unit is not null and used_by is not null and section = 'Lane funnels') = 2);
select pg_temp.ok('the table has its purpose, no public role can read it, and the writer is not open to a public role', obj_description('pipeline.lane_funnel_job_runs'::regclass, 'pg_class') is not null
  and not has_table_privilege('public', 'pipeline.lane_funnel_job_runs', 'select') and not has_function_privilege('public', 'security.lane_funnel_job_runs_refresh_v1(boolean)'::regprocedure, 'execute'));
select pg_temp.ok('the index is partial and commented', (select indexdef like '%WHERE%' from pg_indexes where indexname = 'evidence_artifacts_link_queue_idx') and obj_description('pipeline.evidence_artifacts_link_queue_idx'::regclass, 'pg_class') is not null);
select pg_temp.ok('the lane-funnel job description names the summary; the register lists the table and the writer', (select description like '%scheduler history of the lane jobs%' from pipeline.automation_catalogue where jobname = 'lane-funnel')
  and (select count(*) from pipeline.component_register where name in ('pipeline.lane_funnel_job_runs', 'security.lane_funnel_job_runs_refresh_v1') and introduced_in = '20261110020000') = 2);
select pg_temp.ok('Layer 2/3 operations builds the inbox without its detail', position('layer4_inbox_items_v2(null, null, null, false)' in pg_get_functiondef('public.admin_layer23(text,jsonb)'::regprocedure)) > 0
  and position('layer4_inbox_items_v1' in (select substr(prosrc, strpos(prosrc, '_l23_inbox on commit'), 200) from pg_proc where oid = 'public.admin_layer23(text,jsonb)'::regprocedure)) = 0);
select pg_temp.ok('the repeat check reads the control log once (materialised)', position('st as materialized' in pg_get_functiondef('security.intake_progress_repeats_v1()'::regprocedure)) > 0);
select pg_temp.ok('the lane funnel read no longer touches the scheduler history', position('cron.job_run_details' in pg_get_functiondef('security.lane_funnel_v1(text)'::regprocedure)) = 0);
select pg_temp.ok('all assertions ran', true);
