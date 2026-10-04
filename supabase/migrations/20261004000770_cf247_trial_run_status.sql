-- CF-247 Decision 252: set a trial run's status after a worker call (service role only): finished when no case is left,
-- otherwise paused at the time limit when the call ran out of time.
create or replace function public.svc_toolset_trial_close(p_run_id uuid, p_timed_out boolean) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_left int; v_new text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  perform public.svc_toolset_trial_release(p_run_id);
  v_left := public.svc_toolset_trial_left(p_run_id);
  v_new := case when v_left = 0 then 'done' when p_timed_out then 'paused_time_limit' else null end;
  if v_new = 'done' then
    update pipeline.toolset_trial_runs set status = 'done', finished_at = now(), updated_at = now() where id = p_run_id and status = 'running';
  elsif v_new = 'paused_time_limit' then
    update pipeline.toolset_trial_runs set status = 'paused_time_limit', status_note = format('%s cases left: the worker reached its time per call; press Continue', v_left), updated_at = now() where id = p_run_id and status = 'running';
  end if;
  return jsonb_build_object('left', v_left, 'status', (select status from pipeline.toolset_trial_runs where id = p_run_id));
end $f$;
revoke all on function public.svc_toolset_trial_close(uuid, boolean) from public, anon, authenticated;
grant execute on function public.svc_toolset_trial_close(uuid, boolean) to service_role;
