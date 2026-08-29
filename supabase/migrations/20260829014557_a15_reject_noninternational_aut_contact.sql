-- A15: preserve but reject a generic doctoral admissions contact observed on an international page.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_noninternational_contact',
      'a15_quality_review_at',now(),
      'superseded_by_worker','provider-contact-discover-scheduled-v1.2.1'
    ),
    updated_at=now()
where provider_id='39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid
  and lower(coalesce(work_email,''))='doctoral.and.mphil.admissions@aut.ac.nz'
  and verification_state <> 'rejected';

insert into pipeline.provider_contact_watch_events(provider_id,observation_id,event_type,source_class,before_state,after_state,metadata)
select o.provider_id,o.id,'contact_removed',o.source_class,
       jsonb_build_object('verification_state','current','is_current',true),
       jsonb_build_object('verification_state','rejected','is_current',false),
       jsonb_build_object('reason','a15_noninternational_contact','worker_version','provider-contact-discover-scheduled-v1.2.1','a15_quality_probe',true)
from pipeline.provider_contact_observations o
where o.provider_id='39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid
  and lower(coalesce(o.work_email,''))='doctoral.and.mphil.admissions@aut.ac.nz'
  and o.metadata->>'a15_quality_disposition'='rejected_noninternational_contact'
  and not exists (
    select 1 from pipeline.provider_contact_watch_events e
    where e.observation_id=o.id and e.metadata->>'reason'='a15_noninternational_contact'
  );
