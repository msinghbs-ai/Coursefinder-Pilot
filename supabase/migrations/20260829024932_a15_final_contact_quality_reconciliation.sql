-- A15 final contact-quality reconciliation before cohort freeze.

-- Restore the already reconciled, source-backed VU email+phone observations.
update pipeline.provider_contact_observations
set verification_state='current',
    is_current=true,
    valid_to=null,
    confidence=greatest(coalesce(confidence,0),0.98),
    metadata=metadata||jsonb_build_object(
      'a15_quality_reconciliation','vu_final_preferred_contact',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where id in (
  '35b784a0-6497-48b4-9764-b8442cd5ff27'::uuid,
  '09b5ad4a-9b32-4c30-85ba-6c15a1ffda06'::uuid
);

-- Retire lower-quality phone-only parser variants for those Provider identities.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_vu_phone_only_duplicate',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where id in (
  '766e934b-eccb-463b-87be-26a6017b9773'::uuid,
  'b70f0142-2b9b-4b93-94a9-dd8710d1314b'::uuid
);

-- Otago first-party page publishes a team-level International Marketing and Recruitment contact.
-- Do not retain parser-invented person/territory semantics.
update pipeline.provider_contact_observations
set full_name=null,
    job_title='International Marketing and Recruitment',
    team_name='International Marketing and Recruitment',
    territory_text=null,
    confidence=greatest(coalesce(confidence,0),0.98),
    metadata=metadata||jsonb_build_object(
      'a15_quality_reconciliation','otago_team_contact',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where id='6943d523-2ff9-47e9-9a81-7c893d7c9755'::uuid
  and is_current=true
  and verification_state<>'rejected';
