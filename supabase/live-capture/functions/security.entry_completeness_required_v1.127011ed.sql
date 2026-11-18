CREATE OR REPLACE FUNCTION security.entry_completeness_required_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(security.toolset_setting('pipeline', 'entry.completeness_providers'), '[]'::jsonb) ? p_provider::text
$function$
