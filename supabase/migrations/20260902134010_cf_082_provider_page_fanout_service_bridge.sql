begin;
create or replace function pipeline.svc_pilot_invoke_layer2(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer
set search_path='pipeline','vault','net','public' as $$
declare v_key text;v_id bigint;
begin
 if p_function not in ('layer2-acquire-v2','layer2-extract-v2','layer2-course-fact-extract-v2','layer2-scholarship-extract-v2','layer2-provider-page-fanout')
 then raise exception 'Layer2 automation function not allowlisted';end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where name='coursefinder_pilot_automation_key' limit 1;
 if v_key is null then raise exception 'Pilot automation secret missing';end if;
 select net.http_post(url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
 headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),
 body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;
 return v_id;
end $$;
revoke all on function pipeline.svc_pilot_invoke_layer2(text,jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_invoke_layer2(text,jsonb) to service_role;
commit;