CREATE OR REPLACE FUNCTION public.layer4_provider_departure_decide(p_id bigint, p_decision text, p_successor_provider_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.layer4_provider_departure_decide_v1(p_id,p_decision,p_successor_provider_id,p_reason) $function$
