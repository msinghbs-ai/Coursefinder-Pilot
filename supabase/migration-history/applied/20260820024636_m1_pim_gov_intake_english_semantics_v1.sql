create or replace function security.admin_course_entry_summary(p_course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','catalogue','ref','pipeline'
as $function$
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
$function$;

revoke all on function security.admin_course_entry_summary(uuid) from public;
revoke execute on function security.admin_course_entry_summary(uuid) from authenticated;
grant execute on function security.admin_course_entry_summary(uuid) to service_role;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','security'
as $function$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation='courses_page' then
    return security.admin_course_page_search_state(security.admin_catalogue_page(p_operation,p_args));
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result
      || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))
      || jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id));
  end if;
  return v_result;
end;
$function$;

revoke execute on function public.ui_course_detail(uuid) from authenticated;
