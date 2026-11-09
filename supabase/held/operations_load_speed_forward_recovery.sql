-- HELD (not a migration): forward recovery for 20261110020000 (Operations load speed). Run only if the Platform Admin decides to go back to the text of the five functions before that migration.
-- It restores each of them byte for byte, by undoing the migration's own edits, and proves it: every function is guarded by the md5 of what is live now (pg_proc.prosrc) and, after the edit, must
-- have exactly the md5 it had before the migration; if a function is neither the one the migration wrote nor the one it replaced, the script stops and nothing is changed.
-- After it the lane funnel read scans the scheduler history again (4.5 to 20 s), the intake status view and Layer 2/3 operations are slow again (3.5 to 7 s and 2 to 3.7 s) and the 8 second limit returns.
-- Body md5 of each function (pg_proc.prosrc, read 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp):
-- security.lane_funnel_v1(text) cd8ecc118783da99f50c6fbd035cd3c1 (before the migration) <- a52dc6bbcea06b7eaa2a5bb40a05d0c4 (after it)
-- security.lane_funnel_refresh_v1(boolean) e3e4280b536fe985822608139714434e (before the migration) <- bdba1e435806cb88a2d5cf8370b96ab7 (after it)
-- security.intake_progress_repeats_v1() 3f4a208ca8e0252eb17a1e21e73f80ca (before the migration) <- c973fda29d27214c393dc6f4405a632c (after it)
-- security.process_results_recovery_v1() 0bb7a5bd32ba384bf341214c9a5a9c3c (before the migration) <- 55686871dbffb3e2e381a5d11684d4e4 (after it)
-- public.admin_layer23(text,jsonb) 4c99a80f6899cda0d836dcc4196534de (before the migration) <- 5b4c18db5115318ff0423b0a5d5c4248 (after it)
do $g$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.lane_funnel_v1(text)');
  if v is null then raise exception '% is missing', 'security.lane_funnel_v1(text)'; end if;
  if v not in ('cd8ecc118783da99f50c6fbd035cd3c1', 'a52dc6bbcea06b7eaa2a5bb40a05d0c4') then raise exception 'live security.lane_funnel_v1(text) differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.lane_funnel_refresh_v1(boolean)');
  if v is null then raise exception '% is missing', 'security.lane_funnel_refresh_v1(boolean)'; end if;
  if v not in ('e3e4280b536fe985822608139714434e', 'bdba1e435806cb88a2d5cf8370b96ab7') then raise exception 'live security.lane_funnel_refresh_v1(boolean) differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.intake_progress_repeats_v1()');
  if v is null then raise exception '% is missing', 'security.intake_progress_repeats_v1()'; end if;
  if v not in ('3f4a208ca8e0252eb17a1e21e73f80ca', 'c973fda29d27214c393dc6f4405a632c') then raise exception 'live security.intake_progress_repeats_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('security.process_results_recovery_v1()');
  if v is null then raise exception '% is missing', 'security.process_results_recovery_v1()'; end if;
  if v not in ('0bb7a5bd32ba384bf341214c9a5a9c3c', '55686871dbffb3e2e381a5d11684d4e4') then raise exception 'live security.process_results_recovery_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
  select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure('public.admin_layer23(text,jsonb)');
  if v is null then raise exception '% is missing', 'public.admin_layer23(text,jsonb)'; end if;
  if v not in ('4c99a80f6899cda0d836dcc4196534de', '5b4c18db5115318ff0423b0a5d5c4248') then raise exception 'live public.admin_layer23(text,jsonb) differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.lane_funnel_v1(text)', 'a52dc6bbcea06b7eaa2a5bb40a05d0c4', 'cd8ecc118783da99f50c6fbd035cd3c1',
