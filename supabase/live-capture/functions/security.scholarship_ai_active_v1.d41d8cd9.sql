CREATE OR REPLACE FUNCTION security.scholarship_ai_active_v1()
 RETURNS TABLE(model_code text, model_identifier text, prompt_version integer, ai_admission boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select m.code, m.model_identifier, (select p.version from pipeline.scholarship_ai_prompts p where p.active order by p.version desc limit 1), s.ai_admission
    -- v2.15.250: the first model in the chain reads first
    from pipeline.scholarship_ai_extract_settings s left join pipeline.scholarship_ai_models m on m.code = coalesce(s.chain[1], (select m2.code from pipeline.scholarship_ai_models m2 where m2.status = 'active' limit 1)) where s.id = 1
$function$
