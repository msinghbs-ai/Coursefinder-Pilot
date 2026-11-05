CREATE OR REPLACE FUNCTION security.current_role_rank()
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'security', 'auth'
AS $function$
select coalesce(max(r.rank),0)::smallint
from security.user_roles ur join security.roles r on r.code=ur.role_code
where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active'
$function$
;
CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$
;
CREATE OR REPLACE FUNCTION security.provider_university_groups(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('code',replace(ic.code,'au_',''),'name',ic.name) order by ic.name),'[]'::jsonb)
    from catalogue.provider_collection_memberships m join ref.institution_collections ic on ic.id=m.collection_id
   where m.provider_id=p_provider_id and m.status='active' and ic.collection_type='university_group' and ic.status='active'
     and (m.valid_to is null or m.valid_to>=current_date)
$function$
;
CREATE OR REPLACE FUNCTION security.university_group_provider_ids(p_group text)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref'
AS $function$
  select distinct m.provider_id
    from catalogue.provider_collection_memberships m
    join ref.institution_collections ic on ic.id=m.collection_id
   where ic.collection_type='university_group' and ic.status='active'
     and m.status='active' and (m.valid_to is null or m.valid_to>=current_date)
     and replace(ic.code,'au_','')=regexp_replace(lower(btrim(coalesce(p_group,''))),'^au_','')
$function$
;
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
 if p_operation='provider_insights' then v_id:=nullif(p_args->>'id','')::uuid;return jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id));end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)-'courses'-'courses_page'-'evidence'-'evidence_page'-'sources'-'history';end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 if p_operation='course_insights' then v_id:=nullif(p_args->>'id','')::uuid;return jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id));end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('display_code',security.course_display_code_v1(v_id))||jsonb_build_object('course_scholarships',security.admin_course_scholarships(v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $function$
;
CREATE OR REPLACE FUNCTION security.admin_course_page_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'public', 'auth'
AS $function$
declare
  v_q text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_provider_id uuid;
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  v_simple :=
    v_q is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'level_code','') is null
    and nullif(p_args->>'field_code','') is null
    and nullif(p_args->>'delivery_mode','') is null
    and nullif(p_args->>'lifecycle_status','') is null
    and nullif(p_args->>'publication_status','') is null
    and nullif(p_args->>'has_fee','') is null
    and nullif(p_args->>'has_intake','') is null
    and nullif(p_args->>'has_english','') is null
    and nullif(p_args->>'has_scholarship','') is null
    and nullif(p_args->>'has_state','') is null
    and nullif(p_args->>'has_link','') is null
    and nullif(p_args->>'min_completeness','') is null
    and nullif(p_args->>'freshness','') is null
    and nullif(p_args->>'university_group','') is null
    and nullif(p_args->>'applicant','') is null
    and v_sort='course' and v_dir='asc';

  if v_simple then
    return security.admin_course_page_unfiltered_fast(p_args);
  end if;

  if v_q is not null and v_q ~* '^course:' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where c.stable_key=v_q limit 1;
  elsif v_q is not null and v_q ~ '^[0-9]{6}[A-Za-z]$' then
    select c.provider_id into v_provider_id
    from catalogue.courses c where upper(c.course_code)=upper(v_q) limit 1;
  end if;

  if v_provider_id is not null and nullif(p_args->>'provider_id','') is null then
    return security.admin_course_page_fast_base(p_args||jsonb_build_object('provider_id',v_provider_id::text));
  end if;

  return security.admin_course_page_fast_base(p_args);
end $function$
;
CREATE OR REPLACE FUNCTION api.website_v2_label_month(p_label text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select m.n from (values (1,'jan'),(2,'feb'),(3,'mar'),(4,'apr'),(5,'may'),(6,'jun'),(7,'jul'),(8,'aug'),(9,'sep'),(10,'oct'),(11,'nov'),(12,'dec')) m(n,k)
  where strpos(lower(coalesce(p_label,'')), m.k) > 0
  order by strpos(lower(p_label), m.k) limit 1
$function$
;
