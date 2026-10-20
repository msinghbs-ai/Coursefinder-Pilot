CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_scoped_v1(p_course_ids uuid[], p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'search', 'catalogue', 'scholarship', 'pipeline', 'ref', 'extensions', 'pg_temp'
AS $function$
declare v_result jsonb;
begin
  if p_course_ids is null or cardinality(p_course_ids) = 0 then
    return jsonb_build_object('projection_version','course-v3','scope','courses','requested_courses',0,'apply',p_apply,'rows',0,'changed',0,'unchanged',0);
  end if;
  v_result := search.refresh_course_enrichment_core_scoped_v1(p_course_ids, p_apply);
  if p_apply then
    update search.course_documents d
    set semantic_content_hash=encode(extensions.digest(jsonb_build_object(
      'course',d.course_stable_key,
      'provider',d.provider_name,
      'title',d.course_title,
      'code',d.course_code,
      'level',d.study_level_code,
      'field',d.primary_field_code,
      'collections',d.collection_names,
      'academic_options',d.academic_option_names,
      'description',d.description
    )::text,'sha256'),'hex')
    where d.enrichment_semantic_text is null and d.course_id = any(p_course_ids);
  end if;
  return v_result;
end
$function$
