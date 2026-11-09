-- CF-247 Operations load speed (Platform Admin P1, found live 10 Nov 2026 after #961): every cold load of Admin > Layer 2/3 > Operations showed the red banner "The database took too long to
-- answer and stopped the request". The API role stops a request at 8 seconds. Measured in the browser: admin_lane_funnel_v1 HTTP 500 at 8.2 s, admin_intake_progress_v1 7.9 to 10.8 s,
-- admin_progress_read 3.4 to 4.4 s, admin_layer23 3.1 to 3.3 s. In the database, admin_lane_funnel_v1(null) took 4.6, 9.4, 20.2 and 11.9 s on four consecutive reads.
--
-- Why (each measured with explain analyze on the live project, read only):
--   1 security.lane_funnel_v1                  4.5 to 4.6 s warm, 9 to 20 s on a busy minute. Every lane job did two lateral scans of cron.job_run_details (last attempt; runs in the window).
--                                              That table has only its primary key, 159 thousand rows (82.6 thousand in the last 48 hours); the plan was 112 sequential scans of 6,583 buffers.
--   2 security.intake_progress_repeats_v1      5.9 s, the cause of the intake status view taking 3.6 to 3.8 s (once 7 s). The CTE st was referenced once, so Postgres inlined it and ran
--                                              the control-log read again for every repeat pair: 287 sequential scans of pipeline.admin_control_events.
--   3 public.admin_layer23('operations')       2.1 to 3.7 s. It built the full Layer 4 inbox with its evidence join only to count kinds and providers. layer4_inbox_items_v2 with the
--                                              detail switched off (p_detail false) gives the same kinds and providers in 0.15 to 0.22 s.
--   4 security.process_results_recovery_v1     0.8 to 1.3 s. Its job arm ran two correlated scans (last run, last status) per job over cron.job_run_details: 10 sequential scans for five jobs.
--   5 security.admin_live_activity_v1          0.9 to 1.1 s (behind admin_progress_read('running')); 0.93 s of it is the count of the evidence link queue, which has no index that matches its
--                                              filter. The partial index below fits that filter exactly (index only scan). NOT measurable on live without creating it: verified on synthetic data only.
--   Every other read of the tab was under 0.6 s and is unchanged.
--
-- What (the UI shows no change; the answers keep their shape; nothing the consumer API reads is touched):
--   a pipeline.lane_funnel_job_runs            one row: the scheduler history of the lane jobs, summarised in ONE grouped pass over cron.job_run_details, with measured_at, the window and
--                                              history it was made for, took_ms, and error / failed_at (a failed summary keeps the last good rows).
--   b security.lane_funnel_job_runs_refresh_v1 the only writer. It is called at the END of each run of the existing lane-funnel job (security.lane_funnel_refresh_v1, every minute; after the
--                                              stage counts, inside its own handler, so it can never stop the run): no new job, no new schedule. It is
--                                              not due until the summary is older than lane_funnel.job_runs_refresh_seconds, or the window or history setting changed. It excludes its own backend, so
--                                              the job never reports itself as running.
--   c security.lane_funnel_v1                  reads the job fields from the summary. The shape is the same; added only: job_history (measured_at, age, stale, known, error) and history_known per job.
--                                              A summary older than its threshold (the longer of lane_funnel.job_runs_stale_minutes and two looks of the job plus 30 s, so the two settings can never leave it stale for good), a failed one,
--                                              one made for another window, or none at all is reported stale or unknown, never as current; a job missing from the summary is unknown, never "0 runs".
--                                              Each lane says job_history_state (current, stale, unknown) and a lane whose verdict would rest on a stale or unknown history has the verdict unknown (a lane that is off stays off).
--                                              The screen shows the summary's time beside every running state: the state is as at that time, up to a minute old. The stage counts (the lane readings) are unchanged and still live.
--   d security.intake_progress_repeats_v1      st as materialized: the control log is read once.
--   e security.process_results_recovery_v1     one grouped pass for the job arm (last run and last status of the five jobs by name, over the whole history, as before).
--   f public.admin_layer23                     the operations action builds the inbox without its evidence detail (kind and provider are all it uses).
--   g pipeline.evidence_artifacts_link_queue_idx  a partial index whose predicate is the filter of the link queue count (no table scan of the artefacts).
--   h 2 settings (G2, toolset pipeline, section Lane funnels): lane_funnel.job_runs_refresh_seconds (45) and lane_funnel.job_runs_stale_minutes (5). Pipeline settings shows both with label,
--     range, unit and used_by; they are changed there with a reason. No operational number is written into the code; the one fixed value (the summary is also due whenever its window changed) is a rule, not a number.
--
-- No retention purge of cron.job_run_details is warranted: it is already trimmed daily by the jobs cron-history-trim (rows ended over 3 days ago, 04:23) and cron-history-retention (over 14 days,
-- 03:37). Read 10 Nov 2026: 159,736 rows, 82,704 in the last 48 hours, oldest 5 Nov 2026 16:47 UTC. The table is small enough for one grouped pass (85 ms by explain analyze on live, once a minute); the cost
-- was the 112 scans per read, not the size. Nothing is deleted or truncated here.
--
-- Consumer API (G3): nothing in public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, schema api or the five edge functions is read, changed, dropped or
-- renamed. The new table is not read by any of them. Consumer API change approved: not applicable (no change).
-- Controls: all five functions keep SECURITY DEFINER, search_path '' and their rank gate (the text of each gate is unchanged); the new writer is revoked from public, anon and authenticated.
-- Housekeeping: every edit is guarded by the md5 of the live body; if a function differs from what this change edits, the migration raises and nothing is applied. Forward recovery (md5 back to the
-- production text, byte for byte): supabase/held/operations_load_speed_forward_recovery.sql. Equivalence on live data (read only): supabase/held/operations_load_speed_equivalence.sql.
-- Nothing is dropped, deleted or renamed by this migration.
-- Replaces: the per-request scans of cron.job_run_details in security.lane_funnel_v1 (two per job per lane) and security.process_results_recovery_v1 (two per job); the per-pair read of pipeline.admin_control_events in security.intake_progress_repeats_v1; the full Layer 4 inbox detail build in public.admin_layer23('operations')
-- Retires: nothing
--
-- Body md5 of each function (pg_proc.prosrc, read 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp): live -> after this migration.
--   security.lane_funnel_v1(text) cd8ecc118783da99f50c6fbd035cd3c1 -> a52dc6bbcea06b7eaa2a5bb40a05d0c4
--   security.lane_funnel_refresh_v1(boolean) e3e4280b536fe985822608139714434e -> bdba1e435806cb88a2d5cf8370b96ab7
--   security.intake_progress_repeats_v1() 3f4a208ca8e0252eb17a1e21e73f80ca -> c973fda29d27214c393dc6f4405a632c
--   security.process_results_recovery_v1() 0bb7a5bd32ba384bf341214c9a5a9c3c -> 55686871dbffb3e2e381a5d11684d4e4
--   public.admin_layer23(text,jsonb) 4c99a80f6899cda0d836dcc4196534de -> 5b4c18db5115318ff0423b0a5d5c4248

do $g$
declare r record;
begin
  for r in select * from (values ('security.lane_funnel_v1(text)'), ('security.lane_funnel_refresh_v1(boolean)'), ('security.intake_progress_repeats_v1()'), ('security.process_results_recovery_v1()'),
                                 ('public.admin_layer23(text,jsonb)'), ('security.layer4_inbox_items_v2(uuid,text,text[],boolean)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  for r in select * from (values ('pipeline.lane_funnel_lanes'), ('pipeline.platform_toolset_settings'), ('pipeline.automation_catalogue'), ('pipeline.component_register'),
                                 ('pipeline.evidence_artifacts'), ('pipeline.evidence_link_index_state')) v(rel) loop
    if to_regclass(r.rel) is null then raise exception 'required % is missing', r.rel; end if;
  end loop;
end $g$;

-- 1. the settings (G2): how often the scheduler-history summary is made again, and when it is shown as stale ----------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'lane_funnel.job_runs_refresh_seconds', 'Lane funnels: read the scheduler history again after',
  'Job lane-funnel summarises the scheduler history of the lane jobs (last attempt, last success, runs in the window, running now) in one pass and keeps the summary; the lane funnel read on Layer 2/3 > Operations shows the summary and never scans the scheduler history. The summary is made at the end of each run of the job, when it is older than this or when the window or history setting changed. The job looks every minute, so a value above 60 seconds means every second look.',
  'number', to_jsonb(45), 10, 600, 'seconds', 1710, 'CF-247 Operations load speed (10 Nov 2026): the lane funnel read stops scanning the scheduler history', 'Lane funnels', 'security.lane_funnel_job_runs_refresh_v1 (job lane-funnel)'),
 ('pipeline', 'lane_funnel.job_runs_stale_minutes', 'Lane funnels: job history marked stale after',
  'The job columns of the lane funnels (running now, last attempt, runs) are marked stale when their summary is older than this, when the last summary failed, or when it was made for another window. A stale summary is shown with a notice and its age, and a lane whose verdict rests on it says unknown; it is never shown as current. The time used is the longer of this and two looks of the job (the refresh time above, or one minute if that is shorter) plus 30 seconds, so no allowed pair of settings leaves the history stale for good.',
  'number', to_jsonb(5), 2, 120, 'minutes', 1711, 'CF-247 Operations load speed (10 Nov 2026)', 'Lane funnels', 'security.lane_funnel_v1 (stale after the longer of this and 2 x the look interval of job lane-funnel + 30 s)')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set used_by = used_by || '; security.lane_funnel_job_runs_refresh_v1'
 where toolset_key = 'pipeline' and key in ('lane_funnel.gain_window_hours', 'lane_funnel.run_history_hours') and used_by not like '%lane_funnel_job_runs_refresh_v1%';

-- 2. the summary table ------------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.lane_funnel_job_runs (
  singleton boolean primary key default true check (singleton),
  measured_at timestamptz not null default now(),
  window_hours integer,
  history_hours integer,
  jobs jsonb,
  took_ms integer,
  error text,
  failed_at timestamptz);
comment on table pipeline.lane_funnel_job_runs is 'CF-247 Operations load speed (10 Nov 2026): one row, the scheduler history of every job named by pipeline.lane_funnel_lanes (last attempt, last success, runs, failed and succeeded in the window, running now), summarised in one pass by job lane-funnel (security.lane_funnel_job_runs_refresh_v1) so the lane funnel read never scans cron.job_run_details (82 thousand rows were scanned twice per job per lane on every read). measured_at, window_hours, history_hours and jobs are those of the last successful summary; a later failure sets error and failed_at and keeps them, and the read marks them stale. Never read by the consumer API.';
alter table pipeline.lane_funnel_job_runs enable row level security;
revoke all on pipeline.lane_funnel_job_runs from public, anon, authenticated;

-- 3. the only writer (run by job lane-funnel) ---------------------------------------------------------------------------------------------------------------------
create or replace function security.lane_funnel_job_runs_refresh_v1(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_every int := security.pipeline_num_v1('lane_funnel.job_runs_refresh_seconds', 45)::int;
  v_win int := security.pipeline_num_v1('lane_funnel.gain_window_hours', 24)::int;
  v_hist int := security.pipeline_num_v1('lane_funnel.run_history_hours', 48)::int;
  v_t0 timestamptz; v_rows jsonb; v_due boolean;
begin
  if to_regnamespace('cron') is null then return jsonb_build_object('refreshed', false, 'skipped', 'no scheduler'); end if;
  -- due: never summarised, older than the setting, made for another window (a changed window is picked up at once), or the last try failed and its wait is over
  select coalesce(p_force or r.measured_at is null or coalesce(r.failed_at, r.measured_at) < now() - make_interval(secs => v_every)
                  or r.window_hours is distinct from v_win or r.history_hours is distinct from v_hist, true)
    into v_due from (select 1) one left join pipeline.lane_funnel_job_runs r on r.singleton;
  if not v_due then return jsonb_build_object('refreshed', false, 'skipped', 'not due'); end if;
  v_t0 := clock_timestamp();
  begin
    -- ONE pass over the scheduler history for every job of every lane; the run in progress (this one, when job lane-funnel calls it) is not counted as the job's last attempt
    with want as (select distinct j.jobname from pipeline.lane_funnel_lanes l cross join lateral unnest(l.jobs) j(jobname)),
    ids as (select c.jobid, w.jobname from want w join cron.job c on c.jobname = w.jobname),
    h as (
      select d.jobid, max(d.start_time) as last_start, (array_agg(d.end_time order by d.start_time desc))[1] as last_end, (array_agg(d.status order by d.start_time desc))[1] as last_status,
             (array_agg(left(d.return_message, 240) order by d.start_time desc))[1] as last_message,  -- fixed: the scheduler's message is cut so a summary row stays small
             max(d.start_time) filter (where d.status = 'succeeded') as last_success,
             count(*) filter (where d.start_time > now() - make_interval(hours => v_win)) as runs,
             count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'failed') as failed,
             count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'succeeded') as succeeded,
             bool_or(d.status in ('running', 'starting')) as running
        from cron.job_run_details d
       where d.jobid in (select i.jobid from ids i) and d.start_time > now() - make_interval(hours => v_hist) and d.job_pid is distinct from pg_backend_pid()
       group by d.jobid)
    select coalesce(jsonb_object_agg(w.jobname, jsonb_build_object('last_start', h.last_start, 'last_end', h.last_end, 'last_status', h.last_status, 'last_message', h.last_message,
             'last_success', h.last_success, 'runs', coalesce(h.runs, 0), 'failed', coalesce(h.failed, 0), 'succeeded', coalesce(h.succeeded, 0), 'running', coalesce(h.running, false))), '{}'::jsonb)
      into v_rows from want w left join ids i on i.jobname = w.jobname left join h on h.jobid = i.jobid;
    insert into pipeline.lane_funnel_job_runs as r(singleton, measured_at, window_hours, history_hours, jobs, took_ms, error, failed_at)
      values (true, clock_timestamp(), v_win, v_hist, v_rows,
              (extract(epoch from clock_timestamp() - v_t0) * 1000)::int,  -- fixed: seconds to milliseconds
              null, null)
      on conflict (singleton) do update set measured_at = excluded.measured_at, window_hours = excluded.window_hours, history_hours = excluded.history_hours, jobs = excluded.jobs,
                                            took_ms = excluded.took_ms, error = null, failed_at = null;
    return jsonb_build_object('refreshed', true, 'jobs', (select count(*) from jsonb_object_keys(v_rows)));
  exception when others then
    -- a failed summary never overwrites the last good one: its rows and time stay, the error and its time are added (the read marks the history stale)
    insert into pipeline.lane_funnel_job_runs as r(singleton, measured_at, window_hours, history_hours, jobs, took_ms, error, failed_at)
      values (true, clock_timestamp(), v_win, v_hist, null,
              (extract(epoch from clock_timestamp() - v_t0) * 1000)::int,  -- fixed: seconds to milliseconds
              left(sqlerrm, 300),  -- fixed: an error text is cut so the row stays small
              clock_timestamp())
      on conflict (singleton) do update set took_ms = excluded.took_ms, error = excluded.error, failed_at = excluded.failed_at;
    return jsonb_build_object('refreshed', false, 'error', left(sqlerrm, 300));  -- fixed: an error text is cut so the answer stays small
  end;