array[
$old$  v_fc jsonb := security.fc_budget_status_v1();
  -- how old the job-history summary may be before it is marked stale, in seconds: the longer of the setting and two looks of job lane-funnel plus a grace, so allowed settings never leave it stale for good
  v_jr_stale_after int := greatest(security.pipeline_num_v1('lane_funnel.job_runs_stale_minutes', 5)::int * 60,  -- fixed: minutes to seconds
                                   2 * greatest(security.pipeline_num_v1('lane_funnel.job_runs_refresh_seconds', 45)::int, 60) + 30);  -- fixed: job lane-funnel looks once a minute (its schedule), so a summary is made again at most every second look; two looks and 30 s of grace before it is called stale
  v_jr jsonb; v_jr_at timestamptz; v_jr_err text; v_jr_win int; v_jr_hist int; v_jr_failed timestamptz; v_jr_stale boolean; v_jh_state text;$old$,
$old$begin
  -- the scheduler history of the lane jobs is read from the summary that job lane-funnel keeps at the end of each run (security.lane_funnel_job_runs_refresh_v1), not from the
  -- scheduler's run table: that table has no index on (job, time), so the old two scans per job per lane read 82 thousand rows each time
  select r.jobs, r.measured_at, r.error, r.window_hours, r.history_hours, r.failed_at into v_jr, v_jr_at, v_jr_err, v_jr_win, v_jr_hist, v_jr_failed
    from pipeline.lane_funnel_job_runs r where r.singleton;
  -- stale: older than its threshold, a failed last summary, one made for another window, or none; a stale or missing summary is never shown as current (the lane verdict says unknown)
  v_jr_stale := v_jr is null or v_jr_at < now() - make_interval(secs => v_jr_stale_after) or v_jr_err is not null or v_jr_win is distinct from v_win or v_jr_hist is distinct from v_hist;
  for l in select * from pipeline.lane_funnel_lanes x where p_lane is null or x.lane = p_lane order by x.sort, x.lane loop$old$,
$old$          'running', coalesce(g.running, false), 'runs', coalesce(g.runs, 0), 'failed', coalesce(g.failed, 0), 'succeeded', coalesce(g.succeeded, 0),
          'last_start', g.last_start, 'last_end', g.last_end, 'last_status', g.last_status, 'last_message', g.last_message,
          'last_success', g.last_success, 'history_known', coalesce(jsonb_typeof(v_jr -> j.jobname) = 'object', false),$old$,
$old$        left join lateral (select x.* from jsonb_to_record(case when jsonb_typeof(v_jr -> j.jobname) = 'object' then v_jr -> j.jobname end)
                             as x(last_start timestamptz, last_end timestamptz, last_status text, last_message text, last_success timestamptz,
                                  runs integer, failed integer, succeeded integer, running boolean)) g on true) q;$old$,
$old$  return jsonb_build_object('at', now(), 'window_hours', v_win, 'lanes', v_out,
    -- how fresh the job history is: a summary older than its threshold, a failed last summary, or one made for another window is stale, never shown as current
    'job_history', jsonb_build_object('known', v_jr is not null, 'measured_at', v_jr_at, 'age_seconds', case when v_jr_at is not null then round(extract(epoch from now() - v_jr_at)) end,
      'stale', v_jr_stale,
      'error', v_jr_err, 'failed_at', v_jr_failed, 'window_hours', v_jr_win, 'history_hours', v_jr_hist, 'stale_after_seconds', v_jr_stale_after),$old$,
$old$    -- the state of the job history behind this lane's job results: unknown (no summary, or a job of the lane that is on is not in it), stale (older than its threshold, failed, other window) or current
    v_jh_state := case when v_jobs_n = 0 then 'current'
                       when v_jr is null or exists (select 1 from jsonb_array_elements(v_jobs) x where (x->>'active')::boolean and not (x->>'history_known')::boolean) then 'unknown'
                       when v_jr_stale then 'stale' else 'current' end;
    v_verdict := case
      when v_jobs_n = 0 and not exists (select 1 from jsonb_array_elements(v_sw) x) then 'unknown'
      when coalesce(v_off_switch, false) or (v_jobs_n > 0 and v_active = 0) then 'off'
      -- a verdict that rests on job results is not given from a history that is unknown or stale (all-zero counts would read as idle or transferring, an old failure as failing)
      when v_jh_state <> 'current' then 'unknown'$old$,
$old$    v_lane := jsonb_build_object('lane', l.lane, 'title', l.title, 'what', l.what, 'screen', l.screen, 'review_kinds', to_jsonb(l.review_kinds), 'verdict', v_verdict,
      'job_history_state', v_jh_state,$old$],
array[
$new$  v_fc jsonb := security.fc_budget_status_v1();$new$,
$new$begin
  for l in select * from pipeline.lane_funnel_lanes x where p_lane is null or x.lane = p_lane order by x.sort, x.lane loop$new$,
$new$          'running', coalesce(g.running, false), 'runs', coalesce(g.runs, 0), 'failed', coalesce(g.failed, 0), 'succeeded', coalesce(g.succeeded, 0),
          'last_start', r.start_time, 'last_end', r.end_time, 'last_status', r.status, 'last_message', left(r.return_message, 240),
          'last_success', g.last_success,$new$,
$new$        left join lateral (select d.start_time, d.end_time, d.status, d.return_message from cron.job_run_details d
                            where d.jobid = c.jobid and d.start_time > now() - make_interval(hours => v_hist) order by d.start_time desc limit 1) r on true
        left join lateral (select count(*) filter (where d.start_time > now() - make_interval(hours => v_win)) runs,
                                  count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'failed') failed,
                                  count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'succeeded') succeeded,
                                  bool_or(d.status in ('running', 'starting')) running, max(d.start_time) filter (where d.status = 'succeeded') last_success
                             from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - make_interval(hours => v_hist)) g on true) q;$new$,
