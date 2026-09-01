-- A15: reconcile Victoria University duplicate parser variants to one current
-- first-party international-student team contact per Provider identity.
with preferred as (
  select distinct on (provider_id)
         id,provider_id
  from pipeline.provider_contact_observations
  where provider_id in (
    'bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid,
    '0f5373c8-d724-4303-9267-739530a5ce53'::uuid
  )
    and is_current=true
    and verification_state<>'rejected'
  order by provider_id,(work_email is not null) desc,last_verified_at desc
)
update pipeline.provider_contact_observations o
set full_name=null,
    job_title='International Student Enquiries',
    team_name='VU International',
    territory_text=null,
    work_email='international@vu.edu.au',
    work_phone='+61 3 9919 1164',
    confidence=greatest(coalesce(o.confidence,0),0.98),
    metadata=o.metadata||jsonb_build_object(
      'a15_quality_reconciliation','vu_first_party_international_team',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
from preferred p
where o.id=p.id;

update pipeline.provider_contact_observations o
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=o.metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_vu_duplicate_parser_variant',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where o.provider_id in (
    'bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid,
    '0f5373c8-d724-4303-9267-739530a5ce53'::uuid
  )
  and o.is_current=true
  and o.verification_state<>'rejected'
  and o.id not in (
    select id from (
      select distinct on (provider_id) id
      from pipeline.provider_contact_observations
      where provider_id in (
        'bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid,
        '0f5373c8-d724-4303-9267-739530a5ce53'::uuid
      )
        and is_current=true
        and verification_state<>'rejected'
      order by provider_id,(work_email='international@vu.edu.au') desc,last_verified_at desc
    ) q
  );
