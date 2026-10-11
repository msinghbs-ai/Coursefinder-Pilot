CREATE OR REPLACE FUNCTION public.svc_scholarship_source_record(p_source_id uuid, p_source_record_id text, p_source_record_url text, p_source_provider_id text, p_source_provider_cricos text, p_source_provider_name text, p_content_hash text, p_evidence_id uuid, p_payload jsonb, p_status text DEFAULT 'captured'::text, p_error_text text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.scholarship_source_records(
    source_id,source_record_id,source_record_url,source_provider_id,source_provider_cricos,source_provider_name,
    content_hash,evidence_id,payload,status,error_text,observed_at,applied_at
  ) values (
    p_source_id,p_source_record_id,p_source_record_url,p_source_provider_id,p_source_provider_cricos,p_source_provider_name,
    p_content_hash,p_evidence_id,p_payload,p_status,p_error_text,now(),case when p_status='applied' then now() end
  )
  on conflict(source_id,source_record_id,content_hash) do update set
    evidence_id=excluded.evidence_id,payload=excluded.payload,source_record_url=excluded.source_record_url,
    source_provider_id=excluded.source_provider_id,source_provider_cricos=excluded.source_provider_cricos,
    source_provider_name=excluded.source_provider_name,status=excluded.status,error_text=excluded.error_text,
    observed_at=now(),applied_at=case when excluded.status='applied' then now() else pipeline.scholarship_source_records.applied_at end
  returning id into v_id;
  return v_id;
end
$function$
