-- CF-187 — park already-extracted generic collection/support records so CF-171 cannot canonicalise them.
update pipeline.scholarship_source_records sr
set status='unmapped',error_text='CF-187 generic Scholarship collection/support page; individual Scholarship reconciliation required'
where sr.status='captured' and lower(trim(coalesce(sr.payload->>'name',''))) in (
 'academic scholarships','external scholarships','scholarships and fees','financial aid for international students','home country sponsored scholarships'
);

update pipeline.layer2_scholarship_discovery_candidates c
set classification='support_or_navigation',classification_reason='CF-187 generic collection/support page excluded from individual Scholarship reconciliation',classified_at=now()
where c.status='discovered' and lower(trim(coalesce(c.observed_title,''))) in (
 'academic scholarships','external scholarships','scholarships and fees','financial aid for international students','home country sponsored scholarships'
);
