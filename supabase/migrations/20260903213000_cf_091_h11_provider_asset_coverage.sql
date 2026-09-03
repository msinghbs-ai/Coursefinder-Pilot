begin;

create or replace function security.admin_provider_asset_read(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','catalogue','pipeline','ref','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_country text:=upper(nullif(btrim(p_args->>'country_code'),''));
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_state text:=nullif(btrim(p_args->>'state'),'');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='provider_asset_summary' then
    return (
      with base as (
        select p.id,c.iso_alpha2 country_code,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') discovered,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_backed,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate,
          exists(select 1 from catalogue.provider_assets pa where pa.provider_id=p.id and pa.is_primary and pa.status='approved' and pa.asset_type in ('logo','logo_dark','logo_light')) approved_primary
        from catalogue.providers p join ref.countries c on c.id=p.country_id
        where coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      )
      select jsonb_build_object(
        'scope_basis','active canonical Providers matching current filters; Provider type is not populated and this is not yet a university-only denominator',
        'country_code',v_country,'expected',count(*),'discovered',count(*) filter(where discovered),
        'acquired',count(*) filter(where evidence_backed or approved_primary),'approved',count(*) filter(where approved_primary),
        'blocked',count(*) filter(where accepted_candidate and not approved_primary),'missing',count(*) filter(where not discovered),
        'needs_review',count(*) filter(where discovered and not accepted_candidate and not approved_primary),
        'refresh_cadence','quarterly','authority','first_party_provider'
      ) from base
    );
  elsif p_operation='provider_asset_coverage' then
    return (
      with base as (
        select p.id provider_id,p.stable_key,coalesce(p.display_name,p.canonical_name) provider_name,p.website,p.lifecycle_status,
          c.iso_alpha2 country_code,c.name country_name,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='rejected') rejected_candidate_count,
          (select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') latest_candidate_at,
          pa.id primary_asset_id,pa.source_url primary_source_url,pa.evidence_id primary_evidence_id,pa.storage_path primary_storage_path,
          pa.mime_type primary_mime_type,pa.content_hash primary_content_hash,pa.verified_at primary_verified_at,
          case when pa.id is not null then 'approved'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') then 'needs_review'
            else 'missing' end coverage_state
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        left join lateral (
          select x.* from catalogue.provider_assets x where x.provider_id=p.id and x.is_primary and x.status='approved'
            and x.asset_type in ('logo','logo_dark','logo_light')
          order by x.verified_at desc nulls last,x.id limit 1
        ) pa on true
        where coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), filtered as (select * from base where v_state is null or coverage_state=v_state),
      page as (
        select * from filtered order by case coverage_state when 'blocked' then 1 when 'needs_review' then 2 when 'missing' then 3 else 4 end,
          lower(provider_name),provider_id limit v_limit offset v_offset
      )
      select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb))
    );
  elsif p_operation='provider_asset_context' then
    return (
      select jsonb_build_object(
        'provider_id',p.id,
        'state',case when pa.id is not null then 'approved'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') then 'needs_review'
          else 'missing' end,
        'primary_asset',case when pa.id is null then null else jsonb_build_object('id',pa.id,'source_url',pa.source_url,'evidence_id',pa.evidence_id,'storage_path',pa.storage_path,'mime_type',pa.mime_type,'content_hash',pa.content_hash,'verified_at',pa.verified_at) end,
        'candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'accepted_candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted'),
        'latest_candidate_at',(select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'authority','first_party_provider','refresh_cadence','quarterly')
      from catalogue.providers p
      left join lateral (
        select x.* from catalogue.provider_assets x where x.provider_id=p.id and x.is_primary and x.status='approved'
          and x.asset_type in ('logo','logo_dark','logo_light')
        order by x.verified_at desc nulls last,x.id limit 1
      ) pa on true
      where p.id=nullif(p_args->>'provider_id','')::uuid
    );
  end if;
  raise exception 'unsupported provider asset read operation: %',p_operation using errcode='22023';
end
$$;

revoke all on function security.admin_provider_asset_read(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_provider_asset_read(text,jsonb) to authenticated;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','public','security' as $$
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
 if p_operation in ('ranking_summary','ranking_filters','ranking_observations','ranking_imports') then return security.admin_ranking_read(p_operation,p_args); end if;
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
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result); end if;
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
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id); end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id))||jsonb_build_object('ranking_context',security.admin_course_rankings(v_id,10));
 end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id)); end if;
 return v_result;
end
$$;

commit;
