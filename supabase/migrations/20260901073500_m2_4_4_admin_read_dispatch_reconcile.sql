-- CF-CHG-20260830-048
-- M2.4.4: reconcile public.admin_read after A27 paging addition.
-- Restores A10/A12 dispatch branches while retaining the new bounded Layer 2 profile page.

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path='pg_catalog','public','security'
as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation='layer2_profiles'
    and (p_args ? 'limit' or p_args ? 'offset' or p_args ? 'query' or p_args ? 'country' or p_args ? 'method' or p_args ? 'health')
 then return security.admin_layer2_profiles_page(p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then
   v_result:=security.admin_pipeline_ops_read(p_operation,p_args);
   return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);
 end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return security.admin_provider_detail(v_id)
     || jsonb_build_object('contextual_insights',security.admin_contextual_insights('provider',v_id));
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
     || jsonb_build_object('contextual_insights',security.admin_contextual_insights('course',v_id));
 end if;

 if p_operation='scholarship_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));
 end if;

 return v_result;
end $$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
