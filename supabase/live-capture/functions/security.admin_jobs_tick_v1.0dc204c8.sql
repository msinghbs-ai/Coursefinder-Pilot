CREATE OR REPLACE FUNCTION security.admin_jobs_tick_v1(p_items integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_lane text; v_j pipeline.admin_jobs%rowtype; v_fin boolean; v_out jsonb := '[]'::jsonb;
begin
  for v_lane in select distinct lane from pipeline.admin_jobs where state in ('queued', 'running') loop
    select * into v_j from pipeline.admin_jobs j where j.lane = v_lane and j.state in ('queued', 'running')
     order by (j.state = 'running') desc, j.created_at limit 1 for update skip locked;
    if v_j.id is null then continue; end if;
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
      update pipeline.admin_jobs set state = 'failed', error = left(sqlerrm, 500), finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note) values (v_j.id, 'failed: ' || left(sqlerrm, 300));
      perform security.admin_job_close_v1(v_j.id);
      v_out := v_out || jsonb_build_object('id', v_j.id, 'state', 'failed'); continue;
    end;
    if v_fin then
      update pipeline.admin_jobs set state = 'done', finished_at = now(), updated_at = now() where id = v_j.id;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'finished', (select j.result from pipeline.admin_jobs j where j.id = v_j.id));
      perform security.admin_job_close_v1(v_j.id);
    end if;
    v_out := v_out || jsonb_build_object('id', v_j.id, 'state', case when v_fin then 'done' else 'running' end);
  end loop;
  return v_out;
end $function$
