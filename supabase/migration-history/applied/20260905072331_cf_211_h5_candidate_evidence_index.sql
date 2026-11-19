create index if not exists pim_source_candidates_evidence_idx on pipeline.pim_source_candidates(evidence_id) where evidence_id is not null;
