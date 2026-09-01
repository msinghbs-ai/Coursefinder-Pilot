-- A15: preserve but reject a false person-name parse from Griffith contact opening-hours text.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_false_name_parse',
      'a15_quality_review_at',now(),
      'superseded_by_worker','provider-contact-discover-scheduled-v1.2.4'
    ),
    updated_at=now()
where provider_id='36086f5e-9fe0-4878-aa40-1897a7d8cb24'::uuid
  and lower(coalesce(full_name,''))='available monday'
  and verification_state <> 'rejected';

insert into pipeline.provider_contact_watch_events(provider_id,observation_id,event_type,source_class,before_state,after_state,metadata)
select o.provider_id,o.id,'contact_removed',o.source_class,
       jsonb_build_object('verification_state','current','is_current',true),
       jsonb_build_object('verification_state','rejected','is_current',false),
       jsonb_build_object('reason','a15_false_name_parse','worker_version','provider-contact-discover-scheduled-v1.2.4','a15_quality_probe',true)
from pipeline.provider_contact_observations o
where o.provider_id='36086f5e-9fe0-4878-aa40-1897a7d8cb24'::uuid
  and lower(coalesce(o.full_name,''))='available monday'
  and o.metadata->>'a15_quality_disposition'='rejected_false_name_parse'
  and not exists (
    select 1 from pipeline.provider_contact_watch_events e
    where e.observation_id=o.id and e.metadata->>'reason'='a15_false_name_parse'
  );
