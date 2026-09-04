-- CF-116 — preserve the published Scholarship text and expose derived saving/net fee on the existing guarded Course Scholarship read.
create or replace function security.admin_course_scholarships(p_course_id uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','scholarship','catalogue','auth' as $$
declare v_rank integer; v_items jsonb; v_candidates integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'mapping_id',m.id,'scholarship_id',s.id,'name',s.name,'audience',s.audience,
   'award_value_text',case when fc.calculation_status='calculated' then concat_ws(' · ',s.award_value_text,concat('Saving ',trim(fc.currency_code::text),' ',to_char(fc.scholarship_saving_amount,'FM999G999G999G990D00')),concat('Net fee ',trim(fc.currency_code::text),' ',to_char(fc.net_fee_amount,'FM999G999G999G990D00'))) else s.award_value_text end,
   'published_award_value_text',s.award_value_text,'award_value_type',s.award_value_type,'award_percentage',s.award_percentage,'award_amount',s.award_amount,
   'award_currency_code',s.award_currency_code,'award_applies_to_fee_type',s.award_applies_to_fee_type,'award_fee_basis',s.award_fee_basis,'award_duration_basis',s.award_duration_basis,
   'academic_year',s.academic_year,'source_url',s.source_url,'evidence_id',coalesce(m.evidence_id,s.evidence_id),'mapping_basis',m.mapping_basis,'mapping_state',m.mapping_state,'mapped_at',m.mapped_at,
   'calculation',case when fc.id is null then null else jsonb_build_object('status',fc.calculation_status,'course_fee_id',fc.course_fee_id,'fee_amount',fc.fee_amount,'fee_type',fc.fee_type,'fee_basis',fc.fee_basis,'fee_year',fc.fee_year,'currency_code',fc.currency_code,'scholarship_saving_amount',fc.scholarship_saving_amount,'net_fee_amount',fc.net_fee_amount,'formula',fc.calculation_formula,'reason',fc.calculation_reason,'calculated_at',fc.calculated_at,'fee_evidence_id',fc.fee_evidence_id,'scholarship_evidence_id',fc.scholarship_evidence_id) end
 ) order by s.name),'[]'::jsonb) into v_items
 from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id left join scholarship.course_financial_calculations fc on fc.mapping_id=m.id
 where m.course_id=p_course_id and m.mapping_state='mapped';
 select count(*) into v_candidates from scholarship.course_mapping_candidates where course_id=p_course_id and status='needs_review';
 return jsonb_build_object('items',v_items,'mapped_count',jsonb_array_length(v_items),'needs_review_count',v_candidates,'state',case when jsonb_array_length(v_items)>0 then 'mapped' when v_candidates>0 then 'needs_review' else 'not_mapped' end);
end $$;
