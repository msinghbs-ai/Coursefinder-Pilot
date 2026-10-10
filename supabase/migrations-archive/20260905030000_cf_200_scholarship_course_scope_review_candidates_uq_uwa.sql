-- CF-200 — stage Course scope candidates for human/governed review; do not auto-map.
insert into scholarship.course_mapping_candidates(scholarship_id,course_id,candidate_reason,evidence_id,status)
select s.id,c.id,
       case s.source_url
         when 'https://scholarships.uq.edu.au/scholarship/uq-international-excellence-scholarship' then 'CF-200 provider-course candidate: first-party Scholarship states international undergraduate/postgraduate coursework and eligible-program scope; exact program eligibility requires governed review before mapping.'
         when 'https://www.uwa.edu.au/study/scholarships-and-fees/scholarships/international-scholarships/global-excellence-scholarship' then 'CF-200 provider-course candidate: first-party Scholarship covers eligible undergraduate/postgraduate courses with explicit exclusions; review required before mapping.'
         when 'https://www.uwa.edu.au/study/scholarships-and-fees/scholarships/international-scholarships/international-student-award' then 'CF-200 provider-course candidate: first-party Scholarship covers eligible undergraduate/postgraduate courses; exact course/country eligibility requires governed review before mapping.'
       end,
       s.evidence_id,'needs_review'
from scholarship.scholarships s
join catalogue.courses c on c.provider_id=s.provider_id and c.lifecycle_status='active'
where s.publication_status='unpublished' and s.evidence_id is not null
  and s.source_url in (
    'https://scholarships.uq.edu.au/scholarship/uq-international-excellence-scholarship',
    'https://www.uwa.edu.au/study/scholarships-and-fees/scholarships/international-scholarships/global-excellence-scholarship',
    'https://www.uwa.edu.au/study/scholarships-and-fees/scholarships/international-scholarships/international-student-award')
  and not exists(select 1 from scholarship.course_mappings m where m.scholarship_id=s.id and m.course_id=c.id)
on conflict(scholarship_id,course_id) do nothing;
comment on table scholarship.course_mapping_candidates is 'Human-review Scholarship→Course candidates. CF-200 expands candidates only for evidence-backed UQ/UWA provider-course scope; no candidate becomes a mapped Course without governed acceptance.';
