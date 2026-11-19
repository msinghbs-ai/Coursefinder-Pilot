create or replace function public.svc_pilot_source_fetch_result(p_request_id bigint)
returns jsonb
language plpgsql
security invoker
set search_path = public, net
as $$
declare r net._http_response%rowtype;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from net._http_response where id=p_request_id;
  if not found then return null; end if;
  return jsonb_build_object('status_code',r.status_code,'timed_out',r.timed_out,'error_msg',r.error_msg,'content',r.content);
end;
$$;
