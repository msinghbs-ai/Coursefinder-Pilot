CREATE OR REPLACE FUNCTION public.admin_catalogue_edit_rows(p_type text, p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 100 then raise exception 'at most 100 rows at a time'; end if;
  if p_type = 'course' then
    return jsonb_build_object('can_edit', v_rank >= 3,
      'english_tests', (select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name) order by t.code), '[]'::jsonb)
                          from ref.english_tests t where t.status = 'active'),
      'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'display_title', coalesce(c.display_title, c.canonical_title),
        'duration_value', c.duration_value, 'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode,
        'official_url', coalesce((select l.url from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course'
                                    and l.status = 'active' order by l.is_primary desc, l.updated_at desc limit 1), c.course_url),
        'tuition', (select jsonb_build_object('amount', f.amount, 'fee_year', f.fee_year, 'basis', f.basis, 'currency', f.currency_code)
                      from catalogue.course_fees f where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status = 'active'
                     order by f.fee_year desc nulls last, f.updated_at desc limit 1),
        'intakes', (select coalesce(jsonb_agg(jsonb_build_object('label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date)
                                     order by i.intake_year nulls last, i.start_date nulls last, i.intake_label), '[]'::jsonb)
                      from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active'),
        'english', (select coalesce(jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)
                                     order by t.code), '[]'::jsonb)
                      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                     where e.course_id = c.id and e.status = 'active'),
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id))), '{}'::jsonb)
      from catalogue.courses c where c.id = any(p_ids)));
  elsif p_type = 'provider' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(p.id, jsonb_build_object(
        'display_name', coalesce(p.display_name, p.canonical_name), 'primary_city', p.primary_city, 'website', p.website,
        'phone', p.phone, 'email', p.email,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p.id))), '{}'::jsonb)
      from catalogue.providers p where p.id = any(p_ids)));
  elsif p_type = 'campus' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
        'name', c.name, 'address_line1', c.address_line1, 'city', c.city, 'postcode', c.postcode, 'phone', c.phone, 'website', c.website,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'campus' and k.entity_id = c.id))), '{}'::jsonb)
      from catalogue.campuses c where c.id = any(p_ids)));
  elsif p_type = 'scholarship' then
    return jsonb_build_object('can_edit', v_rank >= 3, 'rows', (select coalesce(jsonb_object_agg(s.id, jsonb_build_object(
        'name', s.name, 'award_value_text', s.award_value_text, 'award_amount', s.award_amount, 'award_percentage', s.award_percentage,
        'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date, 'source_url', s.source_url,
        'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id))), '{}'::jsonb)
      from scholarship.scholarships s where s.id = any(p_ids)));
  end if;
  raise exception 'unknown list %', p_type;
end $function$
