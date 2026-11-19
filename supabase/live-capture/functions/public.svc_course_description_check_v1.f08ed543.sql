CREATE OR REPLACE FUNCTION public.svc_course_description_check_v1(p_course uuid, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.course_description_check_v1(p_course, p_value);
end $function$