$new$  return jsonb_build_object('at', now(), 'window_hours', v_win, 'lanes', v_out,$new$,
$new$    v_verdict := case
      when v_jobs_n = 0 and not exists (select 1 from jsonb_array_elements(v_sw) x) then 'unknown'
      when coalesce(v_off_switch, false) or (v_jobs_n > 0 and v_active = 0) then 'off'$new$,
$new$    v_lane := jsonb_build_object('lane', l.lane, 'title', l.title, 'what', l.what, 'screen', l.screen, 'review_kinds', to_jsonb(l.review_kinds), 'verdict', v_verdict,$new$]);

select pg_temp.edit_all('security.lane_funnel_refresh_v1(boolean)', 'bdba1e435806cb88a2d5cf8370b96ab7', 'e3e4280b536fe985822608139714434e',
array[
$old$  -- the scheduler history of the lane jobs, summarised in one pass for the lane funnel read, at the END of the run (after the stage counts, so it is as recent as the run can make it).
  -- Its own handler records a failure of the summary; this block makes sure that nothing it does can stop the run: the stage counts above are already written.
  begin
    perform security.lane_funnel_job_runs_refresh_v1(p_force);
  exception when others then
    raise warning 'lane funnel job history summary failed: %', left(sqlerrm, 300);  -- fixed: an error text is cut so the log line stays short
  end;
  perform set_config('statement_timeout', v_prev, true);
  return jsonb_build_object('counted', v_done, 'failed', v_failed);$old$],
array[
$new$  perform set_config('statement_timeout', v_prev, true);
  return jsonb_build_object('counted', v_done, 'failed', v_failed);$new$]);

select pg_temp.edit_all('security.intake_progress_repeats_v1()', 'c973fda29d27214c393dc6f4405a632c', '3f4a208ca8e0252eb17a1e21e73f80ca',
array[
$old$  -- materialised (10 Nov 2026): this list is tested once for every repeated row; written inline it was computed again for each row (a scan of the whole control log for 287 rows, 5.9 s)
  st as materialized (select a.created_at at from pipeline.admin_control_events a$old$],
array[
$new$  st as (select a.created_at at from pipeline.admin_control_events a$new$]);

select pg_temp.edit_all('security.process_results_recovery_v1()', '55686871dbffb3e2e381a5d11684d4e4', '0bb7a5bd32ba384bf341214c9a5a9c3c',
array[
$old$  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u)),
  -- the last run and its status of the five jobs, read from the scheduler history in one pass (it was two scans of it for each job)
  jr as (select r.jobid, max(r.start_time) last_run, (array_agg(r.status order by r.start_time desc))[1] last_status from cron.job_run_details r
          where r.jobid in (select x.jobid from cron.job x where x.jobname in ('calendar-reread', 'central-ai', 'provider-facts', 'intake-dates-apply', 'process-results')) group by r.jobid)$old$,
$old$    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select h.last_run from jr h where h.jobid = j.jobid),
                       'last_status', (select h.last_status from jr h where h.jobid = j.jobid))), '[]'::jsonb)$old$],
array[
$new$  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u))$new$,
$new$    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid),
                       'last_status', (select r.status from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1))), '[]'::jsonb)$new$]);

select pg_temp.edit_all('public.admin_layer23(text,jsonb)', '5b4c18db5115318ff0423b0a5d5c4248', '4c99a80f6899cda0d836dcc4196534de',
array[
$old$  -- only the kind and the university of each item are used here: the detail of every item (its stored copy and whether a newer copy exists) is not built (3 s, now 0.2 s)
  create temp table if not exists _l23_inbox on commit drop as select i.kind, i.provider_id from security.layer4_inbox_items_v2(null, null, null, false) i;$old$],
array[
$new$  create temp table if not exists _l23_inbox on commit drop as select i.kind, i.provider_id from security.layer4_inbox_items_v1() i;$new$]);

-- left in place (harmless): the settings lane_funnel.job_runs_refresh_seconds and lane_funnel.job_runs_stale_minutes, the table pipeline.lane_funnel_job_runs, the function
-- security.lane_funnel_job_runs_refresh_v1 (nothing calls it after this) and the index evidence_artifacts_link_queue_idx. To remove them too, the Platform Admin pastes these (a drop is not part of an applied migration):
-- drop function if exists security.lane_funnel_job_runs_refresh_v1(boolean);
-- drop table if exists pipeline.lane_funnel_job_runs;
-- drop index if exists pipeline.evidence_artifacts_link_queue_idx;
-- delete from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('lane_funnel.job_runs_refresh_seconds', 'lane_funnel.job_runs_stale_minutes');
