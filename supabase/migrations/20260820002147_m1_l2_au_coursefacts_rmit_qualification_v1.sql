update pipeline.course_fact_source_qualifications
set qualification_status='bounded',
    metadata=metadata || jsonb_build_object(
      'gate','M1-L2-AU-COURSE-FACTS',
      'layer1_prerequisite','passed',
      'apply_admitted',true,
      'search_admitted',false
    ),
    notes='RMIT official course pages admitted for bounded M1-L2-AU-COURSE-FACTS UAT after accepted layer1-au-depth-v1.6.0 completeness baseline; exact CRICOS Course-code mapping required; Search remains blocked.',
    updated_at=now()
where source_key='au_rmit_official_course_pages';
