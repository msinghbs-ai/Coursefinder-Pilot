CREATE OR REPLACE FUNCTION public.scholarship_ai_control_read(p_country_code text DEFAULT 'AU'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.scholarship_ai_control_read_impl(p_country_code) $function$
