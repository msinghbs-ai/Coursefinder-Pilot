-- CF-204 — structure UWA International Student Award as an explicitly evidenced annual fixed tuition reduction.
update scholarship.scholarships
set award_value_text='$5,000 per year tuition fee reduction',
    award_value_type='fixed_amount',
    award_percentage=null,
    award_amount=5000,
    award_currency_code='AUD',
    award_applies_to_fee_type='tuition_fee',
    award_fee_basis='tuition_fee',
    award_duration_basis='annual_program_duration',
    updated_at=now()
where id='e425011f-0ef9-52c2-a508-5e921783a027'::uuid
  and publication_status='unpublished'
  and evidence_id='3e787c84-20e6-480f-9c32-6ec5ce71051b'::uuid
  and source_url='https://www.uwa.edu.au/study/scholarships-and-fees/scholarships/international-scholarships/international-student-award';
comment on column scholarship.scholarships.award_amount is 'Fixed award amount when explicitly evidenced. CF-204 records UWA International Student Award as AUD 5,000 per year tuition reduction for program duration; fixed-amount Course net-fee calculation is not yet authorised by the percentage-only calculator.';
