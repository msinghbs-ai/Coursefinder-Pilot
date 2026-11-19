CREATE OR REPLACE FUNCTION security.fc_courses_v1(p_provider_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select count(*)::int from catalogue.courses c where c.provider_id = p_provider_id and c.lifecycle_status = 'active' and c.course_code ~ '^[0-9]{6}[0-9A-Z]$'
$function$