end $function$;
revoke all on function security.lane_funnel_job_runs_refresh_v1(boolean) from public, anon, authenticated;

-- 4. the md5-guarded edits ------------------------------------------------------------------------------------------------------------------------------------------
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

select pg_temp.edit_all('security.lane_funnel_v1(text)', 'cd8ecc118783da99f50c6fbd035cd3c1', 'a52dc6bbcea06b7eaa2a5bb40a05d0c4',
array[
$old$  v_fc jsonb := security.fc_budget_status_v1();$old$,
$old$begin
  for l in select * from pipeline.lane_funnel_lanes x where p_lane is null or x.lane = p_lane order by x.sort, x.lane loop$old$,
$old$          'running', coalesce(g.running, false), 'runs', coalesce(g.runs, 0), 'failed', coalesce(g.failed, 0), 'succeeded', coalesce(g.succeeded, 0),
          'last_start', r.start_time, 'last_end', r.end_time, 'last_status', r.status, 'last_message', left(r.return_message, 240),
          'last_success', g.last_success,$old$,
$old$        left join lateral (select d.start_time, d.end_time, d.status, d.return_message from cron.job_run_details d
                            where d.jobid = c.jobid and d.start_time > now() - make_interval(hours => v_hist) order by d.start_time desc limit 1) r on true
        left join lateral (select count(*) filter (where d.start_time > now() - make_interval(hours => v_win)) runs,
                                  count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'failed') failed,
                                  count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'succeeded') succeeded,
                                  bool_or(d.status in ('running', 'starting')) running, max(d.start_time) filter (where d.status = 'succeeded') last_success
                             from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - make_interval(hours => v_hist)) g on true) q;$old$,
