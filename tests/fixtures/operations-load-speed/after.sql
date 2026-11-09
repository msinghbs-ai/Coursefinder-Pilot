-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): after migration 20261110020000 the same questions give the same answers (apart from the documented cache-derived fields, which agree within the cache's age),
-- the job history says honestly how old it is, a failed or missing summary is shown as stale or unknown and never as current, and the migration changes nothing else.
create or replace function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$ begin if p_cond is not true then raise exception 'FAILED: %', p_name; end if; raise notice 'ok: %', p_name; end $$;
create or replace function pg_temp.jobs(p jsonb) returns table(job text, j jsonb) language sql as $$ select x->>'job', x from jsonb_array_elements(p->'lanes') l, jsonb_array_elements(l->'jobs') x $$;

-- a stable function sees the snapshot of the statement that calls it: the summary is made in one statement and read in the next, as the job and the screen do
create temp table _r(r jsonb);
create or replace function pg_temp.lanes_vs_old(p_state text) returns table(lane text, old_verdict text, new_verdict text, new_state text, active int) language sql as $$
  select o.value->>'lane', o.value->>'verdict', n.value->>'verdict', n.value->>'job_history_state', (o.value->>'jobs_active')::int
    from jsonb_array_elements((select j from ols.old_out where k = 'lane')->'lanes') o
    join jsonb_array_elements(security.lane_funnel_v1(null)->'lanes') n on n.value->>'lane' = o.value->>'lane' $$;


-- 1. the same answers -------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok('lane funnel, all lanes: the same answer as before apart from the cache-derived job fields and the added job_history / history_known',
  ols.norm_lane(security.lane_funnel_v1(null)) = ols.norm_lane((select j from ols.old_out where k = 'lane')));
select pg_temp.ok('lane funnel, one lane: the same answer', ols.norm_lane(security.lane_funnel_v1('int')) = ols.norm_lane((select j from ols.old_out where k = 'lane_int')));
select pg_temp.ok('the job fields themselves are the same right after the summary is made (last attempt, last success, runs, failed, succeeded, running)',
  (select count(distinct job) from pg_temp.jobs(security.lane_funnel_v1(null))) = 54
  and not exists (select 1 from pg_temp.jobs(security.lane_funnel_v1(null)) n join pg_temp.jobs((select j from ols.old_out where k = 'lane')) o using (job)
                   where (n.j - 'next_run' - 'history_known') <> (o.j - 'next_run')));
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
  and (security.lane_funnel_v1(null)->'job_history'->>'stale_after_seconds')::int = 300
  and (select bool_and(l->>'job_history_state' = 'current') from jsonb_array_elements(security.lane_funnel_v1(null)->'lanes') l));
