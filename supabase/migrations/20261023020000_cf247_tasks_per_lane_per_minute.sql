-- CF-247 (23 Oct 2026). Platform Admin 16:40, on 145 Read with AI tasks moving one a minute: "Yes, maximise to speed it up";
-- 16:43 "can you dry run 40 task in a minute" (dry run: 40 tasks moved in 1.3 seconds); 16:47 "i can't trust the task manager even
-- after refreshing it nothing seems moving. UI should be responsive and refresh, otherwise there is no trust on the platform".
-- 1 The task runner (job admin-jobs, each minute) moved one task per lane a minute. It now moves up to jobs.per_lane_per_tick tasks
--   per lane each minute (Settings › Pipeline settings, 1 to 40, set to 40), oldest first, and stops taking more after 40 seconds so
--   a minute's run ends before the next starts. Pause and cancel still act at the next provider.
-- 2 public.admin_jobs_pulse() gives the Task manager what shows it is alive: when the runner last ran, how many tasks it moves,
--   tasks waiting, running and finished in the last 15 minutes, each open task's place in its lane and its items by state, and the
--   values waiting for the AI reader.
-- Replaces: nothing (security.admin_jobs_tick_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'jobs.per_lane_per_tick', 'Tasks moved per lane each minute',
        'How many tasks started by people (Scheduled jobs › Task manager) the task runner moves forward in each lane every minute, oldest first. It stops taking more after 40 seconds. 1 runs tasks one after another.',
        'number', '40'::jsonb, '1', '40', 'tasks', 101, 'Job sizes', 'job admin-jobs',
        'Platform Admin 23 Oct 2026 16:40: maximise to speed it up')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting', 'pipeline.jobs.per_lane_per_tick',
        jsonb_build_object('before', 1, 'after', 40, 'range', '1 to 40', 'reason', 'Platform Admin 23 Oct 2026 16:40: maximise to speed it up (migration 20261023020000)'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', '865ed3c4a8b11aa9abe3368d7ee9cab1', array[
  array[$o$declare v_lane text; v_j pipeline.admin_jobs%rowtype; v_fin boolean; v_out jsonb := '[]'::jsonb;$o$,
        $n$declare v_lane text; v_j pipeline.admin_jobs%rowtype; v_fin boolean; v_out jsonb := '[]'::jsonb;
        v_n int := greatest(1, least(security.pipeline_num_v1('jobs.per_lane_per_tick', 1)::int, 40)); v_t0 timestamptz := clock_timestamp();$n$],
  array[$o$    select * into v_j from pipeline.admin_jobs j where j.lane = v_lane and j.state in ('queued', 'running')
     order by (j.state = 'running') desc, j.created_at limit 1 for update skip locked;
    if v_j.id is null then continue; end if;$o$,
        $n$    -- 23 Oct 2026: up to jobs.per_lane_per_tick tasks per lane each minute, oldest first
    for v_j in select * from pipeline.admin_jobs j where j.lane = v_lane and j.state in ('queued', 'running')
     order by (j.state = 'running') desc, j.created_at limit v_n for update skip locked loop
    exit when clock_timestamp() - v_t0 > interval '40 seconds';  -- fixed: the runner is called each minute; a run ends before the next starts$n$],
  array[$o$    v_out := v_out || jsonb_build_object('id', v_j.id, 'state', case when v_fin then 'done' else 'running' end);
  end loop;$o$,
        $n$    v_out := v_out || jsonb_build_object('id', v_j.id, 'state', case when v_fin then 'done' else 'running' end);
    end loop;
  end loop;$n$]]);


-- 2 the Task manager's pulse ---------------------------------------------------------------------------------------------------------
create or replace function public.admin_jobs_pulse()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'now', now(),
    'runner', (select jsonb_build_object('last_run', d.start_time, 'status', d.status, 'seconds_ago', extract(epoch from now() - d.start_time)::int)
                 from cron.job_run_details d join cron.job c on c.jobid = d.jobid where c.jobname = 'admin-jobs' order by d.start_time desc limit 1),
    'per_lane', greatest(1, least(security.pipeline_num_v1('jobs.per_lane_per_tick', 1)::int, 40)),
    'queued', (select count(*) from pipeline.admin_jobs where state = 'queued'),
    'running', (select count(*) from pipeline.admin_jobs where state = 'running'),
    'paused', (select count(*) from pipeline.admin_jobs where state = 'paused'),
    'finished_15m', (select count(*) from pipeline.admin_jobs where state in ('done', 'failed', 'cancelled') and finished_at > now() - interval '15 minutes'),
    'last_finished', (select max(finished_at) from pipeline.admin_jobs where state in ('done', 'failed', 'cancelled')),
    'ai_waiting', (select count(*) from pipeline.field_enrich_items where state in ('ai', 'leased')),
    'ai_done_15m', (select count(*) from pipeline.field_enrich_items where source in ('ai_stored', 'ai_title', 'ai_city') and state in ('filled', 'skipped', 'review') and updated_at > now() - interval '15 minutes'),
    'jobs', coalesce((select jsonb_object_agg(o.id, jsonb_build_object('place', o.place, 'items', o.items))
       from (select j.id, row_number() over (partition by j.lane order by (j.state = 'running') desc, j.created_at) place,
                    (select jsonb_build_object('total', count(*), 'queued', count(*) filter (where i.state in ('queued', 'waiting')),
                                               'with_ai', count(*) filter (where i.state in ('ai', 'leased')),
                                               'done', count(*) filter (where i.state in ('filled', 'skipped', 'review', 'failed')),
                                               'filled', count(*) filter (where i.state = 'filled'))
                       from pipeline.field_enrich_items i where i.job_id = j.id) items
               from pipeline.admin_jobs j where j.state in ('queued', 'running', 'paused')) o), '{}'::jsonb));
end $function$;
revoke execute on function public.admin_jobs_pulse() from public, anon;
grant execute on function public.admin_jobs_pulse() to authenticated;
comment on function public.admin_jobs_pulse() is 'CF-247 23 Oct 2026: what shows the Task manager is alive (runner last run, tasks moved per minute, waiting, running, finished in 15 minutes, each open task''s place in line and items, AI reader backlog). Read only.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_jobs_pulse', 'Operations', 'Task manager pulse: runner last run, place in line, items by state, AI backlog', 'active', '{}', '20261023020000')
on conflict (kind, name) do nothing;

select 'task runner moves up to jobs.per_lane_per_tick tasks per lane each minute; Task manager pulse' ok;
