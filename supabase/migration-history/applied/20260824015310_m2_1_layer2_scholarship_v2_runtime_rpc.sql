create or replace function public.layer2_normalized_evidence_context(p_evidence_id uuid)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare e pipeline.evidence_artifacts%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into e from pipeline.evidence_artifacts where id=p_evidence_id;
 if not found or e.evidence_type<>'layer2_extraction_input' then return null; end if;
 return jsonb_build_object('id',e.id,'source_id',e.source_id,'job_id',e.job_id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'mime_type',e.mime_type,'source_profile_version_id',e.source_profile_version_id,'retention_class',e.retention_class,'retain_until',e.retain_until,'metadata',e.metadata);
end $$;
revoke all on function public.layer2_normalized_evidence_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_normalized_evidence_context(uuid) to service_role;
notify pgrst,'reload schema';
