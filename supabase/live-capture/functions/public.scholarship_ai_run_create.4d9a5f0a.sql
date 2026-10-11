CREATE OR REPLACE FUNCTION public.scholarship_ai_run_create(p_country_code text, p_task_class text, p_profile_id uuid, p_limit integer DEFAULT 10, p_trigger_mode text DEFAULT 'manual'::text, p_changes_only boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.scholarship_ai_run_create_impl(p_country_code,p_task_class,p_profile_id,p_limit,p_trigger_mode,p_changes_only) $function$
