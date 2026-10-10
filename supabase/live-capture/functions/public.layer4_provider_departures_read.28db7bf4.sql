CREATE OR REPLACE FUNCTION public.layer4_provider_departures_read(p_status text DEFAULT 'needs_review'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.layer4_provider_departures_read_v1(p_status) $function$
