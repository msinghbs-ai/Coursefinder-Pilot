create or replace function security.admin_layer_status_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','catalogue','scholarship','auth'
as $$
declare v_rank integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 return jsonb_build_object(
  'layer1',jsonb_build_object(
    'active_sources',(select count(*) from pipeline.sources where status='active' and coalesce(metadata->>'layer','')='1'),
    'running_jobs',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='running'),
    'failed_24h',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='failed' and created_at>now()-interval '24 hours'),
    'latest_activity',(select max(created_at) from pipeline.jobs where job_type='regulatory_sync')
  ),
  'layer2',jsonb_build_object(
    'active_batches',(select count(*) from pipeline.layer2_run_batches where status in('queued','running','partial')),
    'scheduled_wave_requests',(select count(*) from pipeline.layer2_scope_wave_requests where status in('scheduled','running','wave1_dispatched')),
    'wave_pending_courses',(select count(*) from pipeline.layer2_scope_wave_items where status='pending'),
    'processed_24h',(select count(*) from pipeline.layer2_run_items where completed_at>now()-interval '24 hours'),
    'evidence_24h',(select count(*) from pipeline.evidence_artifacts where coalesce(metadata->>'layer','') like '2%' and captured_at>now()-interval '24 hours')
  ),
  'layer3',jsonb_build_object(
    'qualified_profiles',(select count(*) from pipeline.layer3_model_profiles where enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)),
    'pending_evidence_candidates',(select count(*) from security.layer3_evidence_candidates_read(200)),
    'interpretations_24h',(select count(*) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'calls_24h',(select coalesce(sum(external_call_count),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'tokens_24h',(select coalesce(sum(input_tokens+output_tokens),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'recorded_cost_24h',(select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours')
  ),
  'layer4',jsonb_build_object(
    'pending_reviews',(select count(*) from pipeline.layer4_review_items where status='pending'),
    'active_overrides',(select count(*) from (
      select distinct on(entity_type,entity_id,field_code) event_type
      from pipeline.layer4_override_decisions order by entity_type,entity_id,field_code,created_at desc,id desc
    ) x where event_type<>'revert'),
    'publication_decisions',(select count(*) from pipeline.layer4_publication_decisions)
  ),
  'scholarships',jsonb_build_object(
    'scholarships',(select count(*) from scholarship.scholarships),
    'course_mappings',(select count(*) from scholarship.course_mappings where mapping_state='mapped'),
    'review_candidates',(select count(*) from scholarship.course_mapping_candidates where status='needs_review')
  )
 );
end $$;