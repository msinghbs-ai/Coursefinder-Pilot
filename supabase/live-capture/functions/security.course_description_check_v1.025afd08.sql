CREATE OR REPLACE FUNCTION security.course_description_check_v1(p_course uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 course descriptions (6 Nov 2026): the check is security.course_description_check_with_v1 with the course word lists from settings
  select security.course_description_check_with_v1(p_course, p_result, null, null)
$function$
