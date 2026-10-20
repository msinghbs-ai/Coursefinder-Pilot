CREATE OR REPLACE FUNCTION public.scholarship_ai_run_status(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'admin_api'
AS $function$select admin_api.scholarship_ai_run_status(p_run_id)$function$
