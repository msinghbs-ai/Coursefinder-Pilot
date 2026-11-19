CREATE OR REPLACE FUNCTION public.svc_ranking_latest_import(p_system_code text, p_edition_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
declare v jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'id',mi.id,'edition_year',mi.edition_year,'source_url',mi.source_url,'methodology_url',mi.methodology_url,
   'revision_note',mi.revision_note,'original_filename',mi.original_filename,'mime_type',mi.mime_type,'byte_size',mi.byte_size,
   'content_hash',mi.content_hash,'storage_path',mi.storage_path,'evidence_artifact_id',mi.evidence_artifact_id,'status',mi.status
 ) into v
 from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id
 where s.code=p_system_code and mi.edition_year=p_edition_year and mi.status in ('uploaded','validated','parsed','needs_review','reconciled','applied')
 order by mi.uploaded_at desc limit 1;
 return coalesce(v,'{}'::jsonb);
end
$function$
