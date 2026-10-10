create or replace function public.svc_ranking_manual_import_register(p_system_code text, p_edition_year integer, p_publisher_name text, p_source_url text, p_methodology_url text, p_licensing_note text, p_revision_note text, p_original_filename text, p_mime_type text, p_byte_size bigint, p_content_hash text, p_storage_path text, p_uploaded_by uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog','ranking','pipeline','auth'
as $$
declare
  v_system ranking.systems%rowtype;
  v_evidence_id uuid;
  v_import_id uuid;
  v_existing uuid;
  v_group_key text;
  v_capture_version integer;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  select * into v_system from ranking.systems where code=p_system_code and active;
  if v_system.id is null then raise exception 'unsupported ranking system' using errcode='22023'; end if;
  if p_edition_year<2000 or p_edition_year>2100 then raise exception 'invalid edition year' using errcode='22023'; end if;
  if coalesce(btrim(p_source_url),'')='' then raise exception 'source url required' using errcode='22023'; end if;
  if coalesce(btrim(p_licensing_note),'')='' then raise exception 'licensing note required' using errcode='22023'; end if;
  if coalesce(btrim(p_content_hash),'')='' then raise exception 'content hash required' using errcode='22023'; end if;

  select id into v_existing from ranking.manual_imports
  where system_id=v_system.id and edition_year=p_edition_year and content_hash=p_content_hash limit 1;
  if v_existing is not null then
    return jsonb_build_object('duplicate',true,'import_id',v_existing,
      'evidence_id',(select evidence_artifact_id from ranking.manual_imports where id=v_existing));
  end if;

  v_group_key:='ranking:'||p_system_code||':'||p_edition_year::text;
  select coalesce(max(capture_version),0)+1 into v_capture_version
  from pipeline.evidence_artifacts where evidence_group_key=v_group_key;

  insert into pipeline.evidence_artifacts(
    evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,metadata,
    retention_class,review_state,capture_version,evidence_group_key
  ) values (
    'ranking_publisher_file',p_source_url,p_storage_path,p_content_hash,p_mime_type,now(),
    jsonb_strip_nulls(jsonb_build_object(
      'ranking_system',p_system_code,'edition_year',p_edition_year,'publisher_name',p_publisher_name,
      'methodology_url',p_methodology_url,'licensing_note',p_licensing_note,'revision_note',p_revision_note,
      'original_filename',p_original_filename,'byte_size',p_byte_size,'uploaded_by',p_uploaded_by,'manual_upload',true
    )),
    'source_evidence','pending_review',v_capture_version,v_group_key
  ) returning id into v_evidence_id;

  insert into ranking.manual_imports(
    system_id,edition_year,publisher_name,source_url,methodology_url,licensing_note,revision_note,
    original_filename,mime_type,byte_size,content_hash,storage_path,evidence_artifact_id,status,uploaded_by
  ) values (
    v_system.id,p_edition_year,p_publisher_name,p_source_url,nullif(p_methodology_url,''),p_licensing_note,nullif(p_revision_note,''),
    p_original_filename,p_mime_type,p_byte_size,p_content_hash,p_storage_path,v_evidence_id,'uploaded',p_uploaded_by
  ) returning id into v_import_id;

  return jsonb_build_object('duplicate',false,'import_id',v_import_id,'evidence_id',v_evidence_id,'status','uploaded','capture_version',v_capture_version);
end
$$;
revoke all on function public.svc_ranking_manual_import_register(text,integer,text,text,text,text,text,text,text,bigint,text,text,uuid) from public,anon,authenticated;
grant execute on function public.svc_ranking_manual_import_register(text,integer,text,text,text,text,text,text,text,bigint,text,text,uuid) to service_role;
