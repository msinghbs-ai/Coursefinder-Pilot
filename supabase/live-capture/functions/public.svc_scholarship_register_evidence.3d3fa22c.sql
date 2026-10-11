CREATE OR REPLACE FUNCTION public.svc_scholarship_register_evidence(p_source_id uuid, p_source_url text, p_storage_path text, p_content_hash text, p_mime_type text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role required'; end if;
  select id into v_id
  from pipeline.evidence_artifacts
  where source_id=p_source_id
    and content_hash=p_content_hash
    and coalesce(source_url,'')=coalesce(p_source_url,'')
  order by captured_at desc limit 1;

  if v_id is null then
    insert into pipeline.evidence_artifacts(
      source_id,evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,metadata
    ) values (
      p_source_id,'source_snapshot',p_source_url,p_storage_path,p_content_hash,p_mime_type,now(),
      coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object('layer','2A','domain','scholarship')
    ) returning id into v_id;
  end if;
  return v_id;
end
$function$
