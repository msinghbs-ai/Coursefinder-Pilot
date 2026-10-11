CREATE OR REPLACE FUNCTION security.scholarship_setting(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key = p_key), p_default)
$function$
