CREATE OR REPLACE FUNCTION security.toolset_setting(p_toolset text, p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key
$function$
