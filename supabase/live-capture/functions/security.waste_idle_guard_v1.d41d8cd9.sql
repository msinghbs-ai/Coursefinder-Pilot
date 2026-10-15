CREATE OR REPLACE FUNCTION security.waste_idle_guard_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w record; v_jobid bigint; v_active boolean; v_out bigint; v_inp bigint; v jsonb := '[]'::jsonb;
        v_hours int := security.pipeline_num_v1('waste.idle_pause_hours', 24)::int;
begin
  for w in select * from pipeline.job_idle_watch order by jobname loop
    select j.jobid, j.active into v_jobid, v_active from cron.job j where j.jobname = w.jobname;
    continue when v_jobid is null;
    execute w.output_sql into v_out using now() - make_interval(hours => v_hours);
    execute w.input_sql into v_inp;
    update pipeline.job_idle_watch set last_checked_at = now(), last_output = v_out, last_input = v_inp where jobname = w.jobname;
    if v_active and coalesce(v_out, 0) = 0 and coalesce(v_inp, 0) = 0 and coalesce(w.resumed_at, '-infinity') < now() - make_interval(hours => v_hours) then
      perform cron.alter_job(v_jobid, active := false);
      update pipeline.job_idle_watch set paused_at = now() where jobname = w.jobname;
      insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, source)
      values ('job', w.jobname, '', 'idle_paused', format('Paused: no output for %s hours and nothing waiting. %s', v_hours, coalesce(w.note, '')), 'waste-guard')
      on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
      v := v || jsonb_build_object('paused', w.jobname);
    elsif not v_active and w.paused_at is not null and coalesce(v_inp, 0) > 0 then
      -- only a job this guard paused is switched on again
      perform cron.alter_job(v_jobid, active := true);
      update pipeline.job_idle_watch set paused_at = null, resumed_at = now() where jobname = w.jobname;
      update pipeline.enrichment_flags set cleared_at = now() where entity = 'job' and entity_key = w.jobname and reason_code = 'idle_paused' and cleared_at is null;
      v := v || jsonb_build_object('resumed', w.jobname);
    end if;
  end loop;
  return v;
end $function$
