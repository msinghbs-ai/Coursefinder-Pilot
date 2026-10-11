CREATE OR REPLACE FUNCTION public.scholarship_selection_for_course(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'security'
AS $function$ select security.scholarship_selection_for_course_browser_bridge(p_course_id) $function$
