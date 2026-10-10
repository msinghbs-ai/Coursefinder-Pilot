CREATE OR REPLACE FUNCTION security.admin_course_taxonomy_summary(p_course_id uuid)
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
    'study_level_observations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'scheme', o.scheme,
          'registration_code', o.registration_code,
          'source_value', o.source_value,
          'mapping_status', o.mapping_status,
          'canonical_level', jsonb_build_object(
            'id', sl.id,
            'code', sl.code,
            'name', sl.name
          ),
          'status', o.status,
          'valid_from', o.valid_from,
          'valid_to', o.valid_to,
          'source_snapshot_at', o.source_snapshot_at,
          'observed_at', o.observed_at,
          'last_verified_at', o.last_verified_at,
          'content_hash', o.content_hash,
          'source', jsonb_build_object(
            'source_id', o.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'content_hash', e.content_hash
          ) end
        ) order by o.observed_at desc nulls last
      )
      from catalogue.course_study_level_observations o
      join ref.study_levels sl on sl.id=o.study_level_id
      left join pipeline.sources s on s.id=o.source_id
      left join pipeline.evidence_artifacts e on e.id=o.evidence_id
      where o.course_id=p_course_id
    ), '[]'::jsonb),
    'field_observations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'source_field_code', o.source_field_code,
          'source_field_name', o.source_field_name,
          'canonical_field', jsonb_build_object(
            'id', f.id,
            'code', f.code,
            'name', f.name
          ),
          'is_primary', o.is_primary,
          'status', o.status,
          'observed_at', o.observed_at,
          'source', jsonb_build_object(
            'source_id', o.source_id,
            'source_label', s.label,
            'source_type', s.source_type,
            'source_url', s.url
          ),
          'evidence', case when e.id is null then null else jsonb_build_object(
            'id', e.id,
            'type', e.evidence_type,
            'source_url', e.source_url,
            'captured_at', e.captured_at,
            'content_hash', e.content_hash
          ) end
        ) order by o.is_primary desc, o.observed_at desc nulls last
      )
      from catalogue.course_field_observations o
      join ref.fields_of_study f on f.id=o.field_id
      left join pipeline.sources s on s.id=o.source_id
      left join pipeline.evidence_artifacts e on e.id=o.evidence_id
      where o.course_id=p_course_id
    ), '[]'::jsonb)
  );
end;
$function$
