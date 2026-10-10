-- A15 bounded integration exposed intermittent Evidence-detail latency on mobile.
-- Additive indexes for admin_evidence_related_visual; no authority/semantic change.
create index if not exists layer2_provider_attempt_raw_evidence_idx
  on pipeline.layer2_provider_attempts(raw_evidence_id)
  where raw_evidence_id is not null;

create index if not exists layer2_provider_attempt_html_evidence_idx
  on pipeline.layer2_provider_attempts(html_evidence_id)
  where html_evidence_id is not null;

create index if not exists layer2_provider_attempt_screenshot_evidence_idx
  on pipeline.layer2_provider_attempts(screenshot_evidence_id)
  where screenshot_evidence_id is not null;
