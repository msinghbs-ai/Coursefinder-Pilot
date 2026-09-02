begin;

with detail as (
  select distinct on(sr.source_id)
    sr.id source_record_row_id,
    sr.source_id,
    sr.evidence_id,
    sr.payload,
    s.provider_id,
    nullif(s.metadata->>'candidate_id','')::uuid discovery_candidate_id,
    i.scholarship_id
  from pipeline.scholarship_source_records sr
  join pipeline.sources s on s.id=sr.source_id
  join scholarship.identifiers i
    on i.source_id=sr.source_id
   and i.scheme='first_party_detail_url'
   and i.identifier_value=sr.source_record_id
  where s.source_type='scholarship_detail'
    and s.metadata->>'change_control_ref'='CF-CHG-20260903-083'
    and sr.payload->>'identifier_scheme'='first_party_detail_url'
  order by sr.source_id,sr.observed_at desc
)
insert into pipeline.layer4_review_items(
  id,entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,
  before_value,proposed_value,layer2_state,layer3_state,status,assigned_to,
  escalation_reason,change_control_ref,created_at,decided_at
)
select
  extensions.gen_random_uuid(),
  'scholarship',
  d.scholarship_id,
  'scope_resolution',
  d.evidence_id,
  null,
  null,
  jsonb_build_object(
    'decision_required',true,
    'provider_id',d.provider_id,
    'audience',d.payload->>'audience',
    'award_value_text',d.payload->>'award_value_text',
    'application_close_text',d.payload->>'application_close_text',
    'eligibility_text',d.payload->>'eligibility_text',
    'source_url',d.payload->>'source_url',
    'requested_scope_actions',jsonb_build_array(
      'resolve_provider/course/study-level/field/campus applicability',
      'preserve include/exclude semantics',
      'do not publish until scope is accepted'
    )
  ),
  jsonb_build_object(
    'source_record_row_id',d.source_record_row_id,
    'source_id',d.source_id,
    'evidence_id',d.evidence_id,
    'extraction_worker',d.payload->>'extraction_worker',
    'scope_resolution_required',coalesce((d.payload->>'scope_resolution_required')::boolean,false),
    'canonical_root_created',true,
    'publication_status','unpublished'
  ),
  '{}'::jsonb,
  'pending',
  null,
  'Layer 2 Scholarship detail identity/facts accepted; course/provider applicability requires human scope decision before publication.',
  'CF-CHG-20260903-083',
  now(),
  null
from detail d
where coalesce((d.payload->>'scope_resolution_required')::boolean,false)
  and not exists(
    select 1
    from pipeline.layer4_review_items r
    where r.entity_type='scholarship'
      and r.entity_id=d.scholarship_id
      and r.field_code='scope_resolution'
      and r.status='pending'
  );

with detail as (
  select distinct on(sr.source_id)
    sr.id source_record_row_id,
    s.metadata,
    sr.source_id
  from pipeline.scholarship_source_records sr
  join pipeline.sources s on s.id=sr.source_id
  where s.source_type='scholarship_detail'
    and s.metadata->>'change_control_ref'='CF-CHG-20260903-083'
    and sr.payload->>'identifier_scheme'='first_party_detail_url'
  order by sr.source_id,sr.observed_at desc
)
update pipeline.scholarship_source_records sr
set status='applied',
    applied_at=now(),
    error_text=case
      when coalesce(sr.payload->>'scope_resolution_required','false')='true'
        then 'Canonical unpublished Scholarship root applied; scope_resolution pending Layer 4.'
      else null
    end
from detail d
where sr.id=d.source_record_row_id;

update pipeline.layer2_scholarship_discovery_candidates d
set status='acquired'
where d.id in (
  select nullif(s.metadata->>'candidate_id','')::uuid
  from pipeline.sources s
  where s.source_type='scholarship_detail'
    and s.metadata->>'change_control_ref'='CF-CHG-20260903-083'
)
and d.status='discovered';

commit;