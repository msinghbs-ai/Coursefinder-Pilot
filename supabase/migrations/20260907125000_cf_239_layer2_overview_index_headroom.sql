-- CF-239 targeted recovery: exact-predicate index headroom.
-- No query/data semantics change. These indexes match predicates already used by
-- security.admin_layer2_ops_read('layer2_ops_overview', ...).

create index if not exists evidence_artifacts_layer2_overview_coalesce_idx
  on pipeline.evidence_artifacts (review_state, retention_class, captured_at desc)
  where coalesce(metadata->>'layer','')='2';

create index if not exists layer2_course_discovery_selected_url_course_idx
  on pipeline.layer2_course_discovery_candidates (course_id)
  where selected
    and discovered_url is not null
    and discovered_url <> '';

create index if not exists layer2_provider_attempts_overview_cover_idx
  on pipeline.layer2_provider_attempts
    (acquisition_provider_id, status, response_http_status, completed_at, started_at, created_at desc);
