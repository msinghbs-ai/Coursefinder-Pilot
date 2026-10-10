CREATE OR REPLACE FUNCTION public.website_v2_course(p_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'scholarship', 'security', 'api'
AS $function$
declare v_id uuid; v_matches int; v jsonb; v_outcomes_ok boolean;
begin
  if nullif(btrim(coalesce(p_identifier,'')),'') is null then raise exception 'INVALID_INPUT: course_id or course_code required' using errcode='22023'; end if;
  select count(*) into v_matches from search.course_documents d where lower(d.course_stable_key)=lower(btrim(p_identifier)) or lower(d.course_code)=lower(btrim(p_identifier));
  select d.course_id into v_id from search.course_documents d
   where lower(d.course_stable_key)=lower(btrim(p_identifier)) or lower(d.course_code)=lower(btrim(p_identifier))
   order by (lower(d.course_stable_key)=lower(btrim(p_identifier))) desc, d.course_stable_key limit 1;
  if v_id is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  v := api.website_v2_course_item(v_id);
  select exists (select 1 from search.enrichment_gates g where g.projection_code='courses' and g.domain_code='provider_outcomes' and g.gate_status='approved') into v_outcomes_ok;
  v := v || jsonb_build_object(
    'description', (select c.description from catalogue.courses c where c.id=v_id),
    'english_note', (select string_agg(distinct e->>'notes', ' | ') from search.course_documents d, jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
                      where d.course_id=v_id and e->>'notes' ~* 'check the course page'),
    'tuition_history', coalesce((select jsonb_agg(jsonb_build_object('year', f.fee_year, 'amount', f.amount, 'currency', f.currency_code, 'basis', f.basis,
                          'source', case f.fee_type when 'tuition' then 'regulatory_registered' when 'provider_current_tuition' then 'provider_current' else f.fee_type end)
                          order by f.fee_year desc nulls last, f.fee_type)
                        from catalogue.course_fees f where f.course_id=v_id and f.status='active' and f.audience in ('international','all') and f.fee_type in ('tuition','provider_current_tuition')), '[]'::jsonb),
    'scholarships', coalesce((select jsonb_agg(jsonb_build_object('scholarship_id', s->>'scholarship_key', 'name', s->>'name', 'amount_note', s->>'award_value_text',
                          'amount_is_maximum', s->'is_maximum', 'saving_per_year', s->'saving_per_year', 'saving_currency', s->'saving_currency',
                          'application_deadline', s->'application_close_date', 'official_url', s->>'source_url'))
                        from search.course_documents d, jsonb_array_elements(coalesce(d.scholarship_options,'[]'::jsonb)) s where d.course_id=v_id), '[]'::jsonb),
    'provider_outcomes_state', case when v_outcomes_ok then 'admitted' else 'not_admitted' end,
    'provider_outcomes', case when v_outcomes_ok then coalesce((select jsonb_agg(jsonb_build_object('survey', sv.code, 'metric_code', m.code, 'metric_name', m.name,
                          'study_level', o.source_cohort_code, 'value', o.metric_value, 'unit', m.unit, 'ci_low', o.confidence_low, 'ci_high', o.confidence_high,
                          'reference_year', o.collection_year_to, 'responses', o.response_count, 'grain', 'provider'))
                        from catalogue.provider_outcomes o join ref.outcome_metrics m on m.id=o.metric_id join ref.outcome_surveys sv on sv.id=o.survey_id
                        join search.course_documents d on d.provider_id=o.provider_id and d.course_id=v_id
                        where o.status in ('active','accepted') and o.external_study_area_id is null), '[]'::jsonb) else '[]'::jsonb end,
    'other_matches', greatest(v_matches - 1, 0));
  return jsonb_build_object('contract_version','website-search-v2','item',v);
end $function$
