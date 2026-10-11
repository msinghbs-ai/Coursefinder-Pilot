CREATE OR REPLACE FUNCTION public.admin_scholarship_links_detail(p_scholarship_id uuid, p_decision text DEFAULT NULL::text, p_filter jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_s scholarship.scholarships%rowtype; v_dec text; v_f jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select * into v_s from scholarship.scholarships where id = p_scholarship_id;
  if v_s.id is null then raise exception 'scholarship not found'; end if;
  select coalesce(p_decision, d.decision, sg->>'decision'), coalesce(p_filter, d.filter, sg->'filter') into v_dec, v_f
    from (select security.scholarship_scope_suggest(p_scholarship_id) sg) z left join pipeline.scholarship_scope_decisions d on d.scholarship_id = p_scholarship_id;
  return (with cc as (select c.id candidate_id, c.status, co.id course_id, coalesce(co.display_title, co.canonical_title) title, co.course_code,
                             co.study_level_id, security.broad_field_id(co.primary_field_id) field_id,
                             security.scholarship_scope_match(co.id, v_dec, v_f) ok
                        from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id
                       where c.scholarship_id = p_scholarship_id)
    select jsonb_build_object(
      'scholarship', jsonb_build_object('id', v_s.id, 'name', v_s.name, 'award', v_s.award_value_text, 'award_type', v_s.award_value_type,
                     'award_percentage', v_s.award_percentage, 'award_amount', v_s.award_amount, 'currency', v_s.award_currency_code,
                     'source_url', v_s.source_url, 'audience', v_s.audience, 'academic_year', v_s.academic_year,
                     'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_s.provider_id)),
      'proposed', (select count(*) from cc), 'waiting', (select count(*) from cc where status = 'needs_review'),
      'levels', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'count', n) order by l.sort_order), '[]'::jsonb)
                   from (select study_level_id, count(*) n from cc group by 1) g join ref.study_levels l on l.id = g.study_level_id),
      'fields', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'count', n) order by n desc), '[]'::jsonb)
                   from (select field_id, count(*) n from cc group by 1) g join ref.fields_of_study f on f.id = g.field_id),
      'suggestion', security.scholarship_scope_suggest(p_scholarship_id),
      'decision', (select jsonb_build_object('decision', d.decision, 'filter', d.filter, 'reason', d.reason, 'at', d.decided_at, 'by', u.email,
                          'accepted', d.accepted, 'rejected', d.rejected)
                     from pipeline.scholarship_scope_decisions d left join auth.users u on u.id = d.decided_by where d.scholarship_id = p_scholarship_id),
      'preview', jsonb_build_object('decision', v_dec, 'filter', v_f,
                   'matched', (select count(*) from cc where ok), 'not_matched', (select count(*) from cc where not ok),
                   'sample_matched', (select coalesce(jsonb_agg(jsonb_build_object('id', course_id, 'title', title, 'code', course_code)), '[]'::jsonb) from (select * from cc where ok order by title limit 12) a),
                   'sample_not_matched', (select coalesce(jsonb_agg(jsonb_build_object('id', course_id, 'title', title, 'code', course_code)), '[]'::jsonb) from (select * from cc where not ok order by title limit 8) b)),
      'can_decide', v_rank >= 4));
end $function$
