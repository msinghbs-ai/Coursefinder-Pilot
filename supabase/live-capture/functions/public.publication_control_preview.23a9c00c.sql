CREATE OR REPLACE FUNCTION public.publication_control_preview(p_entity_type text, p_entity_ids uuid[], p_target_scope text, p_action text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'l4_api'
AS $function$
 select l4_api.publication_control_preview(p_entity_type,p_entity_ids,p_target_scope,p_action)
$function$
