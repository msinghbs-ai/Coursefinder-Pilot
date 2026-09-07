-- CF-239 targeted recovery follow-up
-- Fix the exact targeted UAT failures without changing governed budgets or data semantics.

-- public.admin_read is SECURITY INVOKER, so private security helpers it calls must
-- remain executable by authenticated callers while retaining their own auth/rank checks.
grant execute on function security.admin_evidence_page_default_fast(jsonb) to authenticated, service_role;
revoke execute on function security.admin_evidence_page_default_fast(jsonb) from public, anon;

-- Narrow indexes support existing Layer 2 overview projections without scanning wide rows.
create index if not exists evidence_artifacts_layer2_overview_idx
  on pipeline.evidence_artifacts (review_state, retention_class, captured_at desc)
  where (metadata->>'layer')='2';

create index if not exists courses_provider_with_url_idx
  on catalogue.courses (provider_id, id)
  where course_url is not null and course_url <> '';

create or replace function security.admin_layer2_ops_overview_fast()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, catalogue, ref, public, auth
set jit = off
as $function$
declare
  v_rank integer;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 4 then
    raise exception 'pipeline_operator role required' using errcode='42501';
  end if;

  with item_stats as materialized (
    select
      count(*) filter(where status='layer3_required') layer3_candidates,
      count(*) filter(where status='blocked') blocked_items,
      count(*) filter(where status='queued') queued,
      count(*) filter(where status in ('discovering','acquiring','extracting')) processing,
      count(*) filter(where status='resolved_l2') enriched,
      count(*) filter(where status='cancelled') deferred,
      coalesce(sum(fields_targeted),0) fields_targeted,
      coalesce(sum(fields_resolved),0) fields_resolved
    from pipeline.layer2_run_items
  ), attempt_stats as materialized (
    select
      acquisition_provider_id,
      count(*) attempts,
      count(*) filter(where status in ('completed','success','succeeded')) successes,
      count(*) filter(where status in ('failed','error','blocked')) failures,
      count(*) filter(where response_http_status=429) http_429,
      round(avg(extract(epoch from (completed_at-started_at))*1000)
        filter(where completed_at is not null and started_at is not null)) avg_response_ms,
      max(completed_at) filter(where status in ('completed','success','succeeded')) last_success_at
    from pipeline.layer2_provider_attempts
    group by acquisition_provider_id
  ), eligible_providers as materialized (
    select distinct s.provider_id
    from pipeline.layer2_source_profiles p
    join pipeline.sources s on s.id=p.source_id
    where p.domain='course_facts' and p.enabled and not p.paused and s.provider_id is not null
  ), selected_courses as materialized (
    select distinct course_id
    from pipeline.layer2_course_discovery_candidates
    where selected and nullif(discovered_url,'') is not null and course_id is not null
  )
  select jsonb_build_object(
    'health',jsonb_build_object(
      'enabled_profiles',(select count(*) from pipeline.layer2_source_profiles where enabled and not paused and domain in ('course_facts','scholarship')),
      'active_runs',(select count(*) from pipeline.layer2_run_batches where status in ('queued','running')),
      'stuck_runs',(select count(*) from pipeline.layer2_run_batches b join pipeline.layer2_execution_policies ep on ep.profile_id=b.profile_id where b.status='running' and coalesce(b.heartbeat_at,b.updated_at,b.started_at,b.created_at)<now()-make_interval(mins=>coalesce(ep.stale_after_minutes,30))),
      'layer3_candidates',(select layer3_candidates from item_stats),
      'blocked_items',(select blocked_items from item_stats)
    ),
    'sources','[]'::jsonb,
    'providers',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',ap.id,'provider_key',ap.provider_key,'display_name',ap.display_name,'enabled',ap.enabled,
        'credential_configured',ap.vault_secret_id is not null,'priority',ap.priority,
        'rate_limit_per_minute',ap.rate_limit_per_minute,'concurrency',ap.concurrency,
        'last_tested_at',ap.last_tested_at,'last_test_status',ap.last_test_status,
        'billing_config',security.layer2_provider_sanitise_json(ap.billing_config),
        'attempts',coalesce(st.attempts,0),'successes',coalesce(st.successes,0),
        'failures',coalesce(st.failures,0),'http_429',coalesce(st.http_429,0),
        'avg_response_ms',st.avg_response_ms,'last_success_at',st.last_success_at,
        'recent_failure_streak',(select count(*) from (select a.status from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id order by a.created_at desc limit 10) z where z.status in ('failed','error','blocked'))
      ) order by ap.priority,ap.display_name),'[]'::jsonb)
      from pipeline.layer2_acquisition_providers ap
      left join attempt_stats st on st.acquisition_provider_id=ap.id
      where ap.enabled=true
    ),
    'recent_runs',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',b.id,'profile_id',b.profile_id,'trigger_type',b.trigger_type,'status',b.status,
        'target_count',b.target_count,'processed_count',b.processed_count,
        'resolved_l2_count',b.resolved_l2_count,'escalated_l3_count',b.escalated_l3_count,
        'blocked_count',b.blocked_count,'vendor_units',b.vendor_units,'vendor_cost_usd',b.vendor_cost_usd,
        'created_at',b.created_at,'started_at',b.started_at,'completed_at',b.completed_at,
        'heartbeat_at',b.heartbeat_at,'updated_at',b.updated_at,
        'runtime_seconds',case when b.started_at is null then null else round(extract(epoch from (coalesce(b.completed_at,now())-b.started_at))) end,
        'progress_percent',case when b.target_count>0 then round((100.0*b.processed_count/b.target_count)::numeric,1) else 0 end
      ) order by b.created_at desc),'[]'::jsonb)
      from (select * from pipeline.layer2_run_batches order by created_at desc limit 20)b
    ),
    'outcomes',(
      select jsonb_build_object(
        'queued',queued,'processing',processing,'enriched',enriched,'unresolved',layer3_candidates,
        'failed',blocked_items,'deferred',deferred,'fields_targeted',fields_targeted,'fields_resolved',fields_resolved
      ) from item_stats
    ),
    'demo_firecrawl_attempt',(
      select to_jsonb(x) from (
        select a.id,a.job_id,ap.provider_key,ap.display_name provider_name,a.attempt_no,a.status,
               a.request_url,a.response_http_status,a.response_mime_type,
               coalesce(a.html_evidence_id,a.raw_evidence_id,a.screenshot_evidence_id) evidence_id,
               a.started_at,a.completed_at,p.profile_key
        from pipeline.layer2_provider_attempts a
        join pipeline.layer2_acquisition_providers ap on ap.id=a.acquisition_provider_id
        join pipeline.layer2_source_profile_versions pv on pv.id=a.profile_version_id
        join pipeline.layer2_source_profiles p on p.id=pv.profile_id
        where ap.provider_key='firecrawl'
          and a.status in ('completed','success','succeeded')
          and p.domain='course_facts' and p.enabled and not p.paused
          and exists(select 1 from pipeline.refresh_policies rp where rp.source_profile_id=p.id and rp.layer=2 and rp.enabled)
          and coalesce(a.html_evidence_id,a.raw_evidence_id,a.screenshot_evidence_id) is not null
        order by a.completed_at desc nulls last limit 1
      ) x
    ),
    'recent_provider_attempts',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.completed_at desc nulls last),'[]'::jsonb)
      from (
        select a.id,a.job_id,ap.provider_key,ap.display_name provider_name,a.attempt_no,a.status,
               a.request_url,a.response_http_status,a.response_mime_type,a.raw_evidence_id,a.html_evidence_id,
               a.screenshot_evidence_id,coalesce(a.html_evidence_id,a.raw_evidence_id,a.screenshot_evidence_id) evidence_id,
               a.started_at,a.completed_at
        from pipeline.layer2_provider_attempts a
        join pipeline.layer2_acquisition_providers ap on ap.id=a.acquisition_provider_id
        order by a.completed_at desc nulls last,a.created_at desc limit 5
      ) x
    ),
    'evidence_summary',(
      select jsonb_build_object(
        'count',count(*),'unreviewed',count(*) filter(where review_state='unreviewed'),
        'retained_until_365',count(*) filter(where retention_class='standard_365'),
        'held',count(*) filter(where retention_class='hold'),'latest',max(captured_at)
      )
      from pipeline.evidence_artifacts
      where (metadata->>'layer')='2'
    ),
    'scope_summary',jsonb_build_object(
      'authorised_country_codes',jsonb_build_array('AU'),
      'nz_layer2_course_status','DEFERRED — source qualification/onboarding required',
      'course_catalogue_total',(
        select count(*) from catalogue.courses cc
        join catalogue.providers cp2 on cp2.id=cc.provider_id
        where cp2.canonical_name in ('Federation University Australia','RMIT University (RMIT)','The University of Queensland')
      ),
      'course_queueable_total',(
        select count(*) from (
          select cc.id
          from catalogue.courses cc
          join eligible_providers ep on ep.provider_id=cc.provider_id
          where cc.course_url is not null and cc.course_url <> ''
          union
          select cc.id
          from selected_courses sc
          join catalogue.courses cc on cc.id=sc.course_id
          join eligible_providers ep on ep.provider_id=cc.provider_id
        ) q
      )
    )
  ) into v_result;

  return v_result;
end $function$;

revoke all on function security.admin_layer2_ops_overview_fast() from public, anon;
grant execute on function security.admin_layer2_ops_overview_fast() to authenticated, service_role;

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
 if p_operation='layer2_ops_overview' then return security.admin_layer2_ops_overview_fast(); end if;
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
