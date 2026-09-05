-- CF-199 — structure only unambiguous first-party percentage tuition awards.
update scholarship.scholarships s
set award_value_type='percentage',
    award_percentage=(regexp_match(s.award_value_text,'^([0-9]+(?:\.[0-9]+)?)%'))[1]::numeric,
    award_amount=null,
    award_currency_code=null,
    award_applies_to_fee_type='tuition_fee',
    award_fee_basis='tuition_fee',
    award_duration_basis=case when s.source_url='https://scholarships.uq.edu.au/scholarship/uq-international-excellence-scholarship' then 'program_duration' else s.award_duration_basis end,
    updated_at=now()
where s.publication_status='unpublished'
  and s.evidence_id is not null
  and coalesce(s.award_value_type,'text_only')='text_only'
  and s.award_value_text ~ '^[0-9]+(?:\.[0-9]+)?% (of tuition|reduction)$'
  and (s.source_url like 'https://www.griffith.edu.au/%' or s.source_url like 'https://www.uts.edu.au/%' or s.source_url like 'https://scholarships.uq.edu.au/%');
comment on column scholarship.scholarships.award_percentage is 'Percentage award value when explicitly evidenced. CF-199 structures only unambiguous first-party percentage tuition/reduction text; tiered/up-to and non-tuition awards remain unresolved.';