$old$  return jsonb_build_object('at', now(), 'window_hours', v_win, 'lanes', v_out,$old$,
$old$    v_verdict := case
      when v_jobs_n = 0 and not exists (select 1 from jsonb_array_elements(v_sw) x) then 'unknown'
      when coalesce(v_off_switch, false) or (v_jobs_n > 0 and v_active = 0) then 'off'$old$,
$old$    v_lane := jsonb_build_object('lane', l.lane, 'title', l.title, 'what', l.what, 'screen', l.screen, 'review_kinds', to_jsonb(l.review_kinds), 'verdict', v_verdict,$old$],
array[
$new$  v_fc jsonb := security.fc_budget_status_v1();
  -- how old the job-history summary may be before it is marked stale, in seconds: the longer of the setting and two looks of job lane-funnel plus a grace, so allowed settings never leave it stale for good
  v_jr_stale_after int := greatest(security.pipeline_num_v1('lane_funnel.job_runs_stale_minutes', 5)::int * 60,  -- fixed: minutes to seconds
                                   2 * greatest(security.pipeline_num_v1('lane_funnel.job_runs_refresh_seconds', 45)::int, 60) + 30);  -- fixed: job lane-funnel looks once a minute (its schedule), so a summary is made again at most every second look; two looks and 30 s of grace before it is called stale
  v_jr jsonb; v_jr_at timestamptz; v_jr_err text; v_jr_win int; v_jr_hist int; v_jr_failed timestamptz; v_jr_stale boolean; v_jh_state text;$new$,
$new$begin
  -- the scheduler history of the lane jobs is read from the summary that job lane-funnel keeps at the end of each run (security.lane_funnel_job_runs_refresh_v1), not from the
  -- scheduler's run table: that table has no index on (job, time), so the old two scans per job per lane read 82 thousand rows each time
  select r.jobs, r.measured_at, r.error, r.window_hours, r.history_hours, r.failed_at into v_jr, v_jr_at, v_jr_err, v_jr_win, v_jr_hist, v_jr_failed
    from pipeline.lane_funnel_job_runs r where r.singleton;
  -- stale: older than its threshold, a failed last summary, one made for another window, or none; a stale or missing summary is never shown as current (the lane verdict says unknown)
  v_jr_stale := v_jr is null or v_jr_at < now() - make_interval(secs => v_jr_stale_after) or v_jr_err is not null or v_jr_win is distinct from v_win or v_jr_hist is distinct from v_hist;
  for l in select * from pipeline.lane_funnel_lanes x where p_lane is null or x.lane = p_lane order by x.sort, x.lane loop$new$,
$new$          'running', coalesce(g.running, false), 'runs', coalesce(g.runs, 0), 'failed', coalesce(g.failed, 0), 'succeeded', coalesce(g.succeeded, 0),
          'last_start', g.last_start, 'last_end', g.last_end, 'last_status', g.last_status, 'last_message', g.last_message,
          'last_success', g.last_success, 'history_known', coalesce(jsonb_typeof(v_jr -> j.jobname) = 'object', false),$new$,
$new$        left join lateral (select x.* from jsonb_to_record(case when jsonb_typeof(v_jr -> j.jobname) = 'object' then v_jr -> j.jobname end)
                             as x(last_start timestamptz, last_end timestamptz, last_status text, last_message text, last_success timestamptz,
                                  runs integer, failed integer, succeeded integer, running boolean)) g on true) q;$new$,
$new$  return jsonb_build_object('at', now(), 'window_hours', v_win, 'lanes', v_out,
    -- how fresh the job history is: a summary older than its threshold, a failed last summary, or one made for another window is stale, never shown as current
    'job_history', jsonb_build_object('known', v_jr is not null, 'measured_at', v_jr_at, 'age_seconds', case when v_jr_at is not null then round(extract(epoch from now() - v_jr_at)) end,
      'stale', v_jr_stale,
      'error', v_jr_err, 'failed_at', v_jr_failed, 'window_hours', v_jr_win, 'history_hours', v_jr_hist, 'stale_after_seconds', v_jr_stale_after),$new$,
$new$    -- the state of the job history behind this lane's job results: unknown (no summary, or a job of the lane that is on is not in it), stale (older than its threshold, failed, other window) or current
    v_jh_state := case when v_jobs_n = 0 then 'current'
                       when v_jr is null or exists (select 1 from jsonb_array_elements(v_jobs) x where (x->>'active')::boolean and not (x->>'history_known')::boolean) then 'unknown'
                       when v_jr_stale then 'stale' else 'current' end;
    v_verdict := case
      when v_jobs_n = 0 and not exists (select 1 from jsonb_array_elements(v_sw) x) then 'unknown'
      when coalesce(v_off_switch, false) or (v_jobs_n > 0 and v_active = 0) then 'off'
      -- a verdict that rests on job results is not given from a history that is unknown or stale (all-zero counts would read as idle or transferring, an old failure as failing)
      when v_jh_state <> 'current' then 'unknown'$new$,
$new$    v_lane := jsonb_build_object('lane', l.lane, 'title', l.title, 'what', l.what, 'screen', l.screen, 'review_kinds', to_jsonb(l.review_kinds), 'verdict', v_verdict,
      'job_history_state', v_jh_state,$new$]);

select pg_temp.edit_all('security.lane_funnel_refresh_v1(boolean)', 'e3e4280b536fe985822608139714434e', 'bdba1e435806cb88a2d5cf8370b96ab7',
array[
$old$  perform set_config('statement_timeout', v_prev, true);
  return jsonb_build_object('counted', v_done, 'failed', v_failed);$old$],
array[
$new$  -- the scheduler history of the lane jobs, summarised in one pass for the lane funnel read, at the END of the run (after the stage counts, so it is as recent as the run can make it).
  -- Its own handler records a failure of the summary; this block makes sure that nothing it does can stop the run: the stage counts above are already written.
  begin
    perform security.lane_funnel_job_runs_refresh_v1(p_force);
  exception when others then
    raise warning 'lane funnel job history summary failed: %', left(sqlerrm, 300);  -- fixed: an error text is cut so the log line stays short
  end;
  perform set_config('statement_timeout', v_prev, true);
  return jsonb_build_object('counted', v_done, 'failed', v_failed);$new$]);

select pg_temp.edit_all('security.intake_progress_repeats_v1()', '3f4a208ca8e0252eb17a1e21e73f80ca', 'c973fda29d27214c393dc6f4405a632c',
array[
$old$  st as (select a.created_at at from pipeline.admin_control_events a$old$],
array[
$new$  -- materialised (10 Nov 2026): this list is tested once for every repeated row; written inline it was computed again for each row (a scan of the whole control log for 287 rows, 5.9 s)
  st as materialized (select a.created_at at from pipeline.admin_control_events a$new$]);

select pg_temp.edit_all('security.process_results_recovery_v1()', '0bb7a5bd32ba384bf341214c9a5a9c3c', '55686871dbffb3e2e381a5d11684d4e4',
array[
$old$  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u))$old$,
$old$    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid),
                       'last_status', (select r.status from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1))), '[]'::jsonb)$old$],
