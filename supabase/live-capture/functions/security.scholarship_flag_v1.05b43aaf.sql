CREATE OR REPLACE FUNCTION security.scholarship_flag_v1(p_key text, p_default boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$
