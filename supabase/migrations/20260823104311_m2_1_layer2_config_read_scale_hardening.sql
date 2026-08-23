-- Mirrors deployed 20260823104311 · CF-CHG-20260823-029
create or replace function security.admin_layer2_config_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','security','pipeline','ref','catalogue','public' as $$
declare v_rank integer:=0;v_id uuid;v_result jsonb;begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501';end if;
 select security.current_role_rank() into v_rank;if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501';end if;
 if p_operation='layer2_profiles' then
  with job_counts as (select source_id,count(*)::bigint job_count from pipeline.jobs where source_id is not null group by source_id),
  evidence_counts as (select source_id,count(*)::bigint evidence_count from pipeline.evidence_artifacts where source_id is not null group by source_id),
  version_counts as (select profile_id,count(*)::bigint version_count from pipeline.layer2_source_profile_versions group by profile_id),
  rows as (
   select jsonb_build_object(
    'profile_id',p.id,'profile_key',p.profile_key,'source_id',p.source_id,'source_label',s.label,'country_code',c.iso_alpha2,'source_type',s.source_type,'source_url',s.url,'trust_rank',s.trust_rank,
    'domain',p.domain,'acquisition_method',p.acquisition_method,'target_entity_type',p.target_entity_type,'authority_class',p.authority_class,'enabled',p.enabled,'paused',p.paused,'operational_owner',p.operational_owner,
    'freshness_sla_hours',p.freshness_sla_hours,'schedule_text',p.schedule_text,'current_version_id',p.current_version_id,'current_version',v.version_no,'validation_status',v.validation_status,'validation_result',v.validation_result,
    'change_control_ref',v.change_control_ref,'uat_ref',v.uat_ref,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,'last_inventory_hash',p.last_inventory_hash,
    'job_count',coalesce(jc.job_count,0),'evidence_count',coalesce(ec.evidence_count,0),'version_count',coalesce(vc.version_count,0),'affected_provider_id',s.provider_id,'affected_provider_name',cp.canonical_name,
    'health',case when not p.enabled then 'disabled' when p.paused then 'paused' when v.validation_status<>'valid' then 'blocked' when s.last_failure_at is not null and (s.last_success_at is null or s.last_failure_at>s.last_success_at) then 'degraded' when p.freshness_sla_hours is not null and s.last_success_at is not null and s.last_success_at<now()-(p.freshness_sla_hours||' hours')::interval then 'stale' else 'healthy' end) row_json
   from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id left join ref.countries c on c.id=s.country_id left join catalogue.providers cp on cp.id=s.provider_id left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id left join job_counts jc on jc.source_id=p.source_id left join evidence_counts ec on ec.source_id=p.source_id left join version_counts vc on vc.profile_id=p.id)
  select coalesce(jsonb_agg(row_json order by lower(row_json->>'source_label')),'[]'::jsonb) into v_result from rows;return v_result;
 end if;
 if p_operation='layer2_profile_detail' then
  v_id:=nullif(p_args->>'id','')::uuid;
  select jsonb_build_object(
   'profile',jsonb_build_object('id',p.id,'profile_key',p.profile_key,'source_id',p.source_id,'source_label',s.label,'country_code',c.iso_alpha2,'source_url',s.url,'trust_rank',s.trust_rank,'domain',p.domain,'acquisition_method',p.acquisition_method,'target_entity_type',p.target_entity_type,'authority_class',p.authority_class,'enabled',p.enabled,'paused',p.paused,'operational_owner',p.operational_owner,'freshness_sla_hours',p.freshness_sla_hours,'schedule_text',p.schedule_text,'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,'last_inventory_hash',p.last_inventory_hash,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,'affected_provider_id',s.provider_id,'affected_provider_name',cp.canonical_name),
   'current_version',case when v.id is null then null else jsonb_build_object('id',v.id,'version_no',v.version_no,'configuration',security.layer2_sanitise_config(v.configuration),'configuration_hash',v.configuration_hash,'validation_status',v.validation_status,'validation_result',v.validation_result,'change_control_ref',v.change_control_ref,'uat_ref',v.uat_ref,'created_at',v.created_at) end,
   'history',(select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'version_no',h.version_no,'configuration_hash',h.configuration_hash,'validation_status',h.validation_status,'validation_result',h.validation_result,'change_control_ref',h.change_control_ref,'uat_ref',h.uat_ref,'created_at',h.created_at,'configuration',security.layer2_sanitise_config(h.configuration)) order by h.version_no desc),'[]'::jsonb) from pipeline.layer2_source_profile_versions h where h.profile_id=p.id),
   'recent_jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',j.id,'status',j.status,'job_type',j.job_type,'created_at',j.created_at,'completed_at',j.completed_at,'source_profile_version_id',j.source_profile_version_id) order by j.created_at desc),'[]'::jsonb) from (select * from pipeline.jobs jj where jj.source_id=p.source_id order by jj.created_at desc limit 20) j),
   'recent_evidence',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'mime_type',e.mime_type,'captured_at',e.captured_at,'content_hash',e.content_hash,'source_profile_version_id',e.source_profile_version_id) order by e.captured_at desc),'[]'::jsonb) from (select * from pipeline.evidence_artifacts ee where ee.source_id=p.source_id order by ee.captured_at desc limit 20) e)
  ) into v_result from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id left join ref.countries c on c.id=s.country_id left join catalogue.providers cp on cp.id=s.provider_id left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.id=v_id;
  return coalesce(v_result,'{}'::jsonb);
 end if;
 raise exception 'unsupported layer2 read operation: %',p_operation using errcode='22023';
end $$;

-- Preserve the single M1 browser RPC boundary while adding Layer 2 reads.
create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path to 'pg_catalog','public','security' as $$
declare v_result jsonb;v_id uuid;begin
 if p_operation='dashboard' then return security.admin_dashboard_maturity();end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args);end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args);end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args);end if;
 if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args);end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args);end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args);end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args);end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args);end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args);end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args);end if;
 if p_operation='publication_overview' then return security.admin_publication_overview();end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id);end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $$;
