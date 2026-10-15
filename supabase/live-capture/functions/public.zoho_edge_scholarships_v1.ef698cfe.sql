CREATE OR REPLACE FUNCTION public.zoho_edge_scholarships_v1(p_course text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_course uuid; v_sel jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select c.id into v_course from catalogue.courses c where c.id::text = p_course or c.stable_key = p_course limit 1;
  if v_course is null then return jsonb_build_object('error', 'NOT_FOUND'); end if;
  v_sel := security.scholarship_selection_for_course_impl(v_course);
  return jsonb_build_object(
    'course_id', v_course,
    'audience_filter', 'international',
    'scholarships', coalesce((
      select jsonb_agg(jsonb_build_object(
          'scholarship_id', s.id, 'stable_key', s.stable_key, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name),
          'audience', s.audience, 'nationalities', s.nationalities,
          'value', jsonb_build_object('text', scholarship.value_label(s.id), 'type', s.award_value_type, 'percentage', s.award_percentage, 'amount', s.award_amount, 'currency', s.award_currency_code, 'is_maximum', s.award_value_is_maximum,
                                      'tiers', (select jsonb_agg(jsonb_build_object('label', t.label, 'percentage', t.percentage, 'amount', t.amount, 'currency', t.currency_code, 'basis', t.basis) order by t.display_order) from scholarship.award_tiers t where t.scholarship_id = s.id)),
          'saving', (select jsonb_build_object('year', fc.fee_year, 'currency', fc.currency_code, 'tuition', fc.fee_amount, 'saving', fc.scholarship_saving_amount, 'net', fc.net_fee_amount, 'basis', fc.fee_basis, 'estimate', fc.fee_basis = 'estimated_annual_from_registered_total')
                       from scholarship.course_financial_calculations fc where fc.scholarship_id = s.id and fc.course_id = v_course and fc.calculation_status = 'calculated' order by fc.fee_year desc nulls last limit 1),
          'who_qualifies', (select jsonb_agg(jsonb_build_object('type', cr.criterion_type, 'text', cr.human_text, 'mandatory', cr.is_mandatory) order by cr.created_at) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
          'application', jsonb_build_object('required', s.application_required, 'opens', s.application_open_date, 'closes', s.application_close_date, 'academic_year', s.academic_year),
          'page', s.source_url,
          'match', e->'derived_score', 'selection_state', e->'selection_state', 'eligibility_state', e->'eligibility_state'))
        from jsonb_array_elements(coalesce(v_sel->'candidates', '[]'::jsonb)) e
        join scholarship.scholarships s on s.id = (e->>'scholarship_id')::uuid
        left join catalogue.providers p on p.id = s.provider_id
       where s.lifecycle_status = 'active' and s.publication_status = 'published'
         and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id)), '[]'::jsonb),  -- v2.15.236
    'read_at', now());
end $function$
