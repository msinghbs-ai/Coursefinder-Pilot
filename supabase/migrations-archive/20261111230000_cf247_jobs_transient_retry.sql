-- CF-247 F-OPS (F-CDESC root cause 2; Platform Admin 11 Nov 2026 13:45 AEDT "What can we fix now ... Do it yourself and deliver outcome"): a task whose slice hits a passing database error is tried again next run instead of failing for good.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 10 to 11 Nov 2026). The standing task bba24b11 ("Fill the gaps · all countries (standing)", 3,001 items) failed one minute in on 10 Nov 06:24Z with "deadlock detected" (SQLSTATE 40P01). security.admin_jobs_tick_v1
-- turns ANY slice error into state failed and the task is never run again (public.admin_jobs can resume only a paused task). Its 3,001 items stayed queued with no runner, the 1,500 courses it held were never read again, and because the day's room of
-- enrich.course_text_items_per_day counts items created by standing tasks in the last 24 hours, field-gap-queue created no course description work for the rest of the day. The Integration Controller resumed it by hand on 11 Nov 06:05 AEDT
-- (register 11 Nov 06:35). A deadlock, a serialization failure or a lock that is not available is transient: the same slice succeeds on a later run.
--
-- What this changes: security.admin_jobs_tick_v1(integer) only (md5-guarded body replacement). In the slice's exception handler, SQLSTATE 40P01, 40001 or 55P03 leaves the task running (its slice's work was rolled back), records an event
-- "transient database error (<code>), tried again next run", and the next run (each minute) takes the task again; after jobs.transient_retry_max such events for a task (new setting, default 5, range 0 to 50; 0 keeps today's behaviour) the
-- error fails the task as today. Every other error fails the task exactly as today. Cancel, pause, start, finish and close are unchanged. A statement time-out of the runner (query_canceled) was never caught here and is unchanged: it
-- cancels the run and the task, still running, is taken again next run.
--
-- Live definition this change edits (pg_proc.prosrc md5, read 11 Nov 2026 14:30 AEDT), before -> after (the migration stops, and applies nothing, if the live body is neither):
--   security.admin_jobs_tick_v1(integer)   f95f8c26d9bbd4fa07a74bcd0797e198 -> d25e4bad56b632eae40d15f69ddfc4f4
-- Replaces: the body of security.admin_jobs_tick_v1 is replaced in place (md5-guarded); failing a task on a transient database error is replaced by a bounded retry on the next run
-- Retires: nothing
-- Nothing is dropped or deleted. One setting is added (jobs.transient_retry_max, with label, range, unit and used_by) and its addition is recorded in admin_control_events. Forward recovery (restores the previous body byte for byte):
-- supabase/held/jobs_transient_retry_forward_recovery.sql

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'jobs.transient_retry_max', 'Tasks: tries after a passing database error',
        'When a task''s step meets a passing database error (a deadlock, a serialization failure or a lock that is not free), the task runner leaves it running and takes it again next minute, up to this many times for a task. Past that, or for any other error, the task ends failed. 0 ends it failed at once (the behaviour before 11 Nov 2026).',
        'number', to_jsonb(5), '0', '50', 'times', 787, 'Platform upkeep', 'security.admin_jobs_tick_v1 (job admin-jobs)',
        'Platform Admin 11 Nov 2026 13:45: fix what can be fixed now (a deadlocked task left 1,500 course descriptions unread); 5 tries cover a passing deadlock with room to spare')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.jobs.transient_retry_max',
       jsonb_build_object('before', null, 'after', 5, 'range', '0 to 50', 'reason', 'Added by migration 20261111230000 (Platform Admin 11 Nov 2026 13:45): bounded retry of a task after a passing database error'),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'toolsets' and e.target = 'pipeline.jobs.transient_retry_max');

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.admin_jobs_tick_v1(integer)'::regprocedure);
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = 'd25e4bad56b632eae40d15f69ddfc4f4' then raise notice 'security.admin_jobs_tick_v1(integer): already applied'; return; end if;
  if md5(v_src) <> 'f95f8c26d9bbd4fa07a74bcd0797e198' then raise exception 'live security.admin_jobs_tick_v1(integer) differs from the definition this change replaces (body md5 %)', md5(v_src); end if;
  execute $ddl$
