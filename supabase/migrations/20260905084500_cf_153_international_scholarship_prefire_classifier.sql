-- CF-153 — International-only Scholarship pre-fire classifier.
-- Preserve candidates for audit while removing clearly Australian/domestic-only catalogue cues from automatic detail acquisition.

update pipeline.layer2_scholarship_discovery_candidates c
set classification='needs_review',
    classification_reason='international_only_gate: domestic_or_australian_specific_catalogue_cue',
    classified_at=now()
from pipeline.sources s
where c.source_id=s.id
  and c.status='discovered'
  and c.classification='detail_ready'
  and s.provider_id=(select id from catalogue.providers where canonical_name='Monash University' limit 1)
  and lower(coalesce(c.observed_title,'')) ~ '(indigenous australian|aboriginal|torres strait|atsi|first nations|rural health|gippsland|victoria scholarship|victorian|australian government|wa health|care leaver|access monash|domestic student)'
  and lower(coalesce(c.observed_title,'')) !~ '(international|asean|overseas|indones|thai-born|foreign student)';

update pipeline.layer2_scholarship_discovery_candidates c
set classification_reason='international_only_gate: explicit overseas/international catalogue cue; first-party detail verification required',
    classified_at=now()
from pipeline.sources s
where c.source_id=s.id
  and c.status='discovered'
  and c.classification='detail_ready'
  and s.provider_id=(select id from catalogue.providers where canonical_name='Monash University' limit 1)
  and lower(coalesce(c.observed_title,'')) ~ '(international|asean|overseas|indones|thai-born|foreign student)';
