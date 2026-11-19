with x as (
  select j.id job_id,(j.payload->>'candidate_id')::uuid candidate_id,j.payload->>'source_evidence_id' evidence_id,j.payload->>'target_url' target_url
  from pipeline.jobs j
  where j.domain='scholarship' and j.payload->>'change_control_ref'='CF-159'
    and j.status='failed' and j.error_text like 'layer2-scholarship-extract 409: catalogue_enumeration_required%'
)
update pipeline.layer2_scholarship_discovery_candidates c
set classification='catalogue_or_filter',
    classification_reason='extractor confirmed catalogue_enumeration_required; retained as catalogue Evidence, not individual Scholarship',
    classified_at=now()
from x where c.id=x.candidate_id;

with x as (
  select j.id job_id,j.payload->>'source_evidence_id' evidence_id,j.payload->>'target_url' target_url
  from pipeline.jobs j
  where j.domain='scholarship' and j.payload->>'change_control_ref'='CF-159'
    and j.status='failed' and j.error_text like 'layer2-scholarship-extract 409: catalogue_enumeration_required%'
)
update pipeline.jobs j
set status='succeeded',completed_at=now(),error_text=null,
    result=jsonb_build_object(
      'source_evidence_id',x.evidence_id,
      'extraction',jsonb_build_object('skipped',true,'reason','catalogue_enumeration_required','classification','catalogue_or_filter'),
      'publication_changed',false,'canonical_mutation_authorised',false
    )
from x where j.id=x.job_id;
