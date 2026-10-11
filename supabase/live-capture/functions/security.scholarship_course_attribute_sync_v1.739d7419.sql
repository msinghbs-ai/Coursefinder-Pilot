CREATE OR REPLACE FUNCTION security.scholarship_course_attribute_sync_v1(p_full boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'search', 'security'
AS $function$
declare v_since timestamptz; v_now timestamptz := now(); v_ids uuid[]; v_res jsonb; v_done int := 0; v_batch uuid[]; i int := 0;
begin
  select last_run_at into v_since from pipeline.scholarship_attribute_sync where id = 1;
  if p_full then
    select array_agg(distinct x) into v_ids from (
      select course_id x from scholarship.course_mappings where mapping_state = 'mapped'
      union select d.course_id from search.course_documents d where coalesce(jsonb_array_length(d.scholarship_options), 0) > 0) q;
  else
    select array_agg(distinct x) into v_ids from (
      select m.course_id x from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id where s.updated_at > v_since
      union select fc.course_id from scholarship.course_financial_calculations fc where fc.calculated_at > v_since
      union select m.course_id from scholarship.course_mappings m join pipeline.scholarship_publication_batches b on m.scholarship_id = any(b.scholarship_ids) where b.created_at > v_since
      union select m.course_id from scholarship.course_mappings m where m.updated_at > v_since) q;
  end if;
  v_ids := coalesce(v_ids, '{}');
  while i * 2000 < cardinality(v_ids) loop
    v_batch := v_ids[i * 2000 + 1 : (i + 1) * 2000];
    v_res := search.refresh_course_enrichment_core_scoped_v1(v_batch, true);
    v_done := v_done + coalesce((v_res->>'changed')::int, 0);
    i := i + 1;
  end loop;
  v_res := jsonb_build_object('full', p_full, 'courses', cardinality(v_ids), 'changed', v_done, 'since', v_since);
  update pipeline.scholarship_attribute_sync set last_run_at = v_now, last_result = v_res where id = 1;
  return v_res;
end $function$
