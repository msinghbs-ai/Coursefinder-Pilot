CREATE OR REPLACE FUNCTION security.toolset_enforced(p_toolset text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select t.enforcement is distinct from 'observe' from pipeline.platform_toolsets t where t.key = p_toolset), true)
$function$
