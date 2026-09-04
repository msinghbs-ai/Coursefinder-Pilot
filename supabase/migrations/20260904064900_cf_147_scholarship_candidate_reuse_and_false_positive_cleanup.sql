-- CF-147 — Reuse existing Evidence-backed Scholarship acquisition and demote generic-global false positives.
-- No new scraping, canonical creation or Publication mutation occurs here.

update pipeline.layer2_scholarship_discovery_candidates c
set status='acquired',
    classification_reason='reused_existing_evidence_backed_canonical_trace',
    classified_at=now()
where c.status='discovered'
  and c.classification='detail_ready'
  and exists (
    select 1
    from pipeline.scholarship_acquisition_trace t
    where t.provider_id=(select s.provider_id from pipeline.sources s where s.id=c.source_id)
      and t.first_party_detail_url=c.detail_target_url
      and t.verification_evidence_id is not null
      and t.scholarship_id is not null
      and t.stage in ('detail_acquired','canonical_unpublished','layer4_review','publication_decided','published')
  );

update pipeline.layer2_scholarship_discovery_candidates c
set classification='needs_review',
    classification_reason='generic_global_word_without_explicit_international_eligibility',
    classified_at=now()
where c.status='discovered'
  and c.classification='detail_ready'
  and lower(coalesce(c.observed_title,'')) like '%global%'
  and lower(coalesce(c.observed_title,'')) not like '%international%'
  and lower(coalesce(c.observed_title,'')) not like '%asean%'
  and lower(coalesce(c.observed_title,'')) not like '%overseas%';
