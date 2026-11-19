begin;

create or replace function public.svc_ranking_import_storage_restore(
  p_import_id uuid,
  p_storage_path text,
  p_content_hash text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','ranking','pipeline'
as $$
declare
  v_import ranking.manual_imports%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if coalesce(btrim(p_storage_path),'')='' or p_storage_path like 'inline://%' then
    raise exception 'valid storage path required' using errcode='22023';
  end if;
  select * into v_import from ranking.manual_imports where id=p_import_id;
  if v_import.id is null then raise exception 'ranking import not found' using errcode='P0002'; end if;
  if lower(coalesce(v_import.content_hash,''))<>lower(coalesce(p_content_hash,'')) then
    raise exception 'content hash mismatch' using errcode='22023';
  end if;

  update pipeline.evidence_artifacts
     set storage_path=p_storage_path,
         metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
           'publisher_file_restored_at',now(),
           'publisher_file_restored',true,
           'publisher_file_restore_hash',p_content_hash
         )
   where id=v_import.evidence_artifact_id;

  update ranking.manual_imports
     set storage_path=p_storage_path,
         updated_at=now()
   where id=p_import_id;

  return jsonb_build_object('ok',true,'import_id',p_import_id,'evidence_id',v_import.evidence_artifact_id,'storage_path',p_storage_path);
end
$$;

revoke all on function public.svc_ranking_import_storage_restore(uuid,text,text) from public, anon, authenticated;
grant execute on function public.svc_ranking_import_storage_restore(uuid,text,text) to service_role;

commit;
