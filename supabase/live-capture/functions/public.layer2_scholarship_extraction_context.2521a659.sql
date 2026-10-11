CREATE OR REPLACE FUNCTION public.layer2_scholarship_extraction_context(p_evidence_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue'
AS $function$
 select jsonb_build_object(
   'id',e.id,
   'source_id',e.source_id,
   'job_id',e.job_id,
   'evidence_type',e.evidence_type,
   'source_url',e.source_url,
   'storage_path',e.storage_path,
   'content_hash',e.content_hash,
   'mime_type',e.mime_type,
   'source_profile_version_id',e.source_profile_version_id,
   'metadata',e.metadata,
   'provider_id',s.provider_id,
   'provider_name',p.canonical_name,
   'source_type',s.source_type,
   'source_label',s.label,
   'source_metadata',s.metadata
 )
 from pipeline.evidence_artifacts e
 join pipeline.sources s on s.id=e.source_id
 left join catalogue.providers p on p.id=s.provider_id
 where e.id=p_evidence_id
$function$
