-- CF-247 (3 Oct 2026, 11:00 AEST). Platform Admin, 10:46: "We can leave notes on the evidence linked to field if any
-- correction is required later by platform admin or operators, need to provide some mechanism with api from zoho
-- consumer/counsellor to flag or report back the edit."
-- Two ways to say "this value needs a look", both landing on Layer 4 › Flagged values as an open flag on the course's
-- field, with the note, who said it and where it came from; a value is never changed by a note.
-- 1. A counsellor, through the Zoho course API (action "report", service side): zoho_edge_report_v1.
-- 2. An operator or Platform Admin, from the course page: admin_value_note_add (assigned CourseFinder role).
create or replace function public.zoho_edge_report_v1(p_course text, p_field text, p_note text, p_reporter jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
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
end $f$;
revoke all on function public.zoho_edge_report_v1(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.zoho_edge_report_v1(text, text, text, jsonb) to service_role;

create or replace function public.admin_value_note_add(p_course_id uuid, p_field text, p_note text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
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
end $f$;
revoke all on function public.admin_value_note_add(uuid, text, text) from public, anon;
grant execute on function public.admin_value_note_add(uuid, text, text) to authenticated;
