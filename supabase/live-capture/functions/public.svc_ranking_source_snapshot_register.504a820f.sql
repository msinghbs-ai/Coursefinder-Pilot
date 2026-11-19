CREATE OR REPLACE FUNCTION public.svc_ranking_source_snapshot_register(p_source_id uuid, p_system_code text, p_edition_year integer, p_source_url text, p_storage_path text, p_content_hash text, p_byte_size bigint, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'ranking'
AS $function$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  select id into v_id
  from pipeline.evidence_artifacts
  where source_id=p_source_id
    and evidence_type='ranking_publisher_json'
    and content_hash=p_content_hash
  order by captured_at desc
  limit 1;
  if v_id is not null then return v_id; end if;

  insert into pipeline.evidence_artifacts(
    source_id,evidence_type,source_url,storage_path,content_hash,mime_type,
    metadata,retention_class,review_state,evidence_group_key
  )
  values(
    p_source_id,'ranking_publisher_json',p_source_url,p_storage_path,p_content_hash,'application/json',
    jsonb_build_object(
      'layer','1','ranking_system_code',p_system_code,'edition_year',p_edition_year,
      'byte_size',p_byte_size,'capture_mode','publisher_xhr_json'
    ) || coalesce(p_metadata,'{}'::jsonb),
    'source_evidence','pending_review',
    'ranking:'||p_system_code||':'||p_edition_year::text
  )
  returning id into v_id;
  return v_id;
end
$function$
