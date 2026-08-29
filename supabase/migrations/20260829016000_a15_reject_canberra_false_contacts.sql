-- A15: preserve but reject University of Canberra false positives from generic study-area content.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_canberra_generic_study_area',
      'a15_quality_review_at',now(),
      'superseded_by_worker','provider-contact-discover-scheduled-v1.3.1'
    ),
    updated_at=now()
where provider_id='0e1532b8-de30-4761-87fe-460684608633'::uuid
  and source_class='first_party'
  and is_current=true;

insert into pipeline.provider_contact_watch_events(provider_id,observation_id,event_type,source_class,before_state,after_state,metadata)
select o.provider_id,o.id,'contact_removed',o.source_class,
       jsonb_build_object('verification_state','current','is_current',true),
       jsonb_build_object('verification_state','rejected','is_current',false),
       jsonb_build_object('reason','a15_canberra_generic_study_area','worker_version','provider-contact-discover-scheduled-v1.3.1','a15_quality_probe',true)
from pipeline.provider_contact_observations o
where o.provider_id='0e1532b8-de30-4761-87fe-460684608633'::uuid
  and o.metadata->>'a15_quality_disposition'='rejected_canberra_generic_study_area'
  and not exists (
    select 1 from pipeline.provider_contact_watch_events e
    where e.observation_id=o.id and e.metadata->>'reason'='a15_canberra_generic_study_area'
  );
