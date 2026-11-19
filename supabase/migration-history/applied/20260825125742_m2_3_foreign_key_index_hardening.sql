-- M2.3 performance hardening for foreign-key paths introduced by CF-CHG-20260825-038.
create index if not exists layer3_interpretations_profile_idx on pipeline.layer3_interpretations(profile_id);
create index if not exists layer3_model_profiles_fallback_idx on pipeline.layer3_model_profiles(fallback_profile_id) where fallback_profile_id is not null;
create index if not exists layer4_review_items_evidence_idx on pipeline.layer4_review_items(evidence_id) where evidence_id is not null;
create index if not exists layer4_decisions_evidence_idx on pipeline.layer4_decisions(evidence_id) where evidence_id is not null;
create index if not exists layer4_decisions_scalar_resolution_idx on pipeline.layer4_decisions(scalar_resolution_id) where scalar_resolution_id is not null;
create index if not exists refresh_requests_important_date_idx on pipeline.refresh_requests(important_date_id) where important_date_id is not null;
create index if not exists important_dates_evidence_idx on pipeline.important_dates(evidence_id) where evidence_id is not null;
