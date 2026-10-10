CREATE OR REPLACE FUNCTION public.layer1_approve_departures(p_run_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'security'
AS $function$
  select security.admin_layer1_approve_departures_v1(p_run_id,p_reason)
$function$
