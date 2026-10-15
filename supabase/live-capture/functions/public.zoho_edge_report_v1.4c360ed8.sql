CREATE OR REPLACE FUNCTION public.zoho_edge_report_v1(p_course text, p_field text, p_note text, p_reporter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_course uuid; v_id uuid; v_field text := lower(btrim(coalesce(p_field, 'other')));
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_field not in ('official_url', 'intakes', 'english', 'tuition', 'scholarship', 'title', 'duration', 'delivery', 'other') then v_field := 'other'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then return jsonb_build_object('error', 'NOTE_REQUIRED'); end if;
  select c.id into v_course from catalogue.courses c where c.id::text = p_course or c.stable_key = p_course limit 1;
  if v_course is null then return jsonb_build_object('error', 'NOT_FOUND'); end if;
  insert into pipeline.data_flags(entity_type, entity_id, field_code, flag_code, detail, status, change_control_ref)
  values ('course', v_course, v_field, 'reported',
          jsonb_build_object('note', left(btrim(p_note), 1000), 'source', 'zoho', 'reporter', coalesce(p_reporter, '{}'::jsonb), 'quotes', jsonb_build_array(left(btrim(p_note), 1000))),
          'open', 'CF-247')
  returning id into v_id;
  return jsonb_build_object('flag_id', v_id, 'course_id', v_course, 'field', v_field, 'status', 'open');
end $function$
