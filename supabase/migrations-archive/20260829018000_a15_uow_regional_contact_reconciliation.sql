-- A15: reconcile UOW current regional recruitment rows to the first-party
-- Agent partners & representatives page and retire parser artifacts.
update pipeline.provider_contact_observations
set job_title='International Student Recruitment',
    team_name='International Recruitment',
    territory_text=case full_name
      when 'Winn Wen' then 'Greater China and North Asia (excl. Japan)'
      when 'Feras Sallan' then 'Pakistan, Middle East, Africa and ROW'
      when 'Grace Gan Shin Chee' then 'Southeast Asia'
      when 'Gerald Joshua' then 'South Asia (excl. Pakistan)'
      when 'Faheem Naseer' then 'Onshore and College'
      else territory_text
    end,
    confidence=greatest(coalesce(confidence,0),0.98),
    metadata=metadata||jsonb_build_object(
      'a15_quality_reconciliation','uow_first_party_regional_experts',
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where provider_id='62e61a02-9fcb-4c5e-bb11-1c43bed6eee6'::uuid
  and is_current=true
  and verification_state<>'rejected'
  and full_name in ('Winn Wen','Feras Sallan','Grace Gan Shin Chee','Gerald Joshua','Faheem Naseer');

update pipeline.provider_contact_observations o
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=o.metadata||jsonb_build_object(
      'a15_quality_disposition',
      case when lower(coalesce(o.full_name,''))='agent expression'
           then 'rejected_cta_false_name'
           else 'rejected_duplicate_team_phone' end,
      'a15_quality_review_at',now()
    ),
    updated_at=now()
where o.provider_id='62e61a02-9fcb-4c5e-bb11-1c43bed6eee6'::uuid
  and o.is_current=true
  and o.verification_state<>'rejected'
  and (
    lower(coalesce(o.full_name,''))='agent expression'
    or (
      o.work_email is null
      and o.work_phone is not null
      and exists (
        select 1
        from pipeline.provider_contact_observations x
        where x.provider_id=o.provider_id
          and x.id<>o.id
          and x.is_current=true
          and x.verification_state<>'rejected'
          and x.work_phone=o.work_phone
          and x.work_email is not null
      )
    )
  );
