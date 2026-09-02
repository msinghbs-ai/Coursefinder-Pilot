begin;

create or replace function public.layer2_scholarship_extraction_context(p_evidence_id uuid)
returns jsonb language sql security definer
set search_path='pg_catalog','public','pipeline' as $$
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
   'metadata',e.metadata
 )
 from pipeline.evidence_artifacts e
 where e.id=p_evidence_id
$$;

revoke all on function public.layer2_scholarship_extraction_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scholarship_extraction_context(uuid) to service_role;

commit;