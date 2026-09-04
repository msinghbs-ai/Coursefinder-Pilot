create or replace function security.admin_scholarship_runtime_uat(p_country_code text default 'AU')
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','scholarship','catalogue','ref','auth' as $$
declare v_rank integer; v_country text:=upper(coalesce(nullif(p_country_code,''),'AU')); v_checks jsonb; v_pass integer; v_fail integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 with checks as (
  select * from (values
   ('settings_rls', (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='pipeline' and c.relname='scholarship_runtime_settings'), 'Runtime settings table is protected by RLS'),
   ('settings_browser_denied', not has_table_privilege('authenticated','pipeline.scholarship_runtime_settings','SELECT'), 'Browser roles cannot directly read private runtime settings'),
   ('international_only', coalesce((select (metadata->>'international_only')::boolean from pipeline.scholarship_runtime_settings where country_code=v_country),true), 'Automatic acquisition remains international-only'),
   ('publication_blocked', coalesce((select not coalesce((metadata->>'publication_authorised')::boolean,false) from pipeline.scholarship_runtime_settings where country_code=v_country),true), 'Runtime acquisition cannot publish Scholarships'),
   ('scope_service_country', to_regprocedure('public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid)') is not null, 'Country/University catalogue scope service exists'),
   ('detail_batch_service', to_regprocedure('public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)') is not null, 'International detail batching service exists'),
   ('provider_cross_reference', to_regprocedure('security.admin_provider_scholarships(uuid)') is not null, 'Provider detail Scholarship cross-reference exists'),
   ('course_cross_reference', to_regprocedure('security.admin_course_scholarships(uuid)') is not null, 'Course detail Scholarship cross-reference exists'),
   ('financial_fail_closed', not exists(select 1 from scholarship.course_financial_calculations where calculation_status='calculated' and (course_fee_id is null or scholarship_saving_amount is null or net_fee_amount is null)), 'Calculated net fees require a concrete fee row and amounts'),
   ('source_evidence_present', exists(select 1 from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and sr.evidence_id is not null), 'Scholarship source records retain Evidence'),
   ('catalogue_no_mass_publish', not exists(select 1 from pipeline.jobs j where j.domain='scholarship' and coalesce((j.payload->>'publication_authorised')::boolean,false)=true), 'Scholarship acquisition jobs have no publication authorisation')
  ) as x(code,passed,description)
 ), agg as (
   select coalesce(jsonb_agg(jsonb_build_object('code',code,'passed',passed,'description',description) order by code),'[]'::jsonb) items,
          count(*) filter(where passed)::int passed_count,count(*) filter(where not passed)::int failed_count from checks
 ) select items,passed_count,failed_count into v_checks,v_pass,v_fail from agg;
 return jsonb_build_object('country_code',v_country,'status',case when v_fail=0 then 'pass' else 'fail' end,'passed',v_pass,'failed',v_fail,'checks',v_checks,'tested_at',now());
end $$;
grant execute on function security.admin_scholarship_runtime_uat(text) to authenticated,service_role;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','public','security' as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='scholarship_runtime' then return security.admin_scholarship_runtime_read(p_args); end if;
 if p_operation='scholarship_runtime_uat' then return security.admin_scholarship_runtime_uat(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
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
end $$;