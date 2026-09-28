-- CF-247 Decision 162: "Awaiting L2" counts only sources that read course pages. A provider fee schedule covers only
-- the courses it lists, so for a provider whose only fee source is a schedule (Western Sydney, Charles Darwin,
-- Swinburne), a course missing from the schedule shows "CRICOS tuition applies" instead of waiting forever.
-- Checksum-guarded single-anchor patch of security.admin_course_field_states.
do $patch$
declare v_def text; v_old text; v_new text;
begin
  v_def:=pg_get_functiondef('security.admin_course_field_states(uuid)'::regprocedure);
  if md5(v_def)<>'3ba68ad05ee9dcf8ecfd4d382c37beff' then raise exception 'security.admin_course_field_states changed since review; not replaced'; end if;
  v_old:='q.qualification_status in (''qualified'',''bounded'');';
  v_new:='q.qualification_status in (''qualified'',''bounded'')'||chr(10)||
         '     and not exists (select 1 from pipeline.sources s where s.id=q.source_id and s.source_type=''provider_fee_schedule'');';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;

