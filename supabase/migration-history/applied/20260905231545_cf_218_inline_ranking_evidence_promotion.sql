create or replace function public.svc_ranking_inline_evidence_payload_get(p_evidence_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pipeline, ranking
as $$
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
$$;

create or replace function public.svc_ranking_inline_evidence_promote(
  p_evidence_id uuid,
  p_storage_path text,
  p_delete_inline boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pipeline, ranking
as $$
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if coalesce(btrim(p_storage_path),'')='' or p_storage_path like 'inline://%' then
    raise exception 'valid storage path required' using errcode='22023';
  end if;
  if not exists(select 1 from pipeline.ranking_inline_evidence_payloads where evidence_id=p_evidence_id) then
    raise exception 'inline ranking evidence not found' using errcode='P0002';
  end if;
  update pipeline.evidence_artifacts
     set storage_path=p_storage_path,
         metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('inline_payload_promoted_at',now(),'inline_payload_promoted',true)
   where id=p_evidence_id;
  update ranking.manual_imports
     set storage_path=p_storage_path, updated_at=now()
   where evidence_artifact_id=p_evidence_id;
  if p_delete_inline then
    delete from pipeline.ranking_inline_evidence_payloads where evidence_id=p_evidence_id;
  end if;
end
$$;

revoke all on function public.svc_ranking_inline_evidence_payload_get(uuid) from public, anon, authenticated;
revoke all on function public.svc_ranking_inline_evidence_promote(uuid,text,boolean) from public, anon, authenticated;
grant execute on function public.svc_ranking_inline_evidence_payload_get(uuid) to service_role;
grant execute on function public.svc_ranking_inline_evidence_promote(uuid,text,boolean) to service_role;
