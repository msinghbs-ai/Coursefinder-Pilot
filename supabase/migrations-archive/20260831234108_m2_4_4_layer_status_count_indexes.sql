create index if not exists layer2_scope_wave_items_status_idx
  on pipeline.layer2_scope_wave_items(status);
create index if not exists layer2_run_items_completed_at_idx
  on pipeline.layer2_run_items(completed_at desc)
  where completed_at is not null;
create index if not exists evidence_metadata_layer_captured_idx
  on pipeline.evidence_artifacts ((coalesce(metadata->>'layer','')), captured_at desc);
