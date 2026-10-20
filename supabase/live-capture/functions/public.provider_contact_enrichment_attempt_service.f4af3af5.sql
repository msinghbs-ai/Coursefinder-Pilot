CREATE OR REPLACE FUNCTION public.provider_contact_enrichment_attempt_service(p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  insert into pipeline.provider_contact_enrichment_attempts(
    provider_id,source_provider,request_type,domain,requested_titles,status,external_call_count,
    vendor_units,estimated_cost_usd,latency_ms,error,metadata
  ) values(
    (p_payload->>'provider_id')::uuid,p_payload->>'source_provider',p_payload->>'request_type',
    nullif(p_payload->>'domain',''),
    coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'requested_titles','[]'::jsonb))),'{}'::text[]),
    p_payload->>'status',coalesce((p_payload->>'external_call_count')::integer,0),
    nullif(p_payload->>'vendor_units','')::numeric,nullif(p_payload->>'estimated_cost_usd','')::numeric,
    nullif(p_payload->>'latency_ms','')::integer,nullif(p_payload->>'error',''),coalesce(p_payload->'metadata','{}'::jsonb)
  ) returning id into v_id;
  return v_id;
end $function$
