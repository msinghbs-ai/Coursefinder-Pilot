CREATE OR REPLACE FUNCTION security.flag_jobs_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j record; f pipeline.enrichment_flags; v_n int; v_work int; v_since timestamptz; v_until timestamptz; v jsonb := '[]'::jsonb;
        v_need int := security.pipeline_num_v1('flag.empty_calls_to_pause', 30)::int;
        -- SS-014 D14 (2 Nov 2026): only calls old enough to have answered are counted; the call still under way is never one of the last runs
        v_answered timestamptz := now() - make_interval(secs => security.pipeline_num_v1('flag.answer_wait_seconds', 120));
        v_never text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'flag.never_pause_modes'), '{}');
begin
  for j in select c.jobid, c.jobname, c.active, (regexp_match(c.command, $re$'mode',\s*'([a-z_0-9]+)'$re$))[1] mode
             from cron.job c where c.command like '%svc_pilot_submit_nonce(''coverage-sweep''%' loop
    continue when j.mode is null or j.mode = any (v_never);
    select * into f from pipeline.enrichment_flags x where x.entity = 'job' and x.entity_key = j.jobname and x.field = '' and x.reason_code = 'idle_paused';
    if j.active and (f.id is null or f.state <> 'raised') then
      select count(*), count(*) filter (where coalesce(security.worker_call_work_v1(r.content), 1) > 0), min(l.created_at), max(l.created_at) into v_n, v_work, v_since, v_until
        from (select l2.* from pipeline.edge_request_log l2 where l2.function_name = 'coverage-sweep' and l2.mode = j.mode and l2.created_at > coalesce(f.released_at, '-infinity') and l2.created_at <= v_answered
               order by l2.created_at desc limit v_need) l
        join net._http_response r on r.id = l.request_id where r.status_code = 200;
      if v_n >= v_need and v_work = 0 then
        perform cron.alter_job(j.jobid, active := false);
        perform security.flag_raise_v1('job', j.jobname, null, '', 'idle_paused', format('Paused: its last %s runs found nothing to do (worker mode %s)', v_n, j.mode), 'hard', 'flag-recheck', 'auto',
          jsonb_build_object('mode', j.mode, 'runs', v_n, 'with_work', 0, 'from', v_since, 'to', v_until),
          null, now() + least(make_interval(hours => coalesce(security.flag_list_num_v1('flag.job_recheck_hours', coalesce(f.checks, 0)), 6)),
                                 make_interval(mins => security.pipeline_num_v1('tick.backoff_max_minutes', 15)::int)));  /* R1 Q2 (24 Oct 2026): never longer than the backoff cap */
        v := v || jsonb_build_object('paused', j.jobname);
      end if;
    elsif not j.active and f.state = 'raised' and f.reason_code = 'idle_paused' and (f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode))  -- 19 Oct: on again when work is waiting
          and not security.job_held_off_v1(j.jobname) then  -- CF-247 IQ-00060: never a job a person or a governed restore switched off (jobs.held_off)
      perform security.flag_release_v1(f.id, 'flag-recheck', 'auto', 'Trial run: switched on again to look for new work', jsonb_build_object('mode', j.mode, 'check', f.checks + 1), true);
      v := v || jsonb_build_object('trial', j.jobname);
    end if;
  end loop;
  return v;
end $function$

