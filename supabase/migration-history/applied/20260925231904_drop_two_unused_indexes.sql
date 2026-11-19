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
