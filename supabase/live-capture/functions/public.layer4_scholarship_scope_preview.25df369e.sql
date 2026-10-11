CREATE OR REPLACE FUNCTION public.layer4_scholarship_scope_preview(p_scholarship_id uuid, p_candidate_reason text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'l4_api'
AS $function$select l4_api.layer4_scholarship_scope_preview(p_scholarship_id,p_candidate_reason)$function$
