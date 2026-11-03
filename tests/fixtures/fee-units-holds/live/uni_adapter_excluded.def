CREATE OR REPLACE FUNCTION security.uni_adapter_excluded(p_course_id uuid, p_field text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when p_field = 'delivery'
              then exists (select 1 from pipeline.uni_adapter_delivery_exclusions d where d.course_id = p_course_id and d.active)
              else exists (select 1 from pipeline.uni_adapter_exclusions x where x.course_id = p_course_id and x.field = p_field and x.active) end
$function$
