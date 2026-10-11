CREATE OR REPLACE FUNCTION security.scholarship_admission_withdraw_v1(p_scholarship_id uuid, p_reason jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'search'
AS $function$
declare s record; v_courses uuid[];
begin
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if s.id is null or s.lifecycle_status<>'active' then return jsonb_build_object('withdrawn',false); end if;
  if s.publication_status='published' then return jsonb_build_object('withdrawn',false,'reason','published; left for the publication review'); end if;
  if not exists (select 1 from pipeline.scholarship_pages where scholarship_id=s.id and url_source='admitted') then return jsonb_build_object('withdrawn',false,'reason','not admitted from a provider page'); end if;
  select coalesce(array_agg(course_id),'{}') into v_courses from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
  delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
  update scholarship.scholarships set lifecycle_status='inactive', updated_at=now() where id=s.id;
  update pipeline.scholarship_page_candidates set admit_status='withdrawn', admit_reasons=array(select jsonb_array_elements_text(coalesce(p_reason->'reasons','[]'))) where admitted_scholarship_id=s.id;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value) values (s.id,'admission_withdrawn',jsonb_build_object('lifecycle_status','active'),p_reason);
  insert into pipeline.scholarship_admission_log(scholarship_id,provider_id,action,detail) values (s.id,s.provider_id,'withdrawn',p_reason);
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  return jsonb_build_object('withdrawn',true);
end $function$
