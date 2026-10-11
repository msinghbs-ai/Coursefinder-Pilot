CREATE OR REPLACE FUNCTION security.scholarship_scope_apply_saved_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n int := 0;
begin
  for r in select distinct d.scholarship_id, d.decided_by from pipeline.scholarship_scope_decisions d
             join scholarship.course_mapping_candidates c on c.scholarship_id = d.scholarship_id and c.status = 'needs_review' loop
    perform security.scholarship_scope_apply_v1(r.scholarship_id, r.decided_by); n := n + 1;
  end loop;
  return n;
end $function$
