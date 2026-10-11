CREATE OR REPLACE FUNCTION public.svc_scholarship_inspect_paths(p_scholarship_ids uuid[], p_candidate_ids bigint[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship'
AS $function$
  select jsonb_build_object(
    'scholarships', coalesce((select jsonb_agg(jsonb_build_object('scholarship_id',s.id,'name',s.name,'provider_id',s.provider_id,'url',coalesce(sp.final_url,sp.url),'storage_path',e.storage_path,'names',security.provider_name_list(s.provider_id)))
        from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id=s.id left join pipeline.evidence_artifacts e on e.id=sp.evidence_id
       where s.id=any(coalesce(p_scholarship_ids,'{}'))),'[]'::jsonb),
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'url',coalesce(c.final_url,c.url),'storage_path',c.storage_path))
        from pipeline.scholarship_page_candidates c where c.id=any(coalesce(p_candidate_ids,'{}'))),'[]'::jsonb))
$function$
