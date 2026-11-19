-- A15: allow one-time scheduled execution of governed provider-contact workers.
create or replace function pipeline.svc_pilot_submit_nonce(p_function text, p_body jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'pipeline','net','public','extensions'
as $$
declare v_nonce uuid:=extensions.gen_random_uuid(); v_id bigint;
begin
  if p_function not in (
    'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness',
    'coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled',
    'layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled','layer3-source-pattern-benchmark','layer2-screenshot-backfill-scheduled',
    'provider-contact-discover-scheduled','provider-contact-enrich-apollo'
  ) then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at)
  values(v_nonce,p_function,now()+interval '2 minutes');
  select net.http_post(
    url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,
    headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body:=coalesce(p_body,'{}'::jsonb),
    timeout_milliseconds:=120000
  ) into v_id;
  return v_id;
end $$;

revoke all on function pipeline.svc_pilot_submit_nonce(text,jsonb) from public,anon,authenticated;
grant execute on function pipeline.svc_pilot_submit_nonce(text,jsonb) to service_role,postgres;
