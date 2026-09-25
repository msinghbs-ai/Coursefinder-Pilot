-- Package 6, step 2: index foreign keys on busy tables (chosen by row count and scan volume).
-- Guarded: consumer API outputs are fingerprinted before and after in the same transaction;
-- any difference aborts the migration and rolls the indexes back (Decision 136).
do $guard$
declare v_before jsonb; v_after jsonb; v_diff jsonb;
begin
  v_before := security.consumer_api_snapshot_v1();

  create index if not exists layer2_source_profiles_source_id_idx on pipeline.layer2_source_profiles(source_id);
  create index if not exists layer2_run_items_job_id_idx on pipeline.layer2_run_items(job_id);
  create index if not exists layer2_run_items_selected_provider_id_idx on pipeline.layer2_run_items(selected_provider_id);
  create index if not exists layer2_profile_provider_routes_acq_provider_idx on pipeline.layer2_profile_provider_routes(acquisition_provider_id);
  create index if not exists layer2_run_batches_profile_version_id_idx on pipeline.layer2_run_batches(profile_version_id);
  create index if not exists layer2_scope_wave_items_course_id_idx on pipeline.layer2_scope_wave_items(course_id);
  create index if not exists layer2_scope_wave_items_batch_id_idx on pipeline.layer2_scope_wave_items(batch_id);
  create index if not exists layer2_scale_qualification_items_course_id_idx on pipeline.layer2_scale_qualification_items(course_id);
  create index if not exists layer3_work_items_evidence_id_idx on pipeline.layer3_work_items(evidence_id);
  create index if not exists course_mappings_course_id_idx on scholarship.course_mappings(course_id);
  create index if not exists course_mapping_candidates_course_id_idx on scholarship.course_mapping_candidates(course_id);
  create index if not exists course_mappings_source_scope_id_idx on scholarship.course_mappings(source_scope_id);

  v_after := security.consumer_api_snapshot_v1();
  v_diff := security.consumer_api_compare_v1(v_before, v_after);
  if jsonb_array_length(v_diff) > 0 then
    raise exception 'Consumer API output changed; aborting: %', v_diff;
  end if;
  insert into pipeline.consumer_api_baselines(label, snapshot) values ('after package6 step 2 (FK indexes)', v_after);
end $guard$;
