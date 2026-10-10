create index if not exists pipeline_jobs_activity_time_idx
  on pipeline.jobs ((coalesce(completed_at,started_at,created_at)) desc, id);
create index if not exists pipeline_jobs_status_activity_time_idx
  on pipeline.jobs (status, (coalesce(completed_at,started_at,created_at)) desc);
create index if not exists pipeline_evidence_activity_time_idx
  on pipeline.evidence_artifacts ((coalesce(captured_at,created_at)) desc, id);
create index if not exists workflow_review_activity_time_idx
  on workflow.review_queue ((coalesce(updated_at,created_at)) desc, id);