CREATE OR REPLACE FUNCTION security.admin_jobs_tick_v1(p_items integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_lane text; v_j pipeline.admin_jobs%rowtype; v_fin boolean; v_out jsonb := '[]'::jsonb;
        v_n int := greatest(1, least(security.pipeline_num_v1('jobs.per_lane_per_tick', 1)::int, 2000)); v_t0 timestamptz := clock_timestamp();
begin
  for v_lane in select distinct lane from pipeline.admin_jobs where state in ('queued', 'running') loop
    -- 23 Oct 2026: up to jobs.per_lane_per_tick tasks per lane each minute, oldest first
    for v_j in select * from pipeline.admin_jobs j where j.lane = v_lane and j.state in ('queued', 'running')
     order by (j.state = 'running') desc, j.created_at limit v_n for no key update skip locked loop  -- CF-247 IQ-00053: the row is held for the whole run; NO KEY UPDATE does not block the workers' foreign-key checks
    exit when clock_timestamp() - v_t0 > interval '40 seconds';  -- fixed: the runner is called each minute; a run ends before the next starts
    if v_j.cancel_requested then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'cancelled at a provider boundary, work done so far kept');
      perform security.admin_job_close_v1(v_j.id);
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'cancelled'); continue;
    end if;
    if v_j.pause_requested then
      update pipeline.admin_jobs set state = 'paused', pause_requested = false, updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'paused at a provider boundary');
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'paused'); continue;
    end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'running', started_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'started');
    end if;
    begin
      v_fin := security.admin_job_slice_v1(v_j.id, p_items);
    exception when others then
      -- 11 Nov 2026 (CF-247 F-OPS, F-CDESC root cause 2): a passing database error (deadlock 40P01, serialization failure 40001, lock not available 55P03) leaves the task running:
      -- the slice's work was rolled back and the next run (each minute) takes the task again, up to jobs.transient_retry_max times a task. Any other error, or one past the limit, fails the task as before.
      if sqlstate in ('40P01', '40001', '55P03')
         and (select count(*) from pipeline.admin_job_events e where e.job_id = v_j.id and e.note like 'transient database error%') < security.pipeline_num_v1('jobs.transient_retry_max', 5) then
        update pipeline.admin_jobs set updated_at = now() where id = v_j.id;
        insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'transient database error (' || sqlstate || '), tried again next run: ' || left(sqlerrm, 200), jsonb_build_object('sqlstate', sqlstate));
        v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'running', 'retry', sqlstate); continue;
      end if;
      update pipeline.admin_jobs set state = 'failed', error = left(sqlerrm, 500), finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'failed: ' || left(sqlerrm, 300));
      perform security.admin_job_close_v1(v_j.id);
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'failed'); continue;
    end;
    if v_fin then
      -- CF-247 IQ-00064: a task the watcher ended with end_state failed (held past tasks.lane_hold_max_hours) is failed, its note the error
      -- CF-247 IQ-00066: a task the watcher ended not needed (no eligible work) is never done: it is closed cancelled, its error the reason
      update pipeline.admin_jobs set state = case when result->>'end_state' = 'failed' then 'failed' when result->>'end_state' = 'not_needed' then 'cancelled' else 'done' end,
             error = case when result->>'end_state' in ('failed', 'not_needed') then left(result->>'note', 500) else error end,
             finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'finished', (select j.result from pipeline.admin_jobs j where j.id = v_j.id));
      perform security.admin_job_close_v1(v_j.id);
    end if;
    v_out := v_out || jsonb_build_object('id', v_j.id, 'state', case when v_fin then 'done' else 'running' end);
    end loop;
  end loop;
  return v_out;
end $function$
$ddl$;
end $g$;

-- post-check: the body is the one this change states and the setting is registered
do $p$
begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.admin_jobs_tick_v1(integer)'::regprocedure)) <> 'd25e4bad56b632eae40d15f69ddfc4f4' then raise exception 'post-check: security.admin_jobs_tick_v1(integer) is not the body this change states'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'jobs.transient_retry_max' and s.used_by is not null and s.unit is not null) then raise exception 'post-check: setting jobs.transient_retry_max is missing'; end if;
end $p$;
