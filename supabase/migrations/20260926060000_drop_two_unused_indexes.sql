-- Package 6, step 3: remove two large unused indexes (0 scans in 63 days of statistics).
-- Kept deliberately: course_documents_field_idx (production publication gate, Decision 138),
-- course_documents_provider_stable_key_idx (consumer provider filter), course_fees_campus_idx
-- (supports a foreign key). Small unused indexes are left alone: low benefit, and some serve
-- yearly jobs not seen in 63 days. Guarded (Decision 136).
-- ROLLBACK (recreate exactly):
--   CREATE INDEX evidence_artifacts_layer2_overview_idx ON pipeline.evidence_artifacts USING btree (review_state, retention_class, captured_at DESC) WHERE ((metadata ->> 'layer'::text) = '2'::text);
--   CREATE INDEX scholarship_source_records_payload_gin ON pipeline.scholarship_source_records USING gin (payload);
do $guard$
declare v_before jsonb; v_after jsonb; v_diff jsonb;
begin
  v_before := security.consumer_api_snapshot_v1();
  drop index if exists pipeline.evidence_artifacts_layer2_overview_idx;
  drop index if exists pipeline.scholarship_source_records_payload_gin;
  v_after := security.consumer_api_snapshot_v1();
  v_diff := security.consumer_api_compare_v1(v_before, v_after);
  if jsonb_array_length(v_diff) > 0 then raise exception 'Consumer API output changed; aborting: %', v_diff; end if;
end $guard$;
