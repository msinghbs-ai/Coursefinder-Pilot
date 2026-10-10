-- M2.3 Evidence replay/idempotency hardening
-- Change Control: CF-CHG-20260825-036

create or replace function public.layer2_evidence_capture(
  p_source_id uuid,
  p_job_id uuid,
  p_evidence_type text,
  p_source_url text,
  p_storage_path text,
  p_content_hash text,
  p_mime_type text,
  p_profile_version_id uuid,
  p_group_key text,
  p_retention_class text,
  p_retain_until timestamptz,
  p_metadata jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare
  prev pipeline.evidence_artifacts%rowtype;
  v_id uuid;
  v_cap integer;
  v_now timestamptz:=now();
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into prev
  from pipeline.evidence_artifacts
  where evidence_group_key=p_group_key
  order by capture_version desc
  limit 1
  for update;

  if prev.id is not null and prev.content_hash is not distinct from p_content_hash then
    return jsonb_build_object(
      'evidence_id',prev.id,
      'capture_version',prev.capture_version,
      'content_changed',false,
      'supersedes_evidence_id',prev.supersedes_evidence_id,
      'storage_path',prev.storage_path,
      'duplicate_upload_path',p_storage_path
    );
  end if;

  v_cap:=coalesce(prev.capture_version,0)+1;
  if prev.id is not null then
    update pipeline.evidence_artifacts set valid_to=v_now where id=prev.id;
  end if;

  insert into pipeline.evidence_artifacts(
    source_id,job_id,evidence_type,source_url,storage_path,content_hash,mime_type,
    captured_at,valid_from,supersedes_evidence_id,source_profile_version_id,
    retention_class,retain_until,review_state,capture_version,evidence_group_key,metadata
  ) values(
    p_source_id,p_job_id,p_evidence_type,p_source_url,p_storage_path,p_content_hash,p_mime_type,
    v_now,v_now,prev.id,p_profile_version_id,coalesce(p_retention_class,'standard_365'),
    p_retain_until,'unreviewed',v_cap,p_group_key,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('content_changed',true)
  ) returning id into v_id;

  return jsonb_build_object(
    'evidence_id',v_id,
    'capture_version',v_cap,
    'content_changed',true,
    'supersedes_evidence_id',prev.id,
    'storage_path',p_storage_path,
    'duplicate_upload_path',null
  );
end
$$;

revoke all on function public.layer2_evidence_capture(uuid,uuid,text,text,text,text,text,uuid,text,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_evidence_capture(uuid,uuid,text,text,text,text,text,uuid,text,text,timestamptz,jsonb) to service_role;