array[
$new$  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u)),
  -- the last run and its status of the five jobs, read from the scheduler history in one pass (it was two scans of it for each job)
  jr as (select r.jobid, max(r.start_time) last_run, (array_agg(r.status order by r.start_time desc))[1] last_status from cron.job_run_details r
          where r.jobid in (select x.jobid from cron.job x where x.jobname in ('calendar-reread', 'central-ai', 'provider-facts', 'intake-dates-apply', 'process-results')) group by r.jobid)$new$,
$new$    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select h.last_run from jr h where h.jobid = j.jobid),
                       'last_status', (select h.last_status from jr h where h.jobid = j.jobid))), '[]'::jsonb)$new$]);

select pg_temp.edit_all('public.admin_layer23(text,jsonb)', '4c99a80f6899cda0d836dcc4196534de', '5b4c18db5115318ff0423b0a5d5c4248',
array[
$old$  create temp table if not exists _l23_inbox on commit drop as select i.kind, i.provider_id from security.layer4_inbox_items_v1() i;$old$],
array[
$new$  -- only the kind and the university of each item are used here: the detail of every item (its stored copy and whether a newer copy exists) is not built (3 s, now 0.2 s)
  create temp table if not exists _l23_inbox on commit drop as select i.kind, i.provider_id from security.layer4_inbox_items_v2(null, null, null, false) i;$new$]);

