-- A15: preserve but reject low-confidence fallback rows from the UQ structured regional-manager proof.
update pipeline.provider_contact_observations
set verification_state='rejected',
    is_current=false,
    valid_to=coalesce(valid_to,now()),
    metadata=metadata||jsonb_build_object(
      'a15_quality_disposition','rejected_structured_table_fallback',
      'a15_quality_review_at',now(),
      'superseded_by_worker','provider-contact-discover-scheduled-v1.1.2'
    ),
    updated_at=now()
where provider_id='e55396d2-869a-46ef-9d17-841c7eab1313'::uuid
  and source_class='first_party'
  and metadata->>'worker_version'='provider-contact-discover-scheduled-v1.1.1'
  and coalesce(confidence,0)<0.95
  and verification_state <> 'rejected';

insert into pipeline.provider_contact_watch_events(
  provider_id,observation_id,event_type,source_class,before_state,after_state,metadata
)
select
  o.provider_id,o.id,'contact_removed','first_party',
  jsonb_build_object('verification_state','current','is_current',true),
  jsonb_build_object('verification_state','rejected','is_current',false),
  jsonb_build_object('reason','a15_structured_table_fallback','worker_version','provider-contact-discover-scheduled-v1.1.2')
from pipeline.provider_contact_observations o
where o.provider_id='e55396d2-869a-46ef-9d17-841c7eab1313'::uuid
  and o.metadata->>'a15_quality_disposition'='rejected_structured_table_fallback'
  and not exists (
    select 1 from pipeline.provider_contact_watch_events e
    where e.observation_id=o.id
      and e.event_type='contact_removed'
      and e.metadata->>'reason'='a15_structured_table_fallback'
  );
