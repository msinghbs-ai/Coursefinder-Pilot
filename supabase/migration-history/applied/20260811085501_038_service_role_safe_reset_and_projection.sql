create or replace function search.rebuild_course_documents()
returns bigint
language plpgsql
security definer
set search_path to 'search','catalogue','scholarship','publishing','ref','extensions'
as $function$
declare v_generation bigint; v_count bigint;
begin
  update search.projection_state set generation=generation+1,rebuilt_at=now() where projection_code='courses' returning generation into v_generation;
  delete from search.course_documents where true;
  insert into search.course_documents(
    course_id,provider_id,country_id,study_level_id,primary_field_id,provider_name,course_title,collection_names,academic_option_names,description,search_text,search_tsv,
    has_fee,has_intake,has_english,has_scholarship,publication_status,completeness_score,catalogue_generation,content_hash,updated_at)
  select c.id,c.provider_id,p.country_id,c.study_level_id,c.primary_field_id,coalesce(p.display_name,p.canonical_name),c.canonical_title,
    coalesce((select array_agg(distinct cc.name order by cc.name) from catalogue.course_collection_memberships m join catalogue.course_collections cc on cc.id=m.collection_id where m.course_id=c.id),'{}'::text[]),
    coalesce((select array_agg(distinct ao.name order by ao.name) from catalogue.course_academic_options ao where ao.course_id=c.id and ao.status='active'),'{}'::text[]),
    c.description,
    concat_ws(' ',coalesce(p.display_name,p.canonical_name),c.canonical_title,coalesce(c.description,''),coalesce((select string_agg(distinct cc.name,' ') from catalogue.course_collection_memberships m join catalogue.course_collections cc on cc.id=m.collection_id where m.course_id=c.id),''),coalesce((select string_agg(distinct ao.name,' ') from catalogue.course_academic_options ao where ao.course_id=c.id and ao.status='active'),'')),
    to_tsvector('english',concat_ws(' ',coalesce(p.display_name,p.canonical_name),c.canonical_title,coalesce(c.description,''),coalesce((select string_agg(distinct cc.name,' ') from catalogue.course_collection_memberships m join catalogue.course_collections cc on cc.id=m.collection_id where m.course_id=c.id),''),coalesce((select string_agg(distinct ao.name,' ') from catalogue.course_academic_options ao where ao.course_id=c.id and ao.status='active'),''))),
    exists(select 1 from catalogue.course_fees f where f.course_id=c.id),
    exists(select 1 from catalogue.course_intakes i where i.course_id=c.id and i.status='active'),
    exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.id),
    exists(select 1 from scholarship.scopes ss join scholarship.scholarships s on s.id=ss.scholarship_id where s.publication_status in ('published','internal') and ((ss.scope_type='course' and ss.course_id=c.id) or (ss.scope_type='provider' and ss.provider_id=c.provider_id))),
    c.publication_status,
    (select max(es.completeness_score) from publishing.entity_states es where es.entity_id=c.id),
    v_generation,
    encode(extensions.digest(concat_ws('|',c.id::text,c.updated_at::text,coalesce(c.description,'')),'sha256'),'hex'),now()
  from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
  where c.lifecycle_status='active';
  get diagnostics v_count=row_count;
  update search.projection_state set row_count=v_count,rebuilt_at=now() where projection_code='courses';
  return v_count;
end
$function$;

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
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;

  delete from workflow.review_actions where true;
  delete from workflow.review_queue where true; get diagnostics v_deleted_reviews = row_count;
  delete from workflow.suggestions where true;
  delete from workflow.import_errors where true;
  delete from workflow.import_rows where true;
  delete from workflow.import_jobs where true;
  delete from workflow.export_jobs where true;
  delete from workflow.reconciliation_checks where true;
  delete from workflow.migration_entity_map where true;
  delete from workflow.migration_runs where true;
  delete from workflow.handover_events where true;

  delete from search.embedding_jobs where true;
  delete from search.course_embeddings where true;
  delete from search.course_documents where true;
  delete from search.query_embedding_cache where true;
  update search.projection_state set generation=0,row_count=0,rebuilt_at=now() where projection_code='courses';

  delete from publishing.entity_states where true;

  delete from scholarship.coverage where true;
  delete from scholarship.criteria where true;
  delete from scholarship.scopes where true;
  delete from scholarship.award_tiers where true;
  delete from scholarship.scholarships where true; get diagnostics v_deleted_scholarships = row_count;

  delete from pipeline.claims where true;
  delete from pipeline.evidence_artifacts where true; get diagnostics v_deleted_evidence = row_count;
  delete from pipeline.jobs where true; get diagnostics v_deleted_jobs = row_count;

  delete from integration.extraction_profiles where provider_id is not null;
  delete from pipeline.acquisition_policies where provider_id is not null;
  update pipeline.sources set provider_id=null where provider_id is not null;
  update pipeline.sources
     set last_checked_at=null,last_success_at=null,last_failure_at=null,last_error=null,
         metadata=coalesce(metadata,'{}'::jsonb)-'worker_version'-'latest_job_id'-'institution_hash'-'course_hash'-'parsed_records'-'resource_updated',
         updated_at=now();

  delete from pim.attribute_values where true;
  delete from pim.entity_categories where true;
  delete from pim.entity_registry where true; get diagnostics v_deleted_registry = row_count;

  perform search.rebuild_course_documents();
  select generation into v_search_generation from search.projection_state where projection_code='courses';

  return jsonb_build_object(
    'status','reset','baseline','layer1_execution_seed',
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
    'deleted_entity_registry',v_deleted_registry,'deleted_jobs',v_deleted_jobs,
    'deleted_evidence_metadata',v_deleted_evidence,'deleted_reviews',v_deleted_reviews,
    'deleted_scholarships',v_deleted_scholarships
  );
end;
$$;
revoke all on function public.svc_layer1_reset_au_uat() from public,anon,authenticated;
grant execute on function public.svc_layer1_reset_au_uat() to service_role;
