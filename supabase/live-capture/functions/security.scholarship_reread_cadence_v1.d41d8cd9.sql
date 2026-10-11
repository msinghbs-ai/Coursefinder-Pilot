CREATE OR REPLACE FUNCTION security.scholarship_reread_cadence_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'security'
AS $function$
declare v_n int := 0;
begin
  update pipeline.scholarship_pages sp set next_read_at = sp.read_at + make_interval(days => security.scholarship_setting('reread_days', 30)::int) from scholarship.scholarships s where s.id = sp.scholarship_id and s.lifecycle_status = 'active' and sp.read_at is not null and (sp.next_read_at is null or sp.next_read_at > sp.read_at + make_interval(days => security.scholarship_setting('reread_days', 30)::int)) and (s.publication_status = 'published' or exists (select 1 from security.scholarship_publishability_v1() p where p.scholarship_id = s.id and p.publishable));
  get diagnostics v_n = row_count;
  return jsonb_build_object('brought_forward', v_n);
end $function$
