CREATE OR REPLACE FUNCTION security.admin_course_rankings(p_course_id uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_provider_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select c.provider_id into v_provider_id from catalogue.courses c where c.id=p_course_id;
  if v_provider_id is null then return '{}'::jsonb; end if;
  return security.admin_provider_rankings(v_provider_id,p_limit);
end
$function$