select pg_temp.ok('a job not in the cache is not counted as having no runs: every listed job is known, and an unknown job would say so',
  (select count(*) from pg_temp.jobs(security.lane_funnel_v1(null)) where (j->>'history_known')::boolean) = 56);
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now(), now(), 'succeeded', 'new run' from cron.job where jobname = 'consumer-api-guard';
select pg_temp.ok('a new run is not shown until the summary is made again (the summary is not due for 45 seconds), and the job says so', security.lane_funnel_job_runs_refresh_v1() = '{"refreshed": false, "skipped": "not due"}'::jsonb
  and (select (j->>'runs')::int = 47 from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard'));
insert into _r select security.lane_funnel_job_runs_refresh_v1(true);
select pg_temp.ok('made again (forced): the new run is counted', (select (r->>'refreshed')::boolean from _r) and (select (j->>'runs')::int = 48 and j->>'last_message' = 'new run' from pg_temp.jobs(security.lane_funnel_v1(null)) where job = 'consumer-api-guard'));
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '10 minutes';
select pg_temp.ok('a summary older than its threshold is stale and shows its age, not current', (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean and (security.lane_funnel_v1(null)->'job_history'->>'age_seconds')::int >= 600);
truncate _r; insert into _r select security.lane_funnel_job_runs_refresh_v1();
select pg_temp.ok('the next look makes it again (older than 45 seconds) and it is current', (select (r->>'refreshed')::boolean from _r) and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);

-- 3. a changed window is picked up at once, and shown stale until then --------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set value = to_jsonb(12) where toolset_key = 'pipeline' and key = 'lane_funnel.gain_window_hours';
select pg_temp.ok('a changed window makes the old summary stale (it was made for another window)', (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);
truncate _r; insert into _r select security.lane_funnel_job_runs_refresh_v1();
select pg_temp.ok('and the next look makes it for the new window at once', (select (r->>'refreshed')::boolean from _r) and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
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
create temp table _fa as select failed_at is not null f from pipeline.lane_funnel_job_runs;
truncate _r; insert into _r select security.lane_funnel_job_runs_refresh_v1(true);
select pg_temp.ok('and the next look (after its wait) heals it', (select f from _fa) and (select (r->>'refreshed')::boolean from _r) and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
  and (select error is null and failed_at is null from pipeline.lane_funnel_job_runs));

-- 6. never made: unknown, never zero ----------------------------------------------------------------------------------------------------------------------------------
create temp table keep_jr as select * from pipeline.lane_funnel_job_runs;
delete from pipeline.lane_funnel_job_runs;
select pg_temp.ok('no summary: job_history unknown and stale, every job unknown (not 0 runs), and the read still answers', not (security.lane_funnel_v1(null)->'job_history'->>'known')::boolean and (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean
  and (select count(*) from pg_temp.jobs(security.lane_funnel_v1(null)) where not (j->>'history_known')::boolean) = 56 and jsonb_array_length(security.lane_funnel_v1(null)->'lanes') = 9);
select pg_temp.ok('and every lane that has a job on says job_history_state unknown with the verdict unknown (all-zero counts would have read idle or transferring)',
  (select count(*) from pg_temp.lanes_vs_old('unknown') where old_verdict not in ('off', 'unknown') and active > 0) >= 2
  and not exists (select 1 from pg_temp.lanes_vs_old('unknown') where old_verdict not in ('off', 'unknown') and active > 0 and (new_verdict <> 'unknown' or new_state <> 'unknown')));
truncate _r; insert into _r select security.lane_funnel_job_runs_refresh_v1();
select pg_temp.ok('and the next look makes it', (select (r->>'refreshed')::boolean from _r) and (security.lane_funnel_v1(null)->'job_history'->>'known')::boolean);

-- 6b. lane verdicts do not rest on a history that is stale or unknown -----------------------------------------------------------------------------------------------------
-- (the lanes with a job on whose verdict was not off before the change: the same lanes must say unknown; a lane that is off stays off)
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '10 minutes';
select pg_temp.ok('a stale history: every lane that has a job on says job_history_state stale and verdict unknown, not the confident value it had (idle, transferring, failing); a lane that is off stays off',
  (select count(*) from pg_temp.lanes_vs_old('stale') where old_verdict not in ('off', 'unknown') and active > 0) >= 2
  and not exists (select 1 from pg_temp.lanes_vs_old('stale') where old_verdict not in ('off', 'unknown') and active > 0 and (new_verdict <> 'unknown' or new_state <> 'stale'))
  and (select count(*) from pg_temp.lanes_vs_old('stale') where old_verdict = 'off') >= 1
  and not exists (select 1 from pg_temp.lanes_vs_old('stale') where old_verdict = 'off' and new_verdict <> 'off')
  and not exists (select 1 from pg_temp.lanes_vs_old('stale') where active = 0 and old_verdict <> new_verdict));
select security.lane_funnel_job_runs_refresh_v1(true);
select pg_temp.ok('and when the history is made again the verdicts are the ones they were', not exists (select 1 from pg_temp.lanes_vs_old('current') where old_verdict <> new_verdict or new_state <> 'current'));
-- the two settings cannot leave the history stale for good: the time used is the longer of the stale setting and two looks plus 30 seconds
update pipeline.platform_toolset_settings set value = to_jsonb(600) where toolset_key = 'pipeline' and key = 'lane_funnel.job_runs_refresh_seconds';
update pipeline.platform_toolset_settings set value = to_jsonb(2) where toolset_key = 'pipeline' and key = 'lane_funnel.job_runs_stale_minutes';
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '10 minutes';
select pg_temp.ok('a long refresh time with the shortest stale time: a 10 minute old summary is current (1230 s used), a 25 minute old one is stale',
  (security.lane_funnel_v1(null)->'job_history'->>'stale_after_seconds')::int = 1230 and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '25 minutes';
select pg_temp.ok('and the 25 minute old one is stale', (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);
update pipeline.platform_toolset_settings set value = to_jsonb(10) where toolset_key = 'pipeline' and key = 'lane_funnel.job_runs_refresh_seconds';
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '140 seconds';
select pg_temp.ok('a short refresh time with the shortest stale time: two looks and 30 seconds (150 s) are used, so 140 s old is current and 160 s old is stale',
  (security.lane_funnel_v1(null)->'job_history'->>'stale_after_seconds')::int = 150 and not (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '160 seconds';
select pg_temp.ok('and 160 s old is stale', (security.lane_funnel_v1(null)->'job_history'->>'stale')::boolean);
update pipeline.platform_toolset_settings set value = to_jsonb(45) where toolset_key = 'pipeline' and key = 'lane_funnel.job_runs_refresh_seconds';
update pipeline.platform_toolset_settings set value = to_jsonb(5) where toolset_key = 'pipeline' and key = 'lane_funnel.job_runs_stale_minutes';
select security.lane_funnel_job_runs_refresh_v1(true);

-- 7. job lane-funnel makes the summary --------------------------------------------------------------------------------------------------------------------------------
update pipeline.lane_funnel_job_runs set measured_at = now() - interval '1 hour';
select security.lane_funnel_refresh_v1();
select pg_temp.ok('the lane-funnel job makes the summary when it runs (and still counts the stages)', (select measured_at > now() - interval '1 minute' from pipeline.lane_funnel_job_runs) and (select count(*) from pipeline.lane_funnel_readings) > 0);

-- 7b. the summary is made at the END of the run, and nothing it does can stop the run ---------------------------------------------------------------------------------------------
select pg_temp.ok('the summary is made after the stage counts and the history write, as the last thing the run does',
  position('lane_funnel_job_runs_refresh_v1' in pg_get_functiondef('security.lane_funnel_refresh_v1(boolean)'::regprocedure)) > position('insert into pipeline.lane_funnel_history' in pg_get_functiondef('security.lane_funnel_refresh_v1(boolean)'::regprocedure))
  and position('exception when others' in substr(pg_get_functiondef('security.lane_funnel_refresh_v1(boolean)'::regprocedure), position('lane_funnel_job_runs_refresh_v1' in pg_get_functiondef('security.lane_funnel_refresh_v1(boolean)'::regprocedure)))) > 0);
do $t$
declare d text := pg_get_functiondef('security.lane_funnel_job_runs_refresh_v1(boolean)'::regprocedure); r jsonb; n int;
begin
  -- a writer that fails outside its own handler (as if its settings read failed)
  create or replace function security.lane_funnel_job_runs_refresh_v1(p_force boolean default false) returns jsonb language plpgsql as $b$ begin raise exception 'outside its own handler'; end $b$;
  delete from pipeline.lane_funnel_readings;
  r := security.lane_funnel_refresh_v1(true);
  execute d;
  select count(*) into n from pipeline.lane_funnel_readings;
  if r->>'counted' is null or n = 0 then raise exception 'FAILED: a failure in the job history summary stopped the lane-funnel run (%, % readings)', r, n; end if;
  if md5(pg_get_functiondef('security.lane_funnel_job_runs_refresh_v1(boolean)'::regprocedure)) <> md5(d) then raise exception 'FAILED: the writer was not restored'; end if;
  raise notice 'ok: a failure of the summary outside its own handler does not stop the lane-funnel run (% counted, % readings written)', r->>'counted', n;
end $t$;

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
