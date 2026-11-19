create or replace function public.layer2_automation_actor()
returns uuid
language sql
security definer
set search_path=pg_catalog,public,security
as $$
  select ur.user_id
  from security.user_roles ur
  join security.roles r on r.code=ur.role_code
  where r.status='active'
    and r.rank>=6
    and (ur.expires_at is null or ur.expires_at>now())
  order by ur.granted_at nulls last, ur.user_id
  limit 1
$$;
revoke all on function public.layer2_automation_actor() from public,anon,authenticated;
grant execute on function public.layer2_automation_actor() to service_role;

create or replace function pipeline.svc_pilot_invoke_layer2_v2(p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path=pipeline,vault,net,public
as $$
declare v_key text; v_id bigint;
begin
  if current_user <> 'service_role' then
    raise exception 'service_role required' using errcode='42501';
  end if;
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

create or replace function pipeline.trg_submit_pilot_edge_execution()
returns trigger
language plpgsql
security definer
set search_path=pipeline,public
as $$
begin
  if new.function_name='layer2-acquire-v2' then
    begin
      new.net_request_id:=pipeline.svc_pilot_invoke_layer2_v2(new.body);
      new.status:='submitted';
      new.submitted_at:=now();
    exception when others then
      new.status:='failed';
      new.error_text:=sqlerrm;
    end;
    return new;
  end if;
  if new.function_name not in ('layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue') then
    new.status:='failed';
    new.error_text:='function not allowlisted';
    return new;
  end if;
  begin
    new.net_request_id:=pipeline.svc_pilot_invoke_edge(new.function_name,new.body);
    new.status:='submitted';
    new.submitted_at:=now();
  exception when others then
    new.status:='failed';
    new.error_text:=sqlerrm;
  end;
  return new;
end $$;
