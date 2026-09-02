begin;
create index if not exists scholarship_catalogue_runs_evidence_idx
  on pipeline.scholarship_catalogue_runs(evidence_id);
create index if not exists scholarship_catalogue_runs_profile_version_idx
  on pipeline.scholarship_catalogue_runs(source_profile_version_id)
  where source_profile_version_id is not null;
commit;