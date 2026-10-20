CREATE OR REPLACE FUNCTION public.layer3_holdout_cases_service(p_gold_set text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
begin
  perform public.layer3_routing_service_guard();
  return jsonb_build_object('gold_set',p_gold_set,
    'task_class',(select s.task_class from pipeline.layer3_holdout_sets s where s.gold_set=p_gold_set),
    'frozen_digest',(select s.digest from pipeline.layer3_holdout_sets s where s.gold_set=p_gold_set),
    'contract_fingerprint',(select s.contract_fingerprint from pipeline.layer3_holdout_sets s where s.gold_set=p_gold_set),
    'current_digest',pipeline.layer3_holdout_digest(p_gold_set),
    'cases',coalesce((select jsonb_agg(jsonb_build_object('case_id',c.id,'case_key',c.case_key,'course_id',c.course_id,'evidence_id',c.evidence_id,
            'storage_path',e.storage_path,'mime_type',e.mime_type,'source_url',e.source_url,'text_sha256',c.text_sha256,'gold',c.gold,
            'evidence_excerpt',c.evidence_excerpt,'candidate_context',c.candidate_context) order by c.case_key)
      from pipeline.layer3_holdout_cases c join pipeline.evidence_artifacts e on e.id=c.evidence_id where c.gold_set=p_gold_set),'[]'::jsonb));
end $function$
