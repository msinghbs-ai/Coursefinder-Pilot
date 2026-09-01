-- CF-CHG-20260901-058
-- Canonical M2.5 Platform Administration read surface.
-- Read-only platform maturity state; no Production enablement or destructive purge.

begin;

create or replace function security.admin_platform_maturity_read(
  p_operation text,
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','scholarship','ref','auth'
as $$
declare
  v_rank integer:=0;
  v_environment text:=lower(coalesce(nullif(btrim(p_args->>'environment'),''),'pilot'));
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,100),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_scope text:=lower(nullif(btrim(coalesce(p_args->>'environment_scope','')),''));
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if v_environment not in ('pilot','production') then raise exception 'invalid environment' using errcode='22023'; end if;

  if p_operation='platform_readiness' then
    return security.m2_5_readiness_snapshot_read();
  end if;

  if p_operation='platform_capacity' then
    return security.platform_capacity_snapshot_read(v_environment);
  end if;

  if p_operation='platform_environment_gates' then
    return jsonb_build_object(
      'environment',v_environment,
      'source_gates',coalesce((
        select jsonb_agg(jsonb_build_object(
          'environment',g.environment,
          'source_id',g.source_id,
          'source_label',coalesce(s.label,g.source_id::text),
          'capability',g.capability,
          'state',g.lifecycle_state,
          'enabled',g.enabled,
          'uat_ref',g.uat_ref,
          'reason',g.reason,
          'change_control_ref',g.change_control_ref,
          'updated_at',g.updated_at
        ) order by coalesce(s.label,''),g.capability)
        from pipeline.environment_source_gates g
        left join pipeline.sources s on s.id=g.source_id
        where g.environment=v_environment
      ),'[]'::jsonb),
      'scraper_gates',coalesce((
        select jsonb_agg(jsonb_build_object(
          'environment',g.environment,
          'provider_id',g.acquisition_provider_id,
          'provider_key',p.provider_key,
          'provider_name',p.display_name,
          'state',g.qualification_state,
          'enabled',g.enabled,
          'uat_ref',g.uat_ref,
          'reason',g.reason,
          'change_control_ref',g.change_control_ref,
          'updated_at',g.updated_at
        ) order by p.provider_key)
        from pipeline.layer2_provider_environment_gates g
        join pipeline.layer2_acquisition_providers p on p.id=g.acquisition_provider_id
        where g.environment=v_environment
      ),'[]'::jsonb),
      'ai_gates',coalesce((
        select jsonb_agg(jsonb_build_object(
          'environment',g.environment,
          'profile_id',g.profile_id,
          'profile_code',p.code,
          'model_identifier',p.model_identifier,
          'state',g.qualification_state,
          'enabled',g.enabled,
          'uat_ref',g.uat_ref,
          'benchmark_ref',g.benchmark_ref,
          'reason',g.reason,
          'change_control_ref',g.change_control_ref,
          'updated_at',g.updated_at
        ) order by p.code)
        from pipeline.layer3_profile_environment_gates g
        join pipeline.layer3_model_profiles p on p.id=g.profile_id
        where g.environment=v_environment
      ),'[]'::jsonb)
    );
  end if;

  if p_operation='platform_uat_catalogue' then
    with base as (
      select test_code,domain,environment_scope,gate_class,status,hard_gate,evidence_ref,
             description,change_control_ref,updated_at
      from pipeline.platform_uat_catalogue
      where v_scope is null
         or environment_scope=v_scope
         or environment_scope='both'
      order by
        case status when 'not_run' then 0 when 'designed' then 1 when 'accepted_baseline' then 2 when 'pass' then 3 else 4 end,
        hard_gate desc,domain,test_code
    ), numbered as (
      select b.*,count(*) over() total_count from base b
    ), page as (
      select * from numbered limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(jsonb_build_object(
        'test_code',test_code,'domain',domain,'environment_scope',environment_scope,
        'gate_class',gate_class,'status',status,'hard_gate',hard_gate,
        'evidence_ref',evidence_ref,'description',description,
        'change_control_ref',change_control_ref,'updated_at',updated_at
      ) order by
        case status when 'not_run' then 0 when 'designed' then 1 when 'accepted_baseline' then 2 when 'pass' then 3 else 4 end,
        hard_gate desc,domain,test_code),'[]'::jsonb),
      'total',coalesce(max(total_count),0),
      'limit',v_limit,'offset',v_offset,'environment_scope',v_scope
    ) into v_result from page;
    return coalesce(v_result,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',v_limit,'offset',v_offset,'environment_scope',v_scope));
  end if;

  if p_operation='platform_workloads' then
    return jsonb_build_object(
      'items',coalesce((
        select jsonb_agg(jsonb_build_object(
          'profile_key',profile_key,
          'workload_class',workload_class,
          'serving_traffic',serving_traffic,
          'background_ingestion',background_ingestion,
          'concurrent_admin_uat',concurrent_admin_uat,
          'rpc_detail_budget_ms',rpc_detail_budget_ms,
          'management_payload_budget_bytes',management_payload_budget_bytes,
          'filter_payload_budget_bytes',filter_payload_budget_bytes,
          'acquisition_on_read_allowed',acquisition_on_read_allowed,
          'sizing_role',sizing_role,
          'notes',notes,
          'updated_at',updated_at
        ) order by workload_class,profile_key)
        from pipeline.performance_workload_profiles
      ),'[]'::jsonb),
      'hard_budgets',jsonb_build_object(
        'rpc_detail_ms',3000,
        'management_payload_bytes',250000,
        'filter_payload_bytes',60000,
        'acquisition_on_read_allowed',false
      )
    );
  end if;

  if p_operation='platform_retention' then
    return jsonb_build_object(
      'dry_run',security.retention_dry_run_read(v_environment),
      'classes',coalesce((
        select jsonb_agg(jsonb_build_object(
          'class_key',class_key,
          'object_scope',object_scope,
          'immutable',immutable,
          'purge_allowed',purge_allowed,
          'default_retention_days',default_retention_days,
          'dry_run_required',dry_run_required,
          'bounded_delete_limit',bounded_delete_limit,
          'post_delete_integrity_required',post_delete_integrity_required,
          'notes',notes,
          'change_control_ref',change_control_ref,
          'updated_at',updated_at
        ) order by immutable desc,class_key)
        from pipeline.retention_class_policies
      ),'[]'::jsonb),
      'destructive_action_authorised',false
    );
  end if;

  if p_operation='platform_active_blocks' then
    with entities as (
      select 'provider'::text entity_type,p.id entity_id,coalesce(p.display_name,p.canonical_name) entity_name,
             p.id provider_id,coalesce(p.display_name,p.canonical_name) provider_name
      from catalogue.providers p
      union all
      select 'course',c.id,coalesce(c.display_title,c.canonical_title),p.id,coalesce(p.display_name,p.canonical_name)
      from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
      union all
      select 'campus',ca.id,ca.name,p.id,coalesce(p.display_name,p.canonical_name)
      from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id
      union all
      select 'scholarship',s.id,s.name,p.id,coalesce(p.display_name,p.canonical_name)
      from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id
    ), base as (
      select b.id,b.entity_type,b.entity_id,e.entity_name,e.provider_id,e.provider_name,
             b.block_scope,b.reason_code,b.comment,b.expires_at,b.review_at,b.created_at
      from security.layer4_active_blocks b
      left join entities e on e.entity_type=b.entity_type and e.entity_id=b.entity_id
      order by b.created_at desc,b.id desc
    ), numbered as (
      select x.*,count(*) over() total_count from base x
    ), page as (
      select * from numbered limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce(jsonb_agg(jsonb_build_object(
        'decision_id',id,
        'entity_type',entity_type,
        'entity_id',entity_id,
        'entity_name',coalesce(entity_name,entity_id::text),
        'provider_id',provider_id,
        'provider_name',provider_name,
        'scope',block_scope,
        'reason_code',reason_code,
        'comment',comment,
        'expires_at',expires_at,
        'review_at',review_at,
        'created_at',created_at
      ) order by created_at desc,id desc),'[]'::jsonb),
      'total',coalesce(max(total_count),0),
      'limit',v_limit,'offset',v_offset
    ) into v_result from page;
    return coalesce(v_result,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',v_limit,'offset',v_offset));
  end if;

  raise exception 'unsupported platform operation: %',p_operation using errcode='22023';
end
$$;

revoke all on function security.admin_platform_maturity_read(text,jsonb) from public,anon;
grant execute on function security.admin_platform_maturity_read(text,jsonb) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admin_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'security'
AS $function$
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
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
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
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
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
end $function$
;

commit;
