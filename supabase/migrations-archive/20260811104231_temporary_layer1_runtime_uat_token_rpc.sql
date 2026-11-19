create or replace function public.svc_layer1_runtime_uat_token()
returns text
language sql
security definer
set search_path = public,pipeline
as $$
  select token from pipeline.layer1_runtime_uat_control where id=true and active=true;
$$;
revoke all on function public.svc_layer1_runtime_uat_token() from public, anon, authenticated;
grant execute on function public.svc_layer1_runtime_uat_token() to service_role;
