-- CF-CHG-20260915-247
-- One-time service nonce runner for bounded Layer 3 dispatcher execution.
-- Keeps service-role credentials inside server/runtime boundaries.
begin;

create or replace function public.svc_cf247_dispatch_layer3(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','net','public','extensions'
as $$
declare
  v_nonce uuid:=extensions.gen_random_uuid();
  v_request_id bigint;
  v_base text;
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),25);
begin
  if current_user not in ('postgres','service_role')
     and coalesce(auth.role(),'')<>'service_role' then
    raise exception 'service_role required' using errcode='42501';
  end if;

  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at)
  values(v_nonce,'layer3-work-dispatch',now()+interval '5 minutes');

  v_base:=public.coursefinder_runtime_edge_base_url();
  if v_base is null then raise exception 'runtime Edge base URL missing'; end if;

  select net.http_post(
    url:=rtrim(v_base,'/')||'/layer3-work-dispatch',
    headers:=jsonb_build_object(
      'content-type','application/json',
      'x-cf-run-nonce',v_nonce::text
    ),
    body:=jsonb_build_object(
      'limit',v_limit,
      'worker','cf247-manual-bounded'
    ),
    timeout_milliseconds:=120000
  ) into v_request_id;

  return jsonb_build_object(
    'request_id',v_request_id,
    'nonce',v_nonce,
    'limit',v_limit
  );
end $$;

revoke all on function public.svc_cf247_dispatch_layer3(integer)
from public,anon,authenticated;
grant execute on function public.svc_cf247_dispatch_layer3(integer)
to service_role;

commit;
