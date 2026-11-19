create or replace function pipeline.svc_pilot_invoke_layer2_v2(p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path=pipeline,vault,net,public
as $$
declare v_key text; v_id bigint;
begin
  select decrypted_secret into v_key from vault.decrypted_secrets where name='coursefinder_pilot_automation_key' limit 1;
  if v_key is null then raise exception 'Pilot automation secret missing'; end if;
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/layer2-acquire-v2',
    headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),
    body:=coalesce(p_body,'{}'::jsonb),
    timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end $$;
revoke all on function pipeline.svc_pilot_invoke_layer2_v2(jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_invoke_layer2_v2(jsonb) to service_role;
