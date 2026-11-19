CREATE OR REPLACE FUNCTION public.svc_ranking_inline_evidence_promote(p_evidence_id uuid, p_storage_path text, p_delete_inline boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'ranking'
AS $function$
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
$function$
