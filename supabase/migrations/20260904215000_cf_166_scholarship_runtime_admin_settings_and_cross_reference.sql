create table if not exists pipeline.scholarship_runtime_settings (
  country_code text primary key,
  enabled boolean not null default true,
  detail_batch_limit integer not null default 25 check (detail_batch_limit between 1 and 100),
  auto_dispatch boolean not null default true,
  catalogue_refresh_hours integer not null default 168 check (catalogue_refresh_hours between 1 and 2160),
  detail_refresh_hours integer not null default 168 check (detail_refresh_hours between 1 and 2160),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
alter table pipeline.scholarship_runtime_settings enable row level security;
revoke all on pipeline.scholarship_runtime_settings from public, anon, authenticated;
grant select,insert,update,delete on pipeline.scholarship_runtime_settings to service_role;
insert into pipeline.scholarship_runtime_settings(country_code,enabled,detail_batch_limit,auto_dispatch,catalogue_refresh_hours,detail_refresh_hours,metadata)
values('AU',true,25,true,168,168,jsonb_build_object('international_only',true,'publication_authorised',false,'route_mode','managed','change_control_ref','CF-166'))
on conflict(country_code) do nothing;

create or replace function security.admin_provider_scholarships(p_provider_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','scholarship','catalogue','auth' as $$
declare v_rank integer; v_items jsonb; v_total integer; v_mapped_courses integer; v_review integer;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'scholarship_id',s.id,'name',s.name,'scholarship_type',s.scholarship_type,'audience',s.audience,
   'award_value_text',s.award_value_text,'award_value_type',s.award_value_type,'award_percentage',s.award_percentage,
   'award_amount',s.award_amount,'award_currency_code',s.award_currency_code,'academic_year',s.academic_year,
   'application_close_date',s.application_close_date,'lifecycle_status',s.lifecycle_status,'publication_status',s.publication_status,
   'source_url',s.source_url,'evidence_id',s.evidence_id,
   'mapped_course_count',(select count(*) from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped')
 ) order by s.name),'[]'::jsonb),count(*)::int
 into v_items,v_total from scholarship.scholarships s where s.provider_id=p_provider_id;
 select count(distinct m.course_id)::int into v_mapped_courses from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id where s.provider_id=p_provider_id and m.mapping_state='mapped';
 select count(*)::int into v_review from scholarship.course_mapping_candidates c join scholarship.scholarships s on s.id=c.scholarship_id where s.provider_id=p_provider_id and c.status='needs_review';
 return jsonb_build_object('items',v_items,'scholarship_count',coalesce(v_total,0),'mapped_course_count',coalesce(v_mapped_courses,0),'needs_review_count',coalesce(v_review,0));
end $$;

