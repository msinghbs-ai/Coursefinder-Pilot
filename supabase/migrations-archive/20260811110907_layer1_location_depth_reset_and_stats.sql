alter table catalogue.campuses drop constraint if exists campuses_evidence_id_fkey;
alter table catalogue.campuses add constraint campuses_evidence_id_fkey foreign key (evidence_id) references pipeline.evidence_artifacts(id) on delete set null;

create or replace function public.svc_layer1_depth_stats()
returns jsonb language sql security definer
set search_path=public,catalogue,pipeline,search
as $$
select jsonb_build_object(
  'providers',(select count(*) from catalogue.providers),
  'courses',(select count(*) from catalogue.courses),
  'campuses',(select count(*) from catalogue.campuses),
  'course_campus_links',(select count(*) from catalogue.course_campuses),
  'provider_registrations',(select count(*) from catalogue.provider_registrations),
  'course_registrations',(select count(*) from catalogue.course_registrations),
  'search_documents',(select count(*) from search.course_documents),
  'evidence_metadata',(select count(*) from pipeline.evidence_artifacts)
) $$;
revoke all on function public.svc_layer1_depth_stats() from public,anon,authenticated;
grant execute on function public.svc_layer1_depth_stats() to service_role;

create or replace function public.svc_layer1_reset_database()
returns jsonb language plpgsql security definer
set search_path=public,catalogue,pim,ref,pipeline,workflow,scholarship,search,publishing,integration
as $$
declare
 v_deleted_registry bigint:=0; v_deleted_jobs bigint:=0; v_deleted_evidence bigint:=0; v_deleted_reviews bigint:=0; v_search_generation bigint:=0;
begin
 if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
 delete from workflow.review_actions where id is not null;
 delete from workflow.review_queue where id is not null; get diagnostics v_deleted_reviews=row_count;
 delete from workflow.suggestions where id is not null;
 delete from workflow.import_errors where id is not null;
 delete from workflow.import_rows where id is not null;
 delete from workflow.import_jobs where id is not null;
 delete from workflow.export_jobs where id is not null;
 delete from workflow.reconciliation_checks where id is not null;
 delete from workflow.migration_entity_map where id is not null;
 delete from workflow.migration_runs where id is not null;
 delete from workflow.handover_events where id is not null;
 delete from search.embedding_jobs where id is not null;
 delete from search.course_embeddings where course_id is not null;
 delete from search.course_documents where course_id is not null;
 delete from search.query_embedding_cache where cache_key is not null;
 update search.projection_state set generation=0,row_count=0,rebuilt_at=now() where projection_code='courses';
 delete from publishing.entity_states where entity_id is not null;
 delete from scholarship.coverage where id is not null;
 delete from scholarship.criteria where id is not null;
 delete from scholarship.scopes where id is not null;
 delete from scholarship.award_tiers where id is not null;
 delete from scholarship.scholarships where id is not null;
 delete from integration.extraction_profiles where provider_id is not null;
 delete from pipeline.acquisition_policies where provider_id is not null;
 update pipeline.sources set provider_id=null where provider_id is not null;
 delete from pim.attribute_values where id is not null;
 delete from pim.entity_categories where entity_id is not null;
 delete from pim.entity_registry where id is not null; get diagnostics v_deleted_registry=row_count;
 delete from pipeline.claims where id is not null;
 delete from pipeline.evidence_artifacts where id is not null; get diagnostics v_deleted_evidence=row_count;
 delete from pipeline.jobs where id is not null; get diagnostics v_deleted_jobs=row_count;
 update pipeline.sources set last_checked_at=null,last_success_at=null,last_failure_at=null,last_error=null,
   metadata=coalesce(metadata,'{}'::jsonb)-'worker_version'-'latest_job_id'-'institution_hash'-'course_hash'-'location_hash'-'course_location_hash'-'parsed_records'-'parsed_locations'-'parsed_course_locations'-'resource_updated'-'last_run_mode'-'last_run_records',updated_at=now()
 where id is not null;
 perform search.rebuild_course_documents();
 select generation into v_search_generation from search.projection_state where projection_code='courses';
 return jsonb_build_object('status','reset','baseline','layer1_execution_seed','providers',(select count(*) from catalogue.providers),'courses',(select count(*) from catalogue.courses),'campuses',(select count(*) from catalogue.campuses),'course_campus_links',(select count(*) from catalogue.course_campuses),'scholarships',(select count(*) from scholarship.scholarships),'search_documents',(select count(*) from search.course_documents),'search_generation',coalesce(v_search_generation,0),'pipeline_jobs',(select count(*) from pipeline.jobs),'evidence_metadata',(select count(*) from pipeline.evidence_artifacts),'review_queue',(select count(*) from workflow.review_queue),'deleted_entity_registry',v_deleted_registry,'deleted_jobs',v_deleted_jobs,'deleted_evidence_metadata',v_deleted_evidence,'deleted_reviews',v_deleted_reviews);
end $$;
