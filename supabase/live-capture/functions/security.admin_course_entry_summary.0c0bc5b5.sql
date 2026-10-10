CREATE OR REPLACE FUNCTION security.admin_course_entry_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'pipeline'
AS $function$
declare
  v_rank integer;
begin
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'intakes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'intake_year', i.intake_year,
          'intake_label', i.intake_label,
          'start_date', i.start_date,
          'application_deadline', i.application_deadline,
          'campus_id', i.campus_id,
          'campus', case when ca.id is null then null else jsonb_build_object(
            'id', ca.id,
            'stable_key', ca.stable_key,
            'name', ca.name,
            'city', ca.city,
            'subdivision_code', sd.code,
            'subdivision_name', sd.name,
            'country_code', co.iso_alpha2
          ) end,
          'status', i.status,
          'confidence', i.confidence,
          'source_intake_key', i.source_intake_key,
          'source', jsonb_build_object(
            'source_id', i.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'valid_from', e.valid_from,
            'valid_to', e.valid_to,
            'content_hash', e.content_hash
          ) end
        ) order by i.intake_year, i.start_date nulls last, i.intake_label
      )
      from catalogue.course_intakes i
      left join catalogue.campuses ca on ca.id=i.campus_id
      left join ref.countries co on co.id=ca.country_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      left join pipeline.sources s on s.id=i.source_id
      left join pipeline.evidence_artifacts e on e.id=i.evidence_id
      where i.course_id=p_course_id
    ), '[]'::jsonb),
    'english_requirements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', er.id,
          'test_id', et.id,
          'test_code', et.code,
          'test_name', et.name,
          'score_scale', et.score_scale,
          'overall_score', er.overall_score,
          'component_scores', er.component_scores,
          'notes', er.notes,
          'status', er.status,
          'confidence', er.confidence,
          'source_requirement_key', er.source_requirement_key,
          'valid_from', er.valid_from,
          'valid_to', er.valid_to,
          'last_verified_at', er.last_verified_at,
          'scope', 'course',
          'source', jsonb_build_object(
            'source_id', er.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'valid_from', e.valid_from,
            'valid_to', e.valid_to,
            'content_hash', e.content_hash
          ) end
        ) order by et.code
      )
      from catalogue.course_english_requirements er
      join ref.english_tests et on et.id=er.english_test_id
      left join pipeline.sources s on s.id=er.source_id
      left join pipeline.evidence_artifacts e on e.id=er.evidence_id
      where er.course_id=p_course_id
    ), '[]'::jsonb)
  );
end;
$function$
