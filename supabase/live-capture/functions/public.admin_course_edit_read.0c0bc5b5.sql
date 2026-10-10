CREATE OR REPLACE FUNCTION public.admin_course_edit_read(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.courses where id = p_course_id) then raise exception 'course not found'; end if;
  return (select jsonb_build_object(
    'course', jsonb_build_object('id', c.id, 'provider_id', c.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'course_code', c.course_code,
               'canonical_title', c.canonical_title, 'display_title', c.display_title, 'description', c.description, 'duration_value', c.duration_value,
               'duration_unit', c.duration_unit, 'delivery_mode', c.delivery_mode, 'lifecycle_status', c.lifecycle_status, 'course_url', c.course_url,
               'manual_course', c.stable_key like 'manual:%'),
    'official_links', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'is_primary', l.is_primary, 'source', s.label,
               'manual', s.source_type = 'manual_entry', 'updated_at', l.updated_at) order by l.is_primary desc, l.updated_at desc), '[]'::jsonb)
               from catalogue.course_links l left join pipeline.sources s on s.id = l.source_id
              where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active'),
    'intakes', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date,
               'source', s.label, 'manual', s.source_type = 'manual_entry') order by i.start_date nulls last, i.intake_label), '[]'::jsonb)
               from catalogue.course_intakes i left join pipeline.sources s on s.id = i.source_id where i.course_id = c.id and i.status = 'active'),
    'english', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'test', t.code, 'test_name', t.name, 'overall', e.overall_score,
               'components', e.component_scores, 'source', s.label, 'manual', s.source_type = 'manual_entry') order by t.name), '[]'::jsonb)
               from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id left join pipeline.sources s on s.id = e.source_id
              where e.course_id = c.id and e.status = 'active'),
    'tuition', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year,
               'basis', f.basis, 'source', s.label, 'manual', s.source_type = 'manual_entry') order by f.updated_at desc), '[]'::jsonb)
               from catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id
              where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status = 'active'),
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'course' and entity_id = c.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    'english_tests', (select jsonb_agg(jsonb_build_object('code', code, 'name', name) order by name) from ref.english_tests),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course_id);
end $function$
