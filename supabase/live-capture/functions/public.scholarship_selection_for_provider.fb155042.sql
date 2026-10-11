CREATE OR REPLACE FUNCTION public.scholarship_selection_for_provider(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.scholarship_selection_for_provider_browser_bridge(p_provider_id) $function$
