alter function search.refresh_course_enrichment_v1(boolean) rename to refresh_course_enrichment_core_v1;

revoke all on function search.refresh_course_enrichment_core_v1(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_enrichment_core_v1(boolean) to service_role;

create or replace function search.refresh_course_enrichment_v1(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=search,extensions,pg_temp
as $function$
declare
  v_result jsonb;
begin
  v_result:=search.refresh_course_enrichment_core_v1(p_apply);
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
    where d.enrichment_semantic_text is null;
  end if;
  return v_result;
end
$function$;

revoke all on function search.refresh_course_enrichment_v1(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_enrichment_v1(boolean) to service_role;

create or replace function search.refresh_course_documents_v3(p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=search,pg_temp
as $function$
declare
  v_base jsonb;
  v_enrichment jsonb;
begin
  v_base:=search.refresh_course_documents_v2(p_apply);
  v_enrichment:=search.refresh_course_enrichment_v1(p_apply);
  return jsonb_build_object('base',v_base,'enrichment',v_enrichment);
end
$function$;
revoke all on function search.refresh_course_documents_v3(boolean) from public,anon,authenticated;
grant execute on function search.refresh_course_documents_v3(boolean) to service_role;
