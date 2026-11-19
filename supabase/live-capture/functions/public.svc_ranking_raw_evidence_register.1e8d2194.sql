CREATE OR REPLACE FUNCTION public.svc_ranking_raw_evidence_register(p_system_code text, p_edition_year integer, p_source_url text, p_storage_path text, p_content_hash text, p_mime_type text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking', 'pipeline'
AS $function$
declare
  v_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if not exists (select 1 from ranking.systems where code=p_system_code and active) then
    raise exception 'unsupported ranking system' using errcode='22023';
  end if;
  if p_edition_year<2000 or p_edition_year>2100 then
    raise exception 'invalid edition year' using errcode='22023';
  end if;
  if coalesce(btrim(p_storage_path),'')='' or coalesce(btrim(p_content_hash),'')='' then
    raise exception 'storage path and content hash required' using errcode='22023';
  end if;

  select id into v_id from pipeline.evidence_artifacts where storage_path=p_storage_path limit 1;
  if v_id is not null then return v_id; end if;

  insert into pipeline.evidence_artifacts(
    evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,metadata,
    retention_class,review_state,capture_version,evidence_group_key
  ) values (
    'ranking_publisher_raw',p_source_url,p_storage_path,p_content_hash,p_mime_type,now(),
    jsonb_strip_nulls(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('ranking_system',p_system_code,'edition_year',p_edition_year)),
    'source_evidence','pending_review',1,
    'ranking:'||p_system_code||':'||p_edition_year::text||':raw:'||left(p_content_hash,16)
  ) returning id into v_id;
  return v_id;
end
$function$
