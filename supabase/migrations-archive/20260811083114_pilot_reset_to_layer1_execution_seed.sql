create or replace function public.svc_layer1_reset_au_uat()
returns jsonb
language plpgsql
security definer
set search_path = public, catalogue, pim, ref, pipeline, workflow, scholarship, search, publishing, integration
as $$
declare
  v_deleted_registry bigint := 0;
  v_deleted_jobs bigint := 0;
  v_deleted_evidence bigint := 0;
  v_deleted_reviews bigint := 0;
  v_deleted_scholarships bigint := 0;
  v_search_generation bigint := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  -- Remove operational/workflow data.
  delete from workflow.review_actions;
  delete from workflow.review_queue;
  get diagnostics v_deleted_reviews = row_count;
  delete from workflow.suggestions;
  delete from workflow.import_errors;
  delete from workflow.import_rows;
  delete from workflow.import_jobs;
  delete from workflow.export_jobs;
  delete from workflow.reconciliation_checks;
  delete from workflow.migration_entity_map;
  delete from workflow.migration_runs;
  delete from workflow.handover_events;

  -- Remove derived/search runtime data while preserving search configuration seed.
  delete from search.embedding_jobs;
  delete from search.course_embeddings;
  delete from search.course_documents;
  delete from search.query_embedding_cache;
  update search.projection_state
     set generation = 0, row_count = 0, rebuilt_at = now()
   where projection_code = 'courses';

  -- Remove publishing/runtime states.
  delete from publishing.entity_states;

  -- Remove scholarship business data.
  delete from scholarship.coverage;
  delete from scholarship.criteria;
  delete from scholarship.scopes;
  delete from scholarship.award_tiers;
  delete from scholarship.scholarships;
  get diagnostics v_deleted_scholarships = row_count;

  -- Remove Layer/runtime pipeline data but preserve source/configuration seed.
  delete from pipeline.claims;
  delete from pipeline.evidence_artifacts;
  get diagnostics v_deleted_evidence = row_count;
  delete from pipeline.jobs;
  get diagnostics v_deleted_jobs = row_count;

  -- Remove provider-scoped runtime configuration that cannot survive a clean catalogue reset.
  delete from integration.extraction_profiles where provider_id is not null;
  delete from pipeline.acquisition_policies where provider_id is not null;
  update pipeline.sources set provider_id = null where provider_id is not null;

  -- Clear source health/runtime metadata while preserving source discovery/configuration metadata.
  update pipeline.sources
     set last_checked_at = null,
         last_success_at = null,
         last_failure_at = null,
         last_error = null,
         metadata = coalesce(metadata, '{}'::jsonb)
                    - 'worker_version' - 'latest_job_id' - 'institution_hash'
                    - 'course_hash' - 'parsed_records' - 'resource_updated',
         updated_at = now();

  -- Remove all entity-bound PIM/catalogue business data. Catalogue rows cascade from registry.
  delete from pim.attribute_values;
  delete from pim.entity_categories;
  delete from pim.entity_registry;
  get diagnostics v_deleted_registry = row_count;

  -- Rebuild projection at the empty catalogue boundary so all UI statistics agree.
  perform search.rebuild_course_documents();
  select generation into v_search_generation from search.projection_state where projection_code='courses';

  return jsonb_build_object(
    'status','reset',
    'baseline','layer1_execution_seed',
    'providers',(select count(*) from catalogue.providers),
    'courses',(select count(*) from catalogue.courses),
    'scholarships',(select count(*) from scholarship.scholarships),
    'search_documents',(select count(*) from search.course_documents),
    'search_generation',coalesce(v_search_generation,0),
    'pipeline_jobs',(select count(*) from pipeline.jobs),
    'evidence_metadata',(select count(*) from pipeline.evidence_artifacts),
    'review_queue',(select count(*) from workflow.review_queue),
    'cricos_course_registrations',(select count(*) from catalogue.course_registrations where lower(scheme)='cricos'),
    'cricos_provider_registrations',(select count(*) from catalogue.provider_registrations where lower(registration_scheme)='cricos'),
    'deleted_entity_registry',v_deleted_registry,
    'deleted_jobs',v_deleted_jobs,
    'deleted_evidence_metadata',v_deleted_evidence,
    'deleted_reviews',v_deleted_reviews,
    'deleted_scholarships',v_deleted_scholarships
  );
end;
$$;
revoke all on function public.svc_layer1_reset_au_uat() from public, anon, authenticated;
grant execute on function public.svc_layer1_reset_au_uat() to service_role;
