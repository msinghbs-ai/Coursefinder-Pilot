-- A15: reapply accepted Wellington team reconciliation after post-freeze transport proof reran the parser.
-- A15: reconcile Wellington current-student international support contact
-- to the first-party International Student Experience team contact.
update pipeline.provider_contact_observations
set full_name=null,
    job_title='International Student Experience',
    team_name='International Student Experience',
    territory_text=null,
    work_email='international-support@vuw.ac.nz',
    work_phone='+64 4 463 5350',
    confidence=greatest(coalesce(confidence,0),0.98),
    metadata=metadata||jsonb_build_object(
      'a15_quality_reconciliation','wellington_international_student_experience',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where provider_id='34616965-b2b7-42a7-8da7-50ffbf120958'::uuid
  and is_current=true
  and verification_state<>'rejected'
  and source_url='https://www.wgtn.ac.nz/students/support/international/contact-us';
