begin;

create index if not exists course_fees_evidence_verified_idx
  on catalogue.course_fees(evidence_id,last_verified_at desc)
  where evidence_id is not null;

create index if not exists course_regulatory_observations_evidence_verified_idx
  on catalogue.course_regulatory_observations(evidence_id,last_verified_at desc)
  where evidence_id is not null;

analyze catalogue.course_fees;
analyze catalogue.course_regulatory_observations;

commit;
