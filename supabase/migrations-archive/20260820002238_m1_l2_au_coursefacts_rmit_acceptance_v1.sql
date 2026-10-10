update pipeline.course_fact_source_qualifications
set qualification_status='qualified',
    metadata=metadata || jsonb_build_object(
      'gate','M1-L2-AU-COURSE-FACTS',
      'gate_result','pass',
      'apply_admitted',true,
      'search_admitted',false,
      'layer1_prerequisite','passed'
    ),
    notes='PASS: RMIT official course pages qualified as first bounded AU Provider source for M1-L2-AU-COURSE-FACTS. Exact CRICOS Course-code resolution, fresh evidence capture, provider-current fee semantics, intake and English observations, canonical replay idempotency and ambiguity rejection passed. Search remains separately blocked.',
    updated_at=now()
where source_key='au_rmit_official_course_pages';
