begin;

create or replace function pipeline.svc_pilot_invoke_layer2(
 p_function text,
 p_body jsonb default '{}'::jsonb
) returns bigint
language plpgsql
security definer
set search_path='pipeline','vault','net','public'
as $$
declare v_key text;v_id bigint;v_base text;
begin
 if p_function not in(
   'layer2-acquire-v2',
   'layer2-extract-v2',
   'layer2-course-fact-extract-v2',
   'layer2-scholarship-extract',
   'layer2-scholarship-catalogue-enumerate',
   'layer2-provider-page-fanout',
   'layer2-provider-asset-promote',
   'layer2-hotcourses-directory-parse'
 ) then raise exception 'Layer2 automation function not allowlisted';end if;
 v_key:=public.coursefinder_runtime_automation_key();v_base:=public.coursefinder_runtime_edge_base_url();
 if v_key is null then raise exception 'runtime automation secret missing';end if;
 if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(
   url:=rtrim(v_base,'/')||'/'||p_function,
   headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),
   body:=coalesce(p_body,'{}'::jsonb),
   timeout_milliseconds:=120000
 ) into v_id;
 return v_id;
end $$;

revoke all on function pipeline.svc_pilot_invoke_layer2(text,jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_invoke_layer2(text,jsonb) to service_role;

commit;
