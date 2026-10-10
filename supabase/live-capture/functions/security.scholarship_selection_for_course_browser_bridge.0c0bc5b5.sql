CREATE OR REPLACE FUNCTION security.scholarship_selection_for_course_browser_bridge(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
begin
  if auth.uid() is not null and security.current_role_rank()<3 then
    raise exception 'CourseFinder reviewer/operator role required' using errcode='42501';
  end if;
  return security.scholarship_selection_for_course_impl(p_course_id);
end
$function$
