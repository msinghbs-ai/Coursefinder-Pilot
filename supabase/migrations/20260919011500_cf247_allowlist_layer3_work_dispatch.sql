-- CF-CHG-20260915-247
-- Forward-only Pilot execution correction: permit the already service-owned,
-- quota-preflighted Layer 3 dispatcher to be invoked through the existing
-- one-time nonce runner. This does not broaden dispatcher authority.

create or replace function pipeline.svc_pilot_submit_nonce(
  p_function text,
  p_body jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path to 'pipeline', 'net', 'public', 'extensions'
as $function$
declare
  v_nonce uuid := extensions.gen_random_uuid();
  v_id bigint;
  v_base text;
begin
  if p_function not in (
    'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness',
    'coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled',
    'layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled','layer3-source-pattern-benchmark',
    'layer3-contact-benchmark','layer2-screenshot-backfill-scheduled','provider-contact-discover-scheduled','provider-contact-enrich-apollo',
    'layer3-cf245-tuition-benchmark','layer3-work-dispatch'
  ) then
    raise exception 'one-time Edge function is not allowlisted';
  end if;

  insert into pipeline.pilot_edge_nonces(id,function_name,expires_at)
  values(v_nonce,p_function,now()+interval '2 minutes');

  v_base := public.coursefinder_runtime_edge_base_url();
  if v_base is null then raise exception 'runtime Edge base URL missing'; end if;

  select net.http_post(
    url := rtrim(v_base,'/')||'/'||p_function,
    headers := jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),
    body := coalesce(p_body,'{}'::jsonb),
    timeout_milliseconds := 120000
  ) into v_id;
  return v_id;
end
$function$;
