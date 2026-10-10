CREATE OR REPLACE FUNCTION public.svc_coverage_reextract_next(p_limit integer, p_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('course_id',cp.course_id,'storage_path',e.storage_path,'title',c.canonical_title,'code',c.course_code,'status',cp.status,'url',cp.url,'country',security.coverage_country(cp.provider_id))),'[]'::jsonb)
    into v
    from (select * from pipeline.coverage_course_pages cp0
           where cp0.read_status='read' and cp0.identity_basis is not null and cp0.evidence_id is not null
             and coalesce(cp0.candidates->>'extractor','')<>p_version
           order by exists (select 1 from pipeline.layer4_review_items r4 where r4.entity_id = cp0.course_id and r4.status = 'pending'
                          and r4.field_code = 'provider_current_tuition_validation') desc, cp0.read_at limit greatest(1,least(coalesce(p_limit,50),200))) cp
    join pipeline.evidence_artifacts e on e.id=cp.evidence_id join catalogue.courses c on c.id=cp.course_id;
  return v;
end $function$
