create or replace function pipeline.svc_pilot_invoke_edge(p_function text, p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','vault','net','public' as $$
declare v_key text; v_id bigint; begin
 if p_function not in ('layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue','layer1-ca-conestoga-catalogue','layer1-ca-fanshawe-pgwp','layer1-ca-mohawk-catalogue') then raise exception 'Pilot Edge function is not allowlisted'; end if;
 select decrypted_secret into v_key from vault.decrypted_secrets where name='coursefinder_pilot_automation_key' limit 1;
 if v_key is null then raise exception 'Pilot automation secret missing'; end if;
 select net.http_post(url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=30000) into v_id;
 return v_id; end $$;
revoke all on function pipeline.svc_pilot_invoke_edge(text,jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_invoke_edge(text,jsonb) to service_role;

create or replace function pipeline.trg_submit_pilot_edge_execution()
returns trigger language plpgsql security definer set search_path='pipeline','public' as $$
begin
 if new.function_name not in ('layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue','layer1-ca-conestoga-catalogue','layer1-ca-fanshawe-pgwp','layer1-ca-mohawk-catalogue') then new.status:='failed'; new.error_text:='function not allowlisted'; return new; end if;
 begin new.net_request_id:=pipeline.svc_pilot_invoke_edge(new.function_name,new.body); new.status:='submitted'; new.submitted_at:=now(); exception when others then new.status:='failed'; new.error_text:=sqlerrm; end;
 return new; end $$;
