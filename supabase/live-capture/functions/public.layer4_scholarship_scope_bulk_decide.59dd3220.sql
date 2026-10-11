CREATE OR REPLACE FUNCTION public.layer4_scholarship_scope_bulk_decide(p_scholarship_id uuid, p_candidate_reason text, p_action text, p_reason text, p_confirmation text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'l4_api'
AS $function$select l4_api.layer4_scholarship_scope_bulk_decide(p_scholarship_id,p_candidate_reason,p_action,p_reason,p_confirmation)$function$
