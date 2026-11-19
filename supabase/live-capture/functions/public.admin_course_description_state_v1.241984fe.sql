CREATE OR REPLACE FUNCTION public.admin_course_description_state_v1(p_course_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := 200; -- fixed: one screen page of rows (the Course Catalogue page size is the setting; this only bounds a hand-made call)
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_course_ids is null or cardinality(p_course_ids) = 0 then return jsonb_build_object('courses', '[]'::jsonb); end if;
  if cardinality(p_course_ids) > v_cap then raise exception 'ask for at most % courses at a time', v_cap; end if;
  return jsonb_build_object('read_at', now(), 'machine_ledger', security.cdesc_machine_ids_v1(p_course_ids) is not null,
    'recheck_days', security.pipeline_num_v1('gaps.recheck_days', 60)::int, 'courses_per_request', security.pipeline_num_v1('run_now.pilot_cap', 20)::int,
    'courses', (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('fill_info', security.cdesc_block_info_v1(s.fill_block), 'recheck_info', security.cdesc_block_info_v1(s.recheck_block)) order by s.title, s.course_id), '[]'::jsonb)
                  from security.cdesc_state_v1(p_course_ids, null) s));
end $function$
