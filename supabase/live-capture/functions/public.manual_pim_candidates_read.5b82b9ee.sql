CREATE OR REPLACE FUNCTION public.manual_pim_candidates_read(p_status text DEFAULT NULL::text, p_entity_type text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pim_api'
AS $function$
 select pim_api.manual_pim_candidates_read(p_status,p_entity_type,p_limit)
$function$
