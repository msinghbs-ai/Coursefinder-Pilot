-- Mirrors deployed 20260823104038 · CF-CHG-20260823-029
create index if not exists layer2_profiles_current_version_idx
  on pipeline.layer2_source_profiles(current_version_id)
  where current_version_id is not null;
