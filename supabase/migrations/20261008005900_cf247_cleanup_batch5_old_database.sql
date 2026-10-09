-- =====================================================================
-- CF-247 clean-up batch 5: retire the last old data-admission functions
-- Approved: Platform Admin, 9 Oct 2026 ("proceed with next step")
--
-- What: drops 31 functions of the old data-admission system: the
-- scheduler workflow RPCs and their browser bridges and helpers (the one-off
-- run builder), the Layer 2 operator/background/wave scope services and
-- batch dispatch, the scholarship runtime UAT path and its scope services,
-- and pipeline.svc_pilot_invoke_layer2. It also removes the dead old-system
-- operations from public.admin_read: 'scholarship_runtime',
-- 'scholarship_runtime_uat', 'layer2_profiles', 'layer2_profile_detail' and
-- 'layer2_provider_routes'. These now fall through to admin_read_impl and
-- return 'unsupported admin read operation'.
--
-- Why: the screens that used these were removed on 9 Oct 2026 (one-off run
-- builder in batch 2; scholarship runtime and Layer 2 profile screens on
-- 9 Oct). Confirmed read-only, live, 9 Oct 2026: no src/ or edge-function
-- caller; every dropped function's callers are inside this set (or
-- admin_read, via the branches removed here); no cron job (active or
-- inactive), trigger, view, policy, column default or pg_depend entry.
--
-- Kept: scheduler_workflow_profile_binding_snapshot_v1 (still called by
-- layer2_discovery_scope_dispatch_v2 and
-- layer2_discovery_context_scope_bound_v1),
-- scheduler_workflow_queueable_url_allowed_v1 (still called by
-- layer2_provider_attempt_start) and scheduler_workflow_https_host_v1 (called
-- by the latter). admin_read keeps 'jobs_runtime' (Refresh schedules ->
-- ScheduledRuntimeHealth) and 'layer2_acquisition_providers'.
--
-- Not touched: no table is dropped, no data or history is deleted.
--
-- Guard: md5(pg_get_functiondef), carriage returns removed, of every
-- function dropped or replaced is checked against the live values read on
-- 9 Oct 2026; any drift, or any cron job naming a dropped function, aborts
-- the migration. No CASCADE is used.
-- =====================================================================


