CREATE OR REPLACE FUNCTION public.layer4_scholarship_scope_groups(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'l4_api'
AS $function$select l4_api.layer4_scholarship_scope_groups(p_limit)$function$
