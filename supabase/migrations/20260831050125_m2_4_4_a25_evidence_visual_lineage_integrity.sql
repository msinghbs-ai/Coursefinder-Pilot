
create or replace function security.admin_evidence_related_visual(p_evidence_id uuid)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','pipeline','storage'
as $$
  select case when se.id is null then null else jsonb_build_object(
    'id',se.id,
    'evidence_type',se.evidence_type,
    'mime_type',se.mime_type,
    'captured_at',se.captured_at,
    'content_hash',se.content_hash,
    'storage_available',so.id is not null,
    'preview_allowed',(so.id is not null and lower(coalesce(se.mime_type,'')) in ('image/png','image/jpeg','image/webp')),
    'source_url',se.source_url,
    'attempt_id',pa.id
  ) end
  from pipeline.evidence_artifacts cur
  join pipeline.layer2_provider_attempts pa
    on pa.screenshot_evidence_id is not null
   and lower(coalesce(cur.mime_type,'')) in ('text/html','application/xhtml+xml')
   and (
     pa.raw_evidence_id=cur.id
     or pa.html_evidence_id=cur.id
   )
  join pipeline.evidence_artifacts se on se.id=pa.screenshot_evidence_id
  left join storage.objects so on so.bucket_id='evidence' and so.name=se.storage_path
  where cur.id=p_evidence_id
  order by pa.completed_at desc nulls last
  limit 1
$$;

revoke all on function security.admin_evidence_related_visual(uuid) from public,anon,authenticated;
