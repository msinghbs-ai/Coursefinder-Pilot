-- CF-247 Decision 252: count what is left in a trial run (service role only).
create or replace function public.svc_toolset_trial_left(p_run_id uuid) returns int
language sql stable security definer set search_path = '' as $f$
  select count(*)::int from pipeline.toolset_trial_items where run_id = p_run_id and status <> 'done'
$f$;
revoke all on function public.svc_toolset_trial_left(uuid) from public, anon, authenticated;
grant execute on function public.svc_toolset_trial_left(uuid) to service_role;
