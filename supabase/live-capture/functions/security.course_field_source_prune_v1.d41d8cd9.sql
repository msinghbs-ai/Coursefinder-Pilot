CREATE OR REPLACE FUNCTION security.course_field_source_prune_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n integer;
begin
  delete from pipeline.course_field_source s where not exists (select 1 from catalogue.courses c where c.id = s.course_id and c.lifecycle_status = 'active');
  get diagnostics v_n = row_count;
  return v_n;
end $function$
