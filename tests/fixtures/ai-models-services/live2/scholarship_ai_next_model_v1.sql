CREATE OR REPLACE FUNCTION security.scholarship_ai_next_model_v1(p_code text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.chain[array_position(s.chain, p_code) + 1] from pipeline.scholarship_ai_extract_settings s where s.id = 1 and array_position(s.chain, p_code) is not null
$function$
