-- CF-247 Decision 252: end the leases of a trial run's unfinished cases so the next worker call picks them up (service role only).
create or replace function public.svc_toolset_trial_release(p_run_id uuid) returns int
language plpgsql security definer set search_path = '' as $f$
declare v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.toolset_trial_items set leased_until = now() where run_id = p_run_id and status = 'leased';
  get diagnostics v_n = row_count;
  return v_n;
end $f$;
revoke all on function public.svc_toolset_trial_release(uuid) from public, anon, authenticated;
grant execute on function public.svc_toolset_trial_release(uuid) to service_role;
