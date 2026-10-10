-- CF-CHG-20260830-048
-- M2.4.4 A27/A28: bounded Administration Layer 2 source-profile registry.
-- Preserve the historical unpaged layer2_profiles contract for legacy consumers.
-- Administration supplies limit/offset/filter args and is dispatched to this paged helper.

create or replace function security.admin_layer2_profiles_page(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','ref','catalogue','public'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),100);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_query text:=lower(nullif(trim(p_args->>'query'),''));
  v_country text:=nullif(upper(trim(p_args->>'country')),'');
  v_method text:=nullif(trim(p_args->>'method'),'');
  v_health text:=nullif(lower(trim(p_args->>'health')),'');
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with base as (
    select
      p.id profile_id,p.profile_key,s.label source_label,c.iso_alpha2 country_code,
      p.domain,p.acquisition_method,p.target_entity_type,p.enabled,p.paused,
      p.current_version_id,v.version_no current_version,v.validation_status,
      s.last_success_at,s.last_failure_at,s.last_error,
      p.last_inventory_at,p.last_inventory_count,s.provider_id affected_provider_id,
      cp.canonical_name affected_provider_name,
      case
        when not p.enabled then 'disabled'
        when p.paused then 'paused'
        when coalesce(v.validation_status,'invalid')<>'valid' then 'blocked'
        when s.last_failure_at is not null and (s.last_success_at is null or s.last_failure_at>s.last_success_at) then 'degraded'
        when p.freshness_sla_hours is not null and s.last_success_at is not null and s.last_success_at<now()-(p.freshness_sla_hours||' hours')::interval then 'stale'
        else 'healthy'
      end health,
      p.source_id
    from pipeline.layer2_source_profiles p
    join pipeline.sources s on s.id=p.source_id
    left join ref.countries c on c.id=s.country_id
    left join catalogue.providers cp on cp.id=s.provider_id
    left join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id
    where p.domain in ('course_facts','scholarship')
      and p.target_entity_type in ('course_fact','scholarship')
  ), filtered as (
    select *
    from base b
    where (v_query is null or lower(concat_ws(' ',b.profile_key,b.source_label,b.country_code,b.acquisition_method,b.domain,b.target_entity_type,b.affected_provider_name,b.last_error)) like '%'||v_query||'%')
      and (v_country is null or b.country_code=v_country)
      and (v_method is null or b.acquisition_method=v_method)
      and (v_health is null or b.health=v_health)
  ), page as (
    select *
    from filtered
    order by lower(source_label),profile_key
    limit v_limit offset v_offset
  ), page_rows as (
    select jsonb_build_object(
      'profile_id',p.profile_id,'profile_key',p.profile_key,'source_label',p.source_label,'country_code',p.country_code,
      'domain',p.domain,'acquisition_method',p.acquisition_method,'target_entity_type',p.target_entity_type,
      'enabled',p.enabled,'paused',p.paused,'current_version',p.current_version,'validation_status',p.validation_status,
      'last_success_at',p.last_success_at,'last_failure_at',p.last_failure_at,'last_error',p.last_error,
      'last_inventory_at',p.last_inventory_at,'last_inventory_count',p.last_inventory_count,
      'affected_provider_name',p.affected_provider_name,'health',p.health,
      'job_count',(select count(*) from pipeline.jobs j where j.source_id=p.source_id),
      'evidence_count',(select count(*) from pipeline.evidence_artifacts e where e.source_id=p.source_id)
    ) row_json
    from page p
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(row_json) from page_rows),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'limit',v_limit,
    'offset',v_offset,
    'has_more',v_offset+v_limit<(select count(*) from filtered),
    'summary',jsonb_build_object(
      'profiles',(select count(*) from base),
      'valid',(select count(*) from base where validation_status='valid'),
      'healthy',(select count(*) from base where health='healthy')
    ),
    'options',jsonb_build_object(
      'countries',(select coalesce(jsonb_agg(x.country_code order by x.country_code),'[]'::jsonb) from (select distinct country_code from base where country_code is not null)x),
      'methods',(select coalesce(jsonb_agg(x.acquisition_method order by x.acquisition_method),'[]'::jsonb) from (select distinct acquisition_method from base where acquisition_method is not null)x),
      'health',jsonb_build_array('healthy','degraded','stale','blocked','paused','disabled')
    )
  ) into v_result;

  return v_result;
end $$;

revoke all on function security.admin_layer2_profiles_page(jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer2_profiles_page(jsonb) to authenticated,service_role;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path='pg_catalog','public','security'
as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation='layer2_profiles' and (p_args ? 'limit' or p_args ? 'offset' or p_args ? 'query' or p_args ? 'country' or p_args ? 'method' or p_args ? 'health') then return security.admin_layer2_profiles_page(p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id);end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