-- 5. one plain index: the queue count of job evidence-link-index (a line of public.admin_live_activity_v1, read by the Running view of Operations) ----------------------
-- The count walked 104,722 evidence rows through evidence_source_idx and their heap (86 thousand buffers, 0.93 s) to find the few without an index state. The index holds exactly the rows
-- the count tests (same condition, so the count's own text is unchanged and answers from the index alone). A plain index: nothing is dropped; the build over the 208 thousand rows takes a moment.
-- Benefit shown (tests/fixtures/operations-load-speed/index-benefit.sql, a scratch table of the live size: 208 thousand rows, 41,600 heap pages): the count took 350 to 630 ms with a
-- sequential pass over the heap and 85 to 170 ms as an index only scan with no heap fetch (2.7 to 5 times faster). The live figure (0.93 s) cannot be measured without the index.
create index if not exists evidence_artifacts_link_queue_idx on pipeline.evidence_artifacts (source_id, id)
  where storage_path is not null and storage_path !~ '^[a-z-]+://' and evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
    and (mime_type ilike '%html%' or mime_type ilike '%json%');
comment on index pipeline.evidence_artifacts_link_queue_idx is 'CF-247 Operations load speed (10 Nov 2026): the evidence the link indexer may read (storage address, type and mime type as tested by the queue count of job evidence-link-index in security.admin_live_activity_v1), so that count is answered from the index.';

-- 6. the job description, the register ------------------------------------------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set description = description || ' Also summarises the scheduler history of the lane jobs for the lane funnel read (one pass, kept in pipeline.lane_funnel_job_runs), so that screen never scans it.'
 where jobname = 'lane-funnel' and description not like '%scheduler history of the lane jobs%';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.lane_funnel_job_runs', 'Platform', 'Reports', 'Operations load speed: the scheduler history of the lane jobs, summarised by job lane-funnel so the lane funnel read never scans cron.job_run_details', 'active', '{}', '20261110020000'),
 ('function', 'security.lane_funnel_job_runs_refresh_v1', 'Platform', 'Reports', 'Operations load speed: the only writer of the lane job history summary (called by security.lane_funnel_refresh_v1, job lane-funnel)', 'active', '{}', '20261110020000')
on conflict do nothing;

-- 7. prime the summary (so the first read after release is not unknown), then post-check -------------------------------------------------------------------------------
do $prime$
begin
  if to_regnamespace('cron') is not null then perform security.lane_funnel_job_runs_refresh_v1(true); end if;
end $prime$;

do $post$
declare v_def text;
begin
  v_def := pg_get_functiondef('security.lane_funnel_v1(text)'::regprocedure);
  if position('cron.job_run_details' in v_def) > 0 then raise exception 'operations load speed post-check: the lane funnel read still scans the scheduler history'; end if;
  if position('security.lane_funnel_job_runs_refresh_v1' in pg_get_functiondef('security.lane_funnel_refresh_v1(boolean)'::regprocedure)) = 0 then
    raise exception 'operations load speed post-check: job lane-funnel does not make the job history summary';
  end if;
  v_def := pg_get_functiondef('security.lane_funnel_refresh_v1(boolean)'::regprocedure);
  if position('lane_funnel_job_runs_refresh_v1' in v_def) < position('insert into pipeline.lane_funnel_history' in v_def) then
    raise exception 'operations load speed post-check: the job history summary is made before the stage counts, not at the end of the run';
  end if;
  if position('as materialized' in pg_get_functiondef('security.intake_progress_repeats_v1()'::regprocedure)) = 0 then raise exception 'operations load speed post-check: the repeat check is not materialised'; end if;
  if position('layer4_inbox_items_v2(null, null, null, false)' in pg_get_functiondef('public.admin_layer23(text,jsonb)'::regprocedure)) = 0 then raise exception 'operations load speed post-check: Layer 2/3 operations still builds the inbox detail'; end if;
  if to_regnamespace('cron') is not null and not exists (select 1 from pipeline.lane_funnel_job_runs r where r.singleton and (r.jobs is not null or r.error is not null)) then
    raise exception 'operations load speed post-check: the job history summary was not made';
  end if;
  raise notice 'operations load speed: 5 function edits, 1 table, 1 index, 2 settings';
end $post$;
