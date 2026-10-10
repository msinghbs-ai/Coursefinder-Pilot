-- CF-247 v2.15.226: slim provider read (Platform Admin, 9 Oct 2026, multiple choice: "Slim the provider read").
-- The provider panel (v2.15.225) shows pills, fact cards, values and rankings. provider_detail returned about 370 KB per
-- open, mostly lists the panel no longer shows: scholarship context (~243 KB), related insights (~56 KB), the course list
-- twice, evidence, sources and history. provider_detail now returns the provider record without those lists and without
-- the scholarship, ranking and logo context (rankings and logos load through their own reads). Related insights move to a
-- new operation, provider_insights, which the panel calls only when "More about this provider" is opened.
-- Only these two admin_read lines change; the live definition is md5-checked first and after. Nothing is dropped.

do $guard$
begin
  if md5(replace(pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure), E'\r', '')) <> '4949564e124715c4b0aabc1a39ccaafb'
    then raise exception 'live admin_read differs from the definition this change replaces'; end if;
end $guard$;

CREATE OR REPLACE FUNCTION public.admin_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'security'
AS $function$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='platform_health' then return security.admin_platform_health_v1(p_args); end if;
 if p_operation='live_activity' then return security.admin_live_activity_v1(); end if;
 if p_operation in ('course_coverage','course_coverage_courses','course_coverage_providers') then return security.admin_course_coverage_read(p_operation,p_args); end if;
 if p_operation='scholarship_ai' then return security.scholarship_ai_control_read_impl(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='layer3_queue_status' then return security.layer3_queue_status_read_v1(); end if;
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='layer_status_summary' then return security.admin_layer_status_summary(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation='evidence_page' then return security.admin_evidence_page(p_args); end if;
 if p_operation in ('evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;
 if p_operation in ('providers_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='ranking_imports' then return security.admin_ranking_imports_read(p_args); end if;
 if p_operation in ('ranking_summary','ranking_filters','ranking_observations') then return security.admin_ranking_read(p_operation,p_args); end if;
 if p_operation in ('ranking_filter_options','ranking_link_candidates','ranking_provider_search','provider_ranking_history') then return security.admin_ranking_links_read(p_operation,p_args); end if;
 if p_operation in ('provider_asset_summary','provider_asset_coverage','provider_asset_context') then return security.admin_provider_asset_read(p_operation,p_args); end if;
 if p_operation in ('provider_contacts_page','provider_contact_detail','provider_contact_imports','provider_contact_import_detail') then return security.admin_provider_contact_read(p_operation,p_args); end if;
 if p_operation='contextual_compare' then return security.admin_contextual_compare(p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation='layer2_dispatcher_tuning' then return security.admin_layer2_dispatcher_tuning_read_v1(p_args); end if;
 if p_operation='enrichment_operations' then return security.admin_enrichment_operations_read(p_args); end if;
 if p_operation='jobs_runtime' then return security.admin_jobs_runtime_read_v1(p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
 if p_operation='layer2_ops_overview' then return security.admin_layer2_ops_read('layer2_ops_overview',p_args); end if;
 if p_operation='layer2_ops_run_detail' then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_insights' then v_id:=nullif(p_args->>'id','')::uuid;return jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id));end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)-'courses'-'courses_page'-'evidence'-'evidence_page'-'sources'-'history';end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))||jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $function$;

do $post$
begin
  if md5(replace(pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure), E'\r', '')) <> 'c4e339a7a8fc58307804b796cdb5cfd6'
    then raise exception 'CF-247 provider read post-check: admin_read not as intended'; end if;
end $post$;
