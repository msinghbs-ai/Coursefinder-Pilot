-- CF-CHG-20260902-081 post-advisor FK index hardening
begin;
create index if not exists provider_assets_evidence_idx on catalogue.provider_assets(evidence_id) where evidence_id is not null;
create index if not exists provider_asset_candidates_evidence_idx on pipeline.provider_asset_candidates(evidence_id) where evidence_id is not null;
create index if not exists provider_asset_candidates_profile_idx on pipeline.provider_asset_candidates(profile_id) where profile_id is not null;
create index if not exists layer2_shared_fetches_evidence_idx on pipeline.layer2_shared_fetches(evidence_id);
create index if not exists layer2_shared_fetches_provider_idx on pipeline.layer2_shared_fetches(acquisition_provider_id) where acquisition_provider_id is not null;
create index if not exists layer2_shared_fetches_profile_idx on pipeline.layer2_shared_fetches(source_profile_id) where source_profile_id is not null;
create index if not exists layer2_fanout_tasks_profile_idx on pipeline.layer2_fanout_tasks(profile_id);
commit;