do $guard$
declare
  v_expected constant jsonb := jsonb_build_object(
    'public.scheduler_workflow_preview_v1(text,text,text,uuid)', 'd9fc509202aa77d2ca328bb81ee73889',
    'security.scheduler_workflow_preview_v1_browser_bridge_guarded(text,text,text,uuid)', 'c8716eca64eb571e9d72179593e66ffe',
    'security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid)', '589fcba2e29b33420cd0ebf86d19abb5',
    'public.scheduler_workflow_run_now_v1(text,text,text,uuid,text,text)', '8edc26b39baf0d8383c493be9184e078',
    'security.scheduler_workflow_run_now_v1_browser_bridge(text,text,text,uuid,text,text)', '38585f72ca00b7effa661543f9636c3b',
    'public.scheduler_workflow_run_now_v2(uuid,text,text,text,uuid,text,text)', '55b2478de6b35d2c05c7d6cf28ed3a47',
    'security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text)', '6c16f409f4ca2aa74ad601a32f4519be',
    'public.scheduler_workflow_scope_options_v1(text,text,uuid,text,integer,integer)', 'db47ce6332858c6afd72c684548394d0',
    'security.scheduler_workflow_scope_options_v1_browser_bridge(text,text,uuid,text,integer,integer)', 'e2bc13953c0c84e70d465125b96f9783',
    'security.scheduler_workflow_scope_snapshot_v2(text,text,uuid)', '6ab3dd3d365b1436cc0e9969bfec7268',
    'security.scheduler_workflow_discovery_config_gap_count_v1(text,text,uuid)', '5bfa839f8c884f7a9069e642c2f69e25',
    'security.scheduler_workflow_execution_policy_gap_count_v1(text,text,uuid)', '1024e734869a2d2adeecd3adb85581b4',
    'security.scheduler_workflow_oversized_profile_count_v1(text,text,uuid)', 'b02d7eb07c70960e9b36603b7365e5a3',
    'security.scheduler_workflow_route_gap_count_v1(text,text,uuid)', 'ed12cab5e7565ba3864cf7dd4ae9b55a',
    'security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamp with time zone)', '00fb351fea4bad543b62b48ba1018384',
    'security.scheduler_workflow_async_binding_cancel_v1(uuid,uuid,text)', '1c6ec8836f5d12c9b3590fd45186b999',
    'security.scheduler_workflow_profile_ids_v1(text,text,uuid)', 'd965f49b862984712848d4dbe303d7dc',
    'security.scheduler_workflow_recent_terminal_negative_v1(uuid,uuid)', '1e409e830e1b96d55cc3b5568c12948f',
    'public.layer2_operator_scope_service(uuid,text,text,text,uuid)', 'b05f21508d89a70fc29d44411553ca0e',
    'security.scheduler_workflow_scope_state_v1(text,text,uuid)', '93f75ef22d46aa934613dc742398eb89',
    'public.layer2_scope_profile_batch_service(uuid,uuid,uuid[])', '1550d97f8da95e669959eb73c447eaed',
    'public.layer2_background_scope_service(uuid,text,text,text,uuid)', '2b3d6f983991f656170428ec483cd98d',
    'public.layer2_wave_scope_service(uuid,text,text,text,uuid,integer,boolean,text,uuid)', '0478612cf69c72fa35bd6e9f4cf994f3',
    'security.layer2_wave_dispatch_request(uuid)', 'b54023e712ecc51cf0e1a3ad7fb12ac0',
    'public.layer2_run_batch_dispatch(uuid)', '1ab033b1508e84c03f6601eddca00f32',
    'security.admin_scholarship_runtime_uat(text)', '375555f17720b51056e0b28c5bf99aba',
    'public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid)', '21cb07fb335f95ead4c167eae9ea02a9',
    'public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean)', '4d01082d942d782aed8a956ac3447dea',
    'scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer)', 'd66ed4c6e39cffa7ac79456b63b5c4e7',
    'security.scholarship_scope_scheduler_tick_impl(timestamp with time zone,integer,boolean)', 'b115c50803c28da46e475051073911a1',
    'pipeline.svc_pilot_invoke_layer2(text,jsonb)', '1af69422c35d8c29025eeb68cdc2e80b',
    'public.admin_read(text,jsonb)', 'f62921ae798f59788d7e0dd9de75167b'
  );
  v_sig text;
  v_oid regprocedure;
  v_md5 text;
  v_hits text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    v_oid := to_regprocedure(v_sig);
    if v_oid is null then
      raise exception 'CF-247 batch 5 guard: % does not exist', v_sig;
    end if;
    -- line endings ignored: the SQL editor may send Windows line endings
    v_md5 := md5(replace(pg_get_functiondef(v_oid), E'\r', ''));
    if v_md5 <> v_expected->>v_sig then
      raise exception 'CF-247 batch 5 guard: % definition drifted (live %, expected %)', v_sig, v_md5, v_expected->>v_sig;
    end if;
  end loop;

  select string_agg(j.jobid::text || ':' || coalesce(j.jobname,'?') || ' -> ' || n.x, '; ')
    into v_hits
    from cron.job j
    join (values
  ('admin_scholarship_runtime_uat'),
  ('layer2_background_scope_service'),
  ('layer2_operator_scope_service'),
  ('layer2_run_batch_dispatch'),
  ('layer2_scope_profile_batch_service'),
  ('layer2_wave_dispatch_request'),
  ('layer2_wave_scope_service'),
  ('reconcile_verified_detail_records'),
  ('scheduler_workflow_async_binding_cancel_v1'),
  ('scheduler_workflow_discovery_config_gap_count_v1'),
  ('scheduler_workflow_dispatch_dedupe_anchor_v1'),
  ('scheduler_workflow_execution_policy_gap_count_v1'),
  ('scheduler_workflow_oversized_profile_count_v1'),
  ('scheduler_workflow_preview_v1'),
  ('scheduler_workflow_preview_v1_browser_bridge'),
  ('scheduler_workflow_preview_v1_browser_bridge_guarded'),
  ('scheduler_workflow_profile_ids_v1'),
  ('scheduler_workflow_recent_terminal_negative_v1'),
  ('scheduler_workflow_route_gap_count_v1'),
  ('scheduler_workflow_run_now_v1'),
  ('scheduler_workflow_run_now_v1_browser_bridge'),
  ('scheduler_workflow_run_now_v2'),
  ('scheduler_workflow_run_now_v2_browser_bridge'),
  ('scheduler_workflow_scope_options_v1'),
  ('scheduler_workflow_scope_options_v1_browser_bridge'),
  ('scheduler_workflow_scope_snapshot_v2'),
  ('scheduler_workflow_scope_state_v1'),
  ('scholarship_international_detail_batch_service'),
  ('scholarship_scope_acquisition_service'),
  ('scholarship_scope_scheduler_tick_impl'),
  ('svc_pilot_invoke_layer2')
    ) n(x) on j.command ~ ('\m' || n.x || '\M');
  if v_hits is not null then
    raise exception 'CF-247 batch 5 guard: cron job(s) still reference retired functions: %', v_hits;
  end if;
