-- CF-CHG-20260830-048
-- M2.4.4: bound Dashboard Layer-status counts that were scanning whole tables.

create index if not exists layer2_scope_wave_items_status_idx
  on pipeline.layer2_scope_wave_items(status);

create index if not exists layer2_run_items_completed_at_idx
  on pipeline.layer2_run_items(completed_at desc)
  where completed_at is not null;

create index if not exists evidence_metadata_layer_captured_idx
  on pipeline.evidence_artifacts ((coalesce(metadata->>'layer','')), captured_at desc);
