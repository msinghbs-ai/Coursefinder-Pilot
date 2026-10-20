CREATE OR REPLACE FUNCTION public.manual_pim_candidate_decide(p_candidate_id uuid, p_action text, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'pim_api'
AS $function$
 select pim_api.manual_pim_candidate_decide(p_candidate_id,p_action,p_reason)
$function$
