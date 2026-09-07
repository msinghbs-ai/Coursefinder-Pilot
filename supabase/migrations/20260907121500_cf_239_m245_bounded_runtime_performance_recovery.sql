-- CF-239 / M2.4.5 recovery
-- Preserve governed semantics and budgets while removing avoidable full-set work
-- from the default Evidence page and supporting existing 24-hour status reads.

create index if not exists evidence_artifacts_captured_nulls_last_idx
  on pipeline.evidence_artifacts (captured_at desc nulls last, id);

create index if not exists evidence_artifacts_created_at_idx
  on pipeline.evidence_artifacts (created_at desc);

create index if not exists layer2_provider_attempts_created_at_idx
  on pipeline.layer2_provider_attempts (created_at desc);

create index if not exists layer3_interpretations_created_at_idx
  on pipeline.layer3_interpretations (created_at desc);

create index if not exists jobs_job_type_status_created_idx
  on pipeline.jobs (job_type, status, created_at desc);

create index if not exists scholarship_course_mappings_state_idx
  on scholarship.course_mappings (mapping_state);

create index if not exists scholarship_course_mapping_candidates_status_idx
  on scholarship.course_mapping_candidates (status);

create or replace function security.admin_evidence_page_default_fast(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, workflow, ref, auth, storage
as $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce((p_args->>'limit')::integer,50),1),200);
  v_offset integer:=greatest(coalesce((p_args->>'offset')::integer,0),0);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  -- This fast path is deliberately narrow. Any filtering, entity scoping,
  -- conflict/freshness/state filtering, verification range, alternate sort,
  -- or ascending direction delegates to the existing governed implementation.
  if nullif(trim(coalesce(p_args->>'query','')),'') is not null
     or nullif(trim(coalesce(p_args->>'country','')),'') is not null
     or nullif(trim(coalesce(p_args->>'source_id','')),'') is not null
     or nullif(trim(coalesce(p_args->>'layer','')),'') is not null
     or nullif(trim(coalesce(p_args->>'entity_type','')),'') is not null
     or nullif(trim(coalesce(p_args->>'entity_id','')),'') is not null
     or nullif(trim(coalesce(p_args->>'provider_id','')),'') is not null
     or nullif(trim(coalesce(p_args->>'job_id','')),'') is not null
     or nullif(trim(coalesce(p_args->>'evidence_type','')),'') is not null
     or nullif(trim(coalesce(p_args->>'mime','')),'') is not null
     or nullif(trim(coalesce(p_args->>'hash','')),'') is not null
     or nullif(trim(coalesce(p_args->>'job_status','')),'') is not null
     or nullif(trim(coalesce(p_args->>'status','')),'') is not null
     or nullif(trim(coalesce(p_args->>'extraction_state','')),'') is not null
     or nullif(trim(coalesce(p_args->>'freshness','')),'') is not null
     or nullif(trim(coalesce(p_args->>'verified_from','')),'') is not null
     or nullif(trim(coalesce(p_args->>'verified_to','')),'') is not null
     or p_args ? 'unresolved_conflicts'
     or lower(coalesce(p_args->>'sort','captured')) <> 'captured'
     or lower(coalesce(p_args->>'direction','desc')) <> 'desc'
  then
    return security.admin_evidence_page(p_args);
  end if;

  with page_ids as materialized (
    select e.id,e.captured_at
    from pipeline.evidence_artifacts e
    order by e.captured_at desc nulls last,e.id
    limit v_limit offset v_offset
  ),
  page_rows as materialized (
    select
      e.id,e.source_id,e.job_id,e.evidence_type,e.source_url,e.content_hash,e.mime_type,e.captured_at,
      e.valid_from,e.valid_to,e.supersedes_evidence_id,e.storage_path,e.metadata,
      s.label source_label,s.source_type,s.status source_status,s.url authority_url,
      co.iso_alpha2 country_code,j.job_type,j.domain job_domain,j.status job_status,
      security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type) layer_code,
      (lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true') explicit_stale,
      coalesce(ls.observation_count,0) observation_count,
      coalesce(ls.source_null_count,0) source_null_count,
      coalesce(ls.rejected_count,0) rejected_count,
      exists(
        select 1
        from workflow.review_queue rq
        join pipeline.claims cl on cl.id=rq.candidate_claim_id
        where cl.evidence_id=e.id
          and lower(coalesce(rq.status,'open')) not in ('closed','resolved','accepted','rejected')
      ) unresolved_conflict,
      exists(
        select 1 from pipeline.evidence_artifacts su
        where su.supersedes_evidence_id=e.id
      ) is_superseded,
      exists(
        select 1 from storage.objects o
        where o.bucket_id='evidence' and o.name=e.storage_path
      ) storage_available
    from page_ids p
    join pipeline.evidence_artifacts e on e.id=p.id
    left join pipeline.sources s on s.id=e.source_id
    left join ref.countries co on co.id=s.country_id
    left join pipeline.jobs j on j.id=e.job_id
    left join pipeline.evidence_lineage_stats ls on ls.evidence_id=e.id
  ),
  classified as (
    select r.*,
      case
        when r.unresolved_conflict then 'conflict'
        when r.rejected_count>0 then 'rejected'
        when r.observation_count=0 then 'missing_extraction'
        when r.source_null_count>0 then 'source_null'
        when r.explicit_stale then 'stale'
        when (r.valid_to is not null and r.valid_to<now()) or r.is_superseded then 'superseded'
        else 'current'
      end operational_status
    from page_rows r
  )
  select jsonb_build_object(
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',x.id,
        'country_code',x.country_code,
        'source_id',x.source_id,
        'source_label',x.source_label,
        'source_type',x.source_type,
        'source_status',x.source_status,
        'authority_url',x.authority_url,
        'layer',x.layer_code,
        'job_id',x.job_id,
        'job_type',x.job_type,
        'job_domain',x.job_domain,
        'job_status',x.job_status,
        'evidence_type',x.evidence_type,
        'mime_type',x.mime_type,
        'captured_at',x.captured_at,
        'valid_from',x.valid_from,
        'valid_to',x.valid_to,
        'content_hash',x.content_hash,
        'extraction_state',case when x.rejected_count>0 and x.observation_count=0 then 'rejected' when x.observation_count>0 then 'extracted' else 'missing_extraction' end,
        'observation_count',x.observation_count,
        'has_source_null',x.source_null_count>0,
        'status',x.operational_status,
        'freshness_state',case when x.explicit_stale then 'stale' when x.valid_to is not null and x.valid_to<now() then 'expired' when x.valid_to is not null then 'current' else 'no_policy' end,
        'unresolved_conflict',x.unresolved_conflict,
        'history_state',case when x.is_superseded then 'superseded' when x.supersedes_evidence_id is not null then 'superseding_snapshot' else 'current_or_unversioned' end,
        'storage_available',x.storage_available
      ) order by x.captured_at desc nulls last,x.id)
      from classified x
    ),'[]'::jsonb),
    'total',(select count(*) from pipeline.evidence_artifacts),
    'limit',v_limit,
    'offset',v_offset
  ) into v_result;

  return v_result;
