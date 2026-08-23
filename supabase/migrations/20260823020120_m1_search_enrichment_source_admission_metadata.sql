update pipeline.course_fact_source_qualifications
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
  'search_admitted',true,
  'search_admission_ref','CF-CHG-20260823-023',
  'search_admitted_at',now(),
  'search_projection_version','course-v3'
), updated_at=now()
where qualification_status='qualified'
  and source_key in ('au_rmit_official_course_pages','au_uq_official_program_pages');
