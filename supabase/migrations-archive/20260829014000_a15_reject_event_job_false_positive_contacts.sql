-- A15: preserve but reject false-positive contacts sourced from domestic job/event pages.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_event_job_false_positive',
      'a15_quality_review_at',now(),
      'superseded_by_worker','provider-contact-discover-scheduled-v1.2.6'
    ),
    updated_at=now()
where source_class='first_party'
  and verification_state <> 'rejected'
  and (
    lower(coalesce(source_url,'')) like '%/jobs/%'
    or lower(coalesce(source_url,'')) like '%domestic%'
    or (
      lower(coalesce(source_url,'')) like '%/events/%'
      and nullif(trim(coalesce(work_email,'')),'') is null
      and nullif(trim(coalesce(work_phone,'')),'') is null
    )
    or coalesce(work_phone,'') like '%.%'
  );

insert into pipeline.provider_contact_watch_events(provider_id,observation_id,event_type,source_class,before_state,after_state,metadata)
select o.provider_id,o.id,'contact_removed',o.source_class,
       jsonb_build_object('verification_state','current','is_current',true),
       jsonb_build_object('verification_state','rejected','is_current',false),
       jsonb_build_object('reason','a15_event_job_false_positive','worker_version','provider-contact-discover-scheduled-v1.2.6','a15_quality_probe',true)
from pipeline.provider_contact_observations o
where o.metadata->>'a15_quality_disposition'='rejected_event_job_false_positive'
  and not exists (
    select 1 from pipeline.provider_contact_watch_events e
    where e.observation_id=o.id and e.metadata->>'reason'='a15_event_job_false_positive'
  );
