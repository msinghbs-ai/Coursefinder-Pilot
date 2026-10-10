CREATE OR REPLACE FUNCTION security.admin_course_page_search_state(p_page jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'search', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(
    i.item || jsonb_build_object(
      'search_projected', d.course_id is not null,
      'search_projection_status', d.publication_status,
      'search_projection_completeness', d.completeness_score,
      'search_projection_version', d.projection_version,
      'search_catalogue_generation', d.catalogue_generation,
      'search_projection_updated_at', d.updated_at,
      'search_projection_generated_at', d.generated_at,
      'search_has_fee', d.has_fee,
      'search_has_intake', d.has_intake,
      'search_has_english', d.has_english,
      'search_has_scholarship', d.has_scholarship
    ) order by i.ord
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(p_page->'items','[]'::jsonb)) with ordinality as i(item,ord)
  left join search.course_documents d on d.course_id=nullif(i.item->>'id','')::uuid;

  return jsonb_set(coalesce(p_page,'{}'::jsonb),'{items}',v_items,true);
end
$function$
