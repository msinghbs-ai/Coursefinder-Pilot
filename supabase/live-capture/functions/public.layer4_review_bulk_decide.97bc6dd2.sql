CREATE OR REPLACE FUNCTION public.layer4_review_bulk_decide(p_entity_type text, p_field_code text, p_escalation_reason text, p_action text, p_reason text, p_confirmation text, p_limit integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'l4_api'
AS $function$select l4_api.layer4_review_bulk_decide(p_entity_type,p_field_code,p_escalation_reason,p_action,p_reason,p_confirmation,p_limit)$function$
