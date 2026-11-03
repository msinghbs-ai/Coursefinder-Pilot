-- CF-247 Layer 4 Inbox performance fixture: the production indexes the Inbox reads use (read from pg_index on fxcwkweaxjtknorudmwp, read-only,
-- 4 Nov 2026 06:55 AEDT), so the timings are measured on the same access paths. Scratch PostgreSQL only; nothing here is live data.
create index if not exists layer4_review_items_status_created_idx on pipeline.layer4_review_items (status, created_at desc);
create index if not exists layer4_review_items_evidence_idx on pipeline.layer4_review_items (evidence_id) where evidence_id is not null;
create index if not exists layer4_review_items_entity_field_iq_idx on pipeline.layer4_review_items (entity_id, field_code, status);
create index if not exists evidence_artifacts_source_url_pattern_idx on pipeline.evidence_artifacts (lower(source_url) text_pattern_ops);
create index if not exists evidence_entity_idx on pipeline.evidence_artifacts (entity_id, captured_at desc);
create index if not exists courses_provider_pub_idx on catalogue.courses (provider_id, lifecycle_status);  -- live: (provider_id, publication_status); the stub has no publication_status
create index if not exists enrichment_flags_provider_idx on pipeline.enrichment_flags (provider_id) where state = 'raised';
create index if not exists enrichment_flags_open_idx on pipeline.enrichment_flags (reason_code) where state = 'raised';
create index if not exists course_links_course_idx on catalogue.course_links (course_id);
create index if not exists scholarship_ai_reviews_pending_idx on pipeline.scholarship_ai_reviews (status, created_at);
create index if not exists provider_onboarding_status_idx on pipeline.provider_onboarding (status, created_at);
create index if not exists data_flags_open_idx on pipeline.data_flags (flag_code, created_at) where status = 'open';
