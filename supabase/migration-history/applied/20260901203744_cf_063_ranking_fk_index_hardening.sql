
create index if not exists ranking_editions_source_artifact_idx on ranking.editions(source_artifact_id) where source_artifact_id is not null;
create index if not exists ranking_manual_import_evidence_idx on ranking.manual_imports(evidence_artifact_id) where evidence_artifact_id is not null;
create index if not exists ranking_observation_evidence_idx on ranking.observations(evidence_artifact_id) where evidence_artifact_id is not null;
create index if not exists ranking_observation_publisher_idx on ranking.observations(publisher_institution_id);
create index if not exists ranking_provider_mapping_evidence_idx on ranking.provider_mappings(evidence_artifact_id) where evidence_artifact_id is not null;