end
$guard$;

-- Replace admin_read without the dead old-system operation branches.
-- Everything else is unchanged (SECURITY INVOKER, STABLE, search_path;
-- owner and grants are kept by CREATE OR REPLACE).
-- Live md5 before: f62921ae798f59788d7e0dd9de75167b
-- Expected md5 after: 4949564e124715c4b0aabc1a39ccaafb
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
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id))||jsonb_build_object('ranking_context',security.admin_provider_rankings(v_id,10))||jsonb_build_object('provider_asset_context',security.admin_provider_asset_read('provider_asset_context',jsonb_build_object('provider_id',v_id)))||jsonb_build_object('scholarship_context',security.admin_provider_scholarships(v_id));end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))||jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $function$;

do $post$
declare
  v_def text := replace(pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure), E'\r', '');
  v_name text;
begin
  if md5(v_def) <> '4949564e124715c4b0aabc1a39ccaafb' then
    raise exception 'CF-247 batch 5 post-check: admin_read definition not as intended (md5 %)', md5(v_def);
  end if;
  foreach v_name in array array['scholarship_runtime','scholarship_runtime_uat','layer2_profiles','layer2_profile_detail','layer2_provider_routes','admin_scholarship_runtime_uat','admin_scholarship_runtime_read','admin_layer2_profiles_page','admin_layer2_config_read'] loop
    if v_def ~ ('\m' || v_name || '\M') then
      raise exception 'CF-247 batch 5 post-check: admin_read still contains %', v_name;
    end if;
  end loop;
  foreach v_name in array array['platform_health','jobs_runtime','layer2_acquisition_providers','layer3_queue_status','course_detail','scholarship_ai'] loop
    if position('''' || v_name || '''' in v_def) = 0 then
      raise exception 'CF-247 batch 5 post-check: admin_read lost operation %', v_name;
    end if;
  end loop;
end
$post$;

-- Drops, callers before callees. No CASCADE.
drop function public.scheduler_workflow_preview_v1(text,text,text,uuid);
drop function security.scheduler_workflow_preview_v1_browser_bridge_guarded(text,text,text,uuid);
drop function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid);
drop function public.scheduler_workflow_run_now_v1(text,text,text,uuid,text,text);
drop function security.scheduler_workflow_run_now_v1_browser_bridge(text,text,text,uuid,text,text);
drop function public.scheduler_workflow_run_now_v2(uuid,text,text,text,uuid,text,text);
drop function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text);
drop function public.scheduler_workflow_scope_options_v1(text,text,uuid,text,integer,integer);
drop function security.scheduler_workflow_scope_options_v1_browser_bridge(text,text,uuid,text,integer,integer);
drop function security.scheduler_workflow_scope_snapshot_v2(text,text,uuid);
drop function security.scheduler_workflow_discovery_config_gap_count_v1(text,text,uuid);
drop function security.scheduler_workflow_execution_policy_gap_count_v1(text,text,uuid);
drop function security.scheduler_workflow_oversized_profile_count_v1(text,text,uuid);
drop function security.scheduler_workflow_route_gap_count_v1(text,text,uuid);
drop function security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamp with time zone);
drop function security.scheduler_workflow_async_binding_cancel_v1(uuid,uuid,text);
drop function security.scheduler_workflow_profile_ids_v1(text,text,uuid);
drop function security.scheduler_workflow_recent_terminal_negative_v1(uuid,uuid);
drop function public.layer2_operator_scope_service(uuid,text,text,text,uuid);
drop function security.scheduler_workflow_scope_state_v1(text,text,uuid);
drop function public.layer2_scope_profile_batch_service(uuid,uuid,uuid[]);
drop function public.layer2_background_scope_service(uuid,text,text,text,uuid);
drop function public.layer2_wave_scope_service(uuid,text,text,text,uuid,integer,boolean,text,uuid);
drop function security.layer2_wave_dispatch_request(uuid);
drop function public.layer2_run_batch_dispatch(uuid);
drop function security.admin_scholarship_runtime_uat(text);
drop function public.scholarship_scope_acquisition_service(uuid,text,text,text,uuid);
drop function public.scholarship_international_detail_batch_service(uuid,text,text,text,uuid,integer,boolean);
drop function scholarship.reconcile_verified_detail_records(uuid,text,text,uuid,integer);
drop function security.scholarship_scope_scheduler_tick_impl(timestamp with time zone,integer,boolean);
drop function pipeline.svc_pilot_invoke_layer2(text,jsonb);
