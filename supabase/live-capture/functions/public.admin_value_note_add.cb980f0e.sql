CREATE OR REPLACE FUNCTION public.admin_value_note_add(p_course_id uuid, p_field text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_field text := lower(btrim(coalesce(p_field, 'other')));
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if v_field not in ('official_url', 'intakes', 'english', 'tuition', 'scholarship', 'title', 'duration', 'delivery', 'description', 'other') then raise exception 'unknown field %', p_field; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'a note is required'; end if;
  if not exists (select 1 from catalogue.courses where id = p_course_id) then raise exception 'course not found'; end if;
  insert into pipeline.data_flags(entity_type, entity_id, field_code, flag_code, detail, status, change_control_ref)
  values ('course', p_course_id, v_field, 'note',
          jsonb_build_object('note', left(btrim(p_note), 1000), 'source', 'admin', 'by', auth.uid(), 'quotes', jsonb_build_array(left(btrim(p_note), 1000))),
          'open', 'CF-247')
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('notes', 'add', v_field, jsonb_build_object('course_id', p_course_id, 'flag_id', v_id), auth.uid());
  return jsonb_build_object('flag_id', v_id);
end $function$
