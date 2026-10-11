CREATE OR REPLACE FUNCTION security.scholarship_fee_alignment_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_courses int := 0; v_refreshed int := 0;
begin
  for r in
    select distinct x.course_id from (
      select f.course_id from catalogue.course_fees f
       where f.audience = 'international' and f.fee_type = 'provider_current_tuition' and f.updated_at > now() - interval '70 minutes'
      union
      select c.course_id from pipeline.adapter_overwrite_changes c where c.field = 'fee' and c.at > now() - interval '70 minutes') x
    where exists (select 1 from scholarship.course_mappings m where m.course_id = x.course_id and m.mapping_state = 'mapped')
  loop
    v_courses := v_courses + 1;
    v_refreshed := v_refreshed + coalesce((scholarship.refresh_course_financial_calculations(r.course_id, null)->>'refreshed')::int, 0);
  end loop;
  return jsonb_build_object('courses', v_courses, 'refreshed', v_refreshed);
end $function$
