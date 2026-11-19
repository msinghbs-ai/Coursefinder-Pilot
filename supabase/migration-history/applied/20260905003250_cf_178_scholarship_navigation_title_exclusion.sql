update pipeline.layer2_scholarship_discovery_candidates c
set classification='support_or_navigation',classification_reason='CF-178 navigation/support title excluded from Scholarship detail acquisition',classified_at=now()
where c.status='discovered' and c.classification='detail_ready'
  and lower(trim(coalesce(c.observed_title,''))) in ('skip to main content','menu','go to top','faq','eligibility','guidelines','find a scholarship','scholarships');

-- Guard future reclassification by marking these rows outside the active detail classifier set.
comment on column pipeline.layer2_scholarship_discovery_candidates.classification is 'Scholarship candidate classifier. support_or_navigation and external_or_out_of_scope are terminal automatic-acquisition exclusions; detail_ready is executable only while status=discovered.';
