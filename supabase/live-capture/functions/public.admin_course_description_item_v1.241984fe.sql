CREATE OR REPLACE FUNCTION public.admin_course_description_item_v1(p_course_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := 200; -- fixed: the same bound as public.admin_course_description_state_v1 (a hand-made call)
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_course_ids is null or cardinality(p_course_ids) = 0 then return jsonb_build_object('courses', '[]'::jsonb); end if;
  if cardinality(p_course_ids) > v_cap then raise exception 'ask for at most % courses at a time', v_cap; end if;
  return jsonb_build_object('read_at', now(), 'courses', security.cdesc_item_detail_v1(p_course_ids));
end $function$
