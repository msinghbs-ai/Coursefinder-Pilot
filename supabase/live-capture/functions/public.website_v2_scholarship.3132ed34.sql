CREATE OR REPLACE FUNCTION public.website_v2_scholarship(p_scholarship_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'security', 'api'
AS $function$
declare v_id uuid; v jsonb;
begin
  if nullif(btrim(coalesce(p_scholarship_id,'')),'') is null then raise exception 'INVALID_INPUT: scholarship_id required' using errcode='22023'; end if;
  select s.id into v_id from scholarship.scholarships s where s.stable_key = btrim(p_scholarship_id)
     and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id) limit 1;  -- v2.15.236
  if v_id is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  v := api.website_v2_scholarship_item(v_id);
  v := v || jsonb_build_object(
    'description', (select s.description from scholarship.scholarships s where s.id=v_id),
    'award_tiers', coalesce((select jsonb_agg(jsonb_build_object('label', t.label, 'amount', t.amount, 'currency', t.currency_code, 'percentage', t.percentage, 'basis', t.basis, 'maximum_amount', t.maximum_amount, 'notes', t.notes) order by t.display_order)
                             from scholarship.award_tiers t where t.scholarship_id=v_id), '[]'::jsonb),
    'linked_courses', coalesce((select jsonb_agg(x.j order by x.t) from (
         select d.course_title t, jsonb_build_object('course_id', d.course_stable_key, 'course_code', d.course_code, 'title', d.course_title,
                  'saving_per_year', (select fc.scholarship_saving_amount from scholarship.course_financial_calculations fc where fc.scholarship_id=v_id and fc.course_id=d.course_id and fc.calculation_status='calculated' order by fc.fee_year desc nulls last limit 1),
                  'saving_currency', (select fc.currency_code from scholarship.course_financial_calculations fc where fc.scholarship_id=v_id and fc.course_id=d.course_id and fc.calculation_status='calculated' order by fc.fee_year desc nulls last limit 1),
                  'saving_basis', (select fc.fee_basis from scholarship.course_financial_calculations fc where fc.scholarship_id=v_id and fc.course_id=d.course_id and fc.calculation_status='calculated' order by fc.fee_year desc nulls last limit 1)) j
         from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id
         where m.scholarship_id=v_id and m.mapping_state='mapped' order by d.course_title limit 200) x), '[]'::jsonb),
    'linked_courses_truncated', (select count(*) > 200 from scholarship.course_mappings m where m.scholarship_id=v_id and m.mapping_state='mapped'));
  return jsonb_build_object('contract_version','website-search-v2','item',v);
end $function$
