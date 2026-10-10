-- CF-203 — structure UNSW International Student Award from captured first-party detail Evidence and stage Course scope review.
update scholarship.scholarships
set award_value_text='20% of tuition',
    award_value_type='percentage',
    award_percentage=20,
    award_amount=null,
    award_currency_code=null,
    award_applies_to_fee_type='tuition_fee',
    award_fee_basis='tuition_fee',
    award_duration_basis='program_duration',
    updated_at=now()
where id='28e59737-a341-50b2-a972-4afa543c171c'::uuid
  and publication_status='unpublished'
  and evidence_id='fb130186-fd3e-4d74-b15b-af25bf3e3c68'::uuid
  and source_url='https://www.scholarships.unsw.edu.au/international-student-award';

insert into scholarship.course_mapping_candidates(scholarship_id,course_id,candidate_reason,evidence_id,status)
select s.id,c.id,
       'CF-203 provider-course candidate: first-party UNSW International Student Award is 20% tuition for program duration, but eligible-country and program exclusions require governed review before Course mapping.',
       s.evidence_id,'needs_review'
from scholarship.scholarships s
join catalogue.courses c on c.provider_id=s.provider_id and c.lifecycle_status='active'
where s.id='28e59737-a341-50b2-a972-4afa543c171c'::uuid
  and s.publication_status='unpublished'
  and not exists(select 1 from scholarship.course_mappings m where m.scholarship_id=s.id and m.course_id=c.id)
on conflict(scholarship_id,course_id) do nothing;

comment on column scholarship.scholarships.award_duration_basis is 'Governed award duration. CF-203 records UNSW International Student Award as 20% tuition for program duration from captured first-party detail Evidence; Course/country eligibility remains a separate review gate.';
