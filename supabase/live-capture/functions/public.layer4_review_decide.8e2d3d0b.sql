CREATE OR REPLACE FUNCTION public.layer4_review_decide(p_review_item_id uuid, p_action text, p_reason text, p_final_value jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.layer4_review_decide_impl(p_review_item_id,p_action,p_reason,p_final_value) $function$
