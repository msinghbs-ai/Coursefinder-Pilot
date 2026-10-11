CREATE OR REPLACE FUNCTION public.svc_scholarship_reextract_next(p_limit integer, p_version text)
 RETURNS TABLE(scholarship_id uuid, storage_path text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return query
    select sp.scholarship_id, e.storage_path
      from pipeline.scholarship_pages sp
      join scholarship.scholarships s on s.id = sp.scholarship_id and s.lifecycle_status = 'active'
      join pipeline.evidence_artifacts e on e.id = sp.evidence_id and e.storage_path is not null
     where sp.read_status = 'read' and sp.facts is not null
       and coalesce(sp.facts->>'criteria_extractor', '') is distinct from p_version
       and coalesce(sp.facts->>'extractor', '') is distinct from p_version
     order by s.publication_status = 'published' desc, sp.scholarship_id
     limit greatest(1, least(p_limit, 300));
end $function$
