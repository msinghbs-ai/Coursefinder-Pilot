-- CF-185 — terms/conditions PDF documents are supporting Evidence, not individual Scholarship detail records.
update pipeline.layer2_scholarship_discovery_candidates c
set classification='support_or_navigation',classification_reason='CF-185 scholarship terms/conditions PDF retained as supporting Evidence; not an individual Scholarship detail',classified_at=now()
where c.id in (
 select nullif(j.payload->>'candidate_id','')::uuid from pipeline.jobs j
 where j.domain='scholarship' and j.job_type='scholarship_scope_acquisition' and j.status='failed'
   and j.error_text like '%attempt_has_no_evidence%'
   and lower(coalesce(j.payload->>'target_url','')) ~ '(terms[-_% ]*and[-_% ]*conditions|tcs[-_ .%0-9]*\.pdf|terms.*\.pdf|conditions.*\.pdf)'
);

update pipeline.jobs j
set status='succeeded',completed_at=now(),error_text=null,
    result=jsonb_build_object('skipped',true,'reason','CF-185 terms/conditions PDF is supporting Evidence, not Scholarship detail','publication_changed',false,'canonical_mutation_authorised',false)
where j.domain='scholarship' and j.job_type='scholarship_scope_acquisition' and j.status='failed'
  and j.error_text like '%attempt_has_no_evidence%'
  and lower(coalesce(j.payload->>'target_url','')) ~ '(terms[-_% ]*and[-_% ]*conditions|tcs[-_ .%0-9]*\.pdf|terms.*\.pdf|conditions.*\.pdf)';
