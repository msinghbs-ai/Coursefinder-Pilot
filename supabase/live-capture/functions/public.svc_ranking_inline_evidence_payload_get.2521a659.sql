CREATE OR REPLACE FUNCTION public.svc_ranking_inline_evidence_payload_get(p_evidence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'ranking'
AS $function$
declare
  v_payload pipeline.ranking_inline_evidence_payloads%rowtype;
  v_import ranking.manual_imports%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  select * into v_payload from pipeline.ranking_inline_evidence_payloads where evidence_id=p_evidence_id;
  if v_payload.evidence_id is null then raise exception 'inline ranking evidence not found' using errcode='P0002'; end if;
  select * into v_import from ranking.manual_imports where evidence_artifact_id=p_evidence_id limit 1;
  if v_import.id is null then raise exception 'ranking import not found for evidence' using errcode='P0002'; end if;
  return jsonb_build_object(
    'evidence_id',v_payload.evidence_id,
    'import_id',v_import.id,
    'edition_year',v_import.edition_year,
    'original_filename',v_payload.original_filename,
    'mime_type',v_payload.mime_type,
    'byte_size',v_payload.byte_size,
    'content_hash',v_payload.content_hash,
    'payload_base64',encode(v_payload.payload,'base64')
  );
end
$function$
