CREATE OR REPLACE FUNCTION public.scholarship_ai_settings_write(p_country_code text, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'admin_api'
AS $function$select admin_api.scholarship_ai_settings_write(p_country_code,p_patch)$function$