end $function$;

revoke all on function security.admin_evidence_page_default_fast(jsonb) from public, anon, authenticated;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, security
as $function$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='platform_health' then return security.admin_platform_health_cf221(); end if;
 if p_operation='scholarship_ai' then return security.scholarship_ai_control_read_impl(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='scholarship_runtime' then return security.admin_scholarship_runtime_read(p_args); end if;
 if p_operation='scholarship_runtime_uat' then return security.admin_scholarship_runtime_uat(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='layer_status_summary' then return security.admin_layer_status_summary(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation='evidence_page' then return security.admin_evidence_page_default_fast(p_args); end if;
 if p_operation in ('evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;
 if p_operation in ('providers_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='ranking_imports' then return security.admin_ranking_imports_read(p_args); end if;
 if p_operation in ('ranking_summary','ranking_filters','ranking_observations') then return security.admin_ranking_read(p_operation,p_args); end if;
 if p_operation in ('provider_asset_summary','provider_asset_coverage','provider_asset_context') then return security.admin_provider_asset_read(p_operation,p_args); end if;
 if p_operation in ('provider_contacts_page','provider_contact_detail','provider_contact_imports','provider_contact_import_detail') then return security.admin_provider_contact_read(p_operation,p_args); end if;
 if p_operation='contextual_compare' then return security.admin_contextual_compare(p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation='layer2_profiles' and (p_args ? 'limit' or p_args ? 'offset' or p_args ? 'query' or p_args ? 'country' or p_args ? 'method' or p_args ? 'health') then return security.admin_layer2_profiles_page(p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id))||jsonb_build_object('ranking_context',security.admin_provider_rankings(v_id,10))||jsonb_build_object('provider_asset_context',security.admin_provider_asset_read('provider_asset_context',jsonb_build_object('provider_id',v_id)))||jsonb_build_object('scholarship_context',security.admin_provider_scholarships(v_id));end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))||jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $function$;
