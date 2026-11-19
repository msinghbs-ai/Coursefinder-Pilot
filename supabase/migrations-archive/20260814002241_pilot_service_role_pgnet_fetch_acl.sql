revoke all on function public.svc_pilot_source_fetch_start(text) from public, anon, authenticated;
revoke all on function public.svc_pilot_source_fetch_result(bigint) from public, anon, authenticated;
grant execute on function public.svc_pilot_source_fetch_start(text) to service_role;
grant execute on function public.svc_pilot_source_fetch_result(bigint) to service_role;
