create or replace function pipeline.svc_pilot_invoke_scholarship_edge(
  p_body jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nonce uuid := gen_random_uuid();
  v_request_id bigint;
begin
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at)
  values(v_nonce,'scholarships-au-etl',now()+interval '5 minutes');

  select net.http_post(
    url := 'https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/scholarships-au-etl',
    headers := jsonb_build_object(
      'content-type','application/json',
      'x-cf-run-nonce',v_nonce::text
    ),
    body := coalesce(p_body,'{}'::jsonb),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return jsonb_build_object('request_id',v_request_id,'nonce',v_nonce);
end
$$;

revoke all on function pipeline.svc_pilot_invoke_scholarship_edge(jsonb) from public, anon, authenticated;
grant execute on function pipeline.svc_pilot_invoke_scholarship_edge(jsonb) to service_role;

comment on function pipeline.svc_pilot_invoke_scholarship_edge(jsonb) is
'Pilot-only nonce runner for M1-L2-SCHOLARSHIPS autonomous UAT. The Edge worker consumes a single-use nonce; no persistent bearer secret is passed.';
