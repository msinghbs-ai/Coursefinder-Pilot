CREATE OR REPLACE FUNCTION security.admin_provider_scholarships(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'scholarship', 'catalogue', 'auth'
AS $function$
declare v_rank integer; v_items jsonb; v_total integer; v_mapped_courses integer; v_review integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'scholarship_id',s.id,'name',s.name,'scholarship_type',s.scholarship_type,'audience',s.audience,
   'award_value_text',s.award_value_text,'award_value_type',s.award_value_type,'award_percentage',s.award_percentage,
   'award_amount',s.award_amount,'award_currency_code',s.award_currency_code,'academic_year',s.academic_year,
   'application_close_date',s.application_close_date,'lifecycle_status',s.lifecycle_status,'publication_status',s.publication_status,
   'source_url',s.source_url,'evidence_id',s.evidence_id,
   'mapped_course_count',(select count(*) from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped')
 ) order by s.name),'[]'::jsonb),count(*)::int
 into v_items,v_total from scholarship.scholarships s where s.provider_id=p_provider_id;
 select count(distinct m.course_id)::int into v_mapped_courses from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id where s.provider_id=p_provider_id and m.mapping_state='mapped';
 select count(*)::int into v_review from scholarship.course_mapping_candidates c join scholarship.scholarships s on s.id=c.scholarship_id where s.provider_id=p_provider_id and c.status='needs_review';
 return jsonb_build_object('items',v_items,'scholarship_count',coalesce(v_total,0),'mapped_course_count',coalesce(v_mapped_courses,0),'needs_review_count',coalesce(v_review,0));
end $function$
