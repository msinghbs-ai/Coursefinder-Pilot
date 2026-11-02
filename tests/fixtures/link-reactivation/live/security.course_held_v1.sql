CREATE OR REPLACE FUNCTION security.course_held_v1(p_course uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- SS-007: an open binding remediation hold (unique partial index course_remediation_holds_open)
  select exists (select 1 from pipeline.course_remediation_holds h where h.course_id = p_course and h.lifted_at is null)
$function$
