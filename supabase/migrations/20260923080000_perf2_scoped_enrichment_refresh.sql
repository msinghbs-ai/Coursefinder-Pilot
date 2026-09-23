-- PERF-2: scoped search-projection refresh.
-- search.refresh_course_enrichment_core_v1 stages all ~33k courses and, when applying,
-- rewrites every row (no changed-only filter), rebuilding each full-text entry. Admission
-- called it for a handful of fees, causing 60-70 s of heavy I/O every run and statement
-- timeouts for concurrent user reads.
-- This adds a scoped variant generated from the live definition by exact substitution
-- (identical logic, restricted to p_course_ids). The full refresh is unchanged for its
-- other callers. Guarded: each substitution must match exactly once.
do $mig$
declare d text; n int;
  a1 text := 'CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_core_v1(p_apply boolean DEFAULT false)';
  b1 text := 'CREATE OR REPLACE FUNCTION search.refresh_course_enrichment_core_scoped_v1(p_course_ids uuid[], p_apply boolean DEFAULT false)';
  a2 text := E'  ) sc on true;\n\n  alter table cf_search_enrichment_stage';
  b2 text := E'  ) sc on true\n  where d.course_id = any(p_course_ids);\n\n  alter table cf_search_enrichment_stage';
  a3 text := $q$return jsonb_build_object('projection_version','course-v3','apply',p_apply,$q$;
  b3 text := $q$return jsonb_build_object('projection_version','course-v3','scope','courses','requested_courses',coalesce(cardinality(p_course_ids),0),'apply',p_apply,$q$;
begin
  d := pg_get_functiondef('search.refresh_course_enrichment_core_v1(boolean)'::regprocedure);
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  if (length(d)-length(replace(d,a3,'')))/length(a3) <> 1 then raise exception 'anchor 3 not found exactly once'; end if;
  execute replace(replace(replace(d,a1,b1),a2,b2),a3,b3);
end $mig$;

-- Scoped counterpart of search.refresh_course_enrichment_v1 (same post-step, restricted).
create or replace function search.refresh_course_enrichment_scoped_v1(p_course_ids uuid[], p_apply boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'search','catalogue','scholarship','pipeline','ref','extensions','pg_temp'
as $function$
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
$function$;

revoke all on function search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean) from public, anon, authenticated;
revoke all on function search.refresh_course_enrichment_scoped_v1(uuid[],boolean) from public, anon, authenticated;
grant execute on function search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean) to service_role;
grant execute on function search.refresh_course_enrichment_scoped_v1(uuid[],boolean) to service_role;
