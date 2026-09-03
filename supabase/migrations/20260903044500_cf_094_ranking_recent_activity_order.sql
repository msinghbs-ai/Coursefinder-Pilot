create or replace function security.admin_ranking_imports_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','ranking','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  return (
    select jsonb_build_object(
      'total',(select count(*) from ranking.manual_imports),
      'limit',v_limit,'offset',v_offset,
      'items',coalesce((
        select jsonb_agg(to_jsonb(x) order by x.updated_at desc,x.uploaded_at desc)
        from (
          select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,
            mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,
            mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,
            mi.uploaded_at,mi.updated_at
          from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id
          order by mi.updated_at desc,mi.uploaded_at desc
          limit v_limit offset v_offset
        ) x
      ),'[]'::jsonb)
    )
  );
end
$$;

revoke all on function security.admin_ranking_imports_read(jsonb) from public, anon;
grant execute on function security.admin_ranking_imports_read(jsonb) to authenticated, service_role;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','security'
as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='layer_status_summary' then return security.admin_layer_status_summary(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
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
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then
   v_result:=security.admin_pipeline_ops_read(p_operation,p_args);
   return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);
 end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return security.admin_provider_detail(v_id)
     || jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id))
     || jsonb_build_object('ranking_context',security.admin_provider_rankings(v_id,10))
     || jsonb_build_object('provider_asset_context',security.admin_provider_asset_read('provider_asset_context',jsonb_build_object('provider_id',v_id)));
 end if;
 if p_operation='campus_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return security.admin_campus_detail(v_id);
 end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return v_result
     || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))
     || jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))
     || jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))
     || jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))
     || jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))
     || jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));
 end if;
 if p_operation='scholarship_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));
 end if;
 return v_result;
end
$$;
