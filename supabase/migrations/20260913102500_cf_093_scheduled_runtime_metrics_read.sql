-- CF-CHG-20260910-093
-- Read-only Scheduled Tasks runtime metrics contract.
-- Rank-4 browser access remains through public.admin_read; no raw payload, URL, secret or private Evidence content is returned.

begin;

create or replace function security.admin_jobs_runtime_read_v1(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with recent as (
    select j.*,
      case when coalesce(j.result->>'processed','') ~ '^\d+$' then (j.result->>'processed')::integer end processed_count,
      case when coalesce(j.result->>'selected','') ~ '^\d+$' then (j.result->>'selected')::integer end selected_count,
      case when coalesce(j.result->>'accepted','') ~ '^\d+$' then (j.result->>'accepted')::integer
           when coalesce(j.result->>'applied','') ~ '^\d+$' then (j.result->>'applied')::integer end accepted_count,
      case when coalesce(j.result->>'failed','') ~ '^\d+$' then (j.result->>'failed')::integer end failed_count,
      case when coalesce(j.result->>'retry_exhausted_count','') ~ '^\d+$' then (j.result->>'retry_exhausted_count')::integer
           when coalesce(j.payload->>'retry_exhausted_count','') ~ '^\d+$' then (j.payload->>'retry_exhausted_count')::integer end retry_exhausted_count
    from pipeline.jobs j
    order by j.created_at desc
    limit v_limit
  ), evidence_counts as (
    select e.job_id,
      count(*)::integer evidence_count,
      count(*) filter(where e.review_state in ('verified','verified_source_reference'))::integer verified_evidence_count
    from pipeline.evidence_artifacts e
    where e.job_id in (select id from recent)
    group by e.job_id
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',j.id,
    'job_type',j.job_type,
    'domain',j.domain,
    'status',j.status,
    'created_at',j.created_at,
    'started_at',j.started_at,
    'completed_at',j.completed_at,
    'source_profile_version_id',j.source_profile_version_id,
    'profile_id',p.id,
    'profile_key',p.profile_key,
    'processed_count',j.processed_count,
    'selected_count',j.selected_count,
    'accepted_count',j.accepted_count,
    'failed_count',j.failed_count,
    'retry_exhausted_count',j.retry_exhausted_count,
    'evidence_count',coalesce(ec.evidence_count,0),
    'verified_evidence_count',coalesce(ec.verified_evidence_count,0),
    'throughput_records_per_min',case when j.processed_count is not null and j.started_at is not null and j.completed_at>j.started_at then round((j.processed_count::numeric/nullif(extract(epoch from (j.completed_at-j.started_at)),0))*60,2) end,
    'dedupe_replay',case when j.result ? 'idempotent_replay' then (j.result->>'idempotent_replay')::boolean end,
    'failure_class',case
      when j.status<>'failed' then nullif(j.result->>'completion_class','')
      when coalesce(j.error_text,'') ilike '%401%' then 'authentication_401'
      when coalesce(j.error_text,'') ilike '%credential%' then 'credential_unavailable'
      when coalesce(j.error_text,'') ilike '%provider%' and coalesce(j.error_text,'') ilike '%exhaust%' then 'provider_exhausted'
      when coalesce(j.error_text,'') ilike '%budget%' then 'acquisition_budget_exhausted'
      when coalesce(j.error_text,'') ilike '%timeout%' then 'timeout'
      else 'failed'
    end
  )) order by j.created_at desc),'[]'::jsonb)
  into v_result
  from recent j
  left join pipeline.layer2_source_profile_versions pv on pv.id=j.source_profile_version_id
  left join pipeline.layer2_source_profiles p on p.id=pv.profile_id
  left join evidence_counts ec on ec.job_id=j.id;

  return v_result;
end
$function$;

revoke all on function security.admin_jobs_runtime_read_v1(jsonb) from public,anon,authenticated;
grant execute on function security.admin_jobs_runtime_read_v1(jsonb) to authenticated;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','security'
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
 if p_operation='evidence_page' then return security.admin_evidence_page(p_args); end if;
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
 if p_operation='jobs_runtime' then return security.admin_jobs_runtime_read_v1(p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
 if p_operation='layer2_ops_overview' then return security.admin_layer2_ops_read('layer2_ops_overview',p_args); end if;
 if p_operation='layer2_ops_run_detail' then return security.admin_layer2_ops_read(p_operation,p_args); end if;
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

commit;