create or replace function security.admin_scholarship_runtime_read(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','scholarship','catalogue','ref','auth' as $$
declare v_rank integer; v_country text:=upper(coalesce(nullif(p_args->>'country_code',''),'AU')); v_q text:=nullif(trim(coalesce(p_args->>'query','')),''); v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200); v_result jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 select jsonb_build_object(
   'settings',coalesce((select to_jsonb(s)-'updated_by' from pipeline.scholarship_runtime_settings s where s.country_code=v_country),jsonb_build_object('country_code',v_country,'enabled',true,'detail_batch_limit',25,'auto_dispatch',true,'catalogue_refresh_hours',168,'detail_refresh_hours',168)),
   'policy',jsonb_build_object('international_only',true,'canonical_mutation_authorised',false,'publication_authorised',false,'route_source','Administration / Scraper Config'),
   'summary',jsonb_build_object(
      'canonical',(select count(*) from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country),
      'published',(select count(*) from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and s.publication_status='published'),
      'international_canonical',(select count(*) from scholarship.scholarships s join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and lower(coalesce(s.audience,''))='international'),
      'candidates',(select count(*) from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country),
      'detail_ready',(select count(*) from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and d.classification='detail_ready'),
      'needs_review',(select count(*) from pipeline.layer2_scholarship_discovery_candidates d join pipeline.sources src on src.id=d.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and d.classification='needs_review'),
      'source_records',(select count(*) from pipeline.scholarship_source_records sr join pipeline.sources src on src.id=sr.source_id join catalogue.providers p on p.id=src.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country),
      'mapped_courses',(select count(distinct m.course_id) from scholarship.course_mappings m join scholarship.scholarships s on s.id=m.scholarship_id join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and m.mapping_state='mapped'),
      'calculations',(select count(*) from scholarship.course_financial_calculations fc join catalogue.courses co on co.id=fc.course_id join catalogue.providers p on p.id=co.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and fc.calculation_status='calculated')
   ),
   'providers',coalesce((select jsonb_agg(to_jsonb(x) order by x.provider_name) from (select ps.* from pipeline.scholarship_provider_stats ps join catalogue.providers p on p.id=ps.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2::text=v_country and (v_q is null or ps.provider_name ilike '%'||v_q||'%') order by ps.provider_name limit v_limit) x),'[]'::jsonb),
   'recent_runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.requested_at desc) from (select r.id,r.country_code,r.scope_type,r.scope_id,r.provider_id,r.provider_count,r.status,r.requested_at,r.started_at,r.completed_at,r.metadata from pipeline.scholarship_scope_acquisition_requests r where r.country_code=v_country order by r.requested_at desc limit 20) x),'[]'::jsonb),
   'countries',coalesce((select jsonb_agg(jsonb_build_object('code',c.iso_alpha2::text,'name',c.name) order by c.name) from ref.countries c where exists(select 1 from catalogue.providers p where p.country_id=c.id)),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;

create or replace function public.scholarship_runtime_settings_write(p_patch jsonb)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth' as $$
declare v_rank integer; v_uid uuid:=auth.uid(); v_country text:=upper(coalesce(nullif(p_patch->>'country_code',''),'AU')); v_row pipeline.scholarship_runtime_settings;
begin
 if v_uid is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
 insert into pipeline.scholarship_runtime_settings(country_code,enabled,detail_batch_limit,auto_dispatch,catalogue_refresh_hours,detail_refresh_hours,updated_by,updated_at,metadata)
 values(v_country,coalesce((p_patch->>'enabled')::boolean,true),least(greatest(coalesce(nullif(p_patch->>'detail_batch_limit','')::integer,25),1),100),coalesce((p_patch->>'auto_dispatch')::boolean,true),least(greatest(coalesce(nullif(p_patch->>'catalogue_refresh_hours','')::integer,168),1),2160),least(greatest(coalesce(nullif(p_patch->>'detail_refresh_hours','')::integer,168),1),2160),v_uid,now(),jsonb_build_object('international_only',true,'publication_authorised',false,'route_mode','managed','change_control_ref','CF-166'))
 on conflict(country_code) do update set enabled=excluded.enabled,detail_batch_limit=excluded.detail_batch_limit,auto_dispatch=excluded.auto_dispatch,catalogue_refresh_hours=excluded.catalogue_refresh_hours,detail_refresh_hours=excluded.detail_refresh_hours,updated_by=v_uid,updated_at=now(),metadata=excluded.metadata
 returning * into v_row;
 return to_jsonb(v_row)-'updated_by';
end $$;
revoke all on function public.scholarship_runtime_settings_write(jsonb) from public,anon;
grant execute on function public.scholarship_runtime_settings_write(jsonb) to authenticated,service_role;
grant execute on function security.admin_scholarship_runtime_read(jsonb) to authenticated,service_role;
grant execute on function security.admin_provider_scholarships(uuid) to authenticated,service_role;

-- public.admin_read is extended in the runtime migration to expose scholarship_runtime and provider scholarship_context.
create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable set search_path='pg_catalog','public','security' as $$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='scholarship_runtime' then return security.admin_scholarship_runtime_read(p_args); end if;
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