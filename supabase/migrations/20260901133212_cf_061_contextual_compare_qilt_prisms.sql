-- CF-CHG-20260901-061
-- Applied Pilot migration version: 20260901133212
-- Bounded QILT/PRISMS contextual comparison read surface.
-- Read-only; no Layer 1 identity, Search or Publication mutation.

begin;

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
 if p_operation='contextual_compare' then return security.admin_contextual_compare(p_args); end if;
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
     || jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id));
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
     || jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id));
 end if;

 if p_operation='scholarship_detail' then
   v_id:=nullif(p_args->>'id','')::uuid;
   return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));
 end if;

 return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_contextual_compare(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_type text:=lower(coalesce(nullif(btrim(p_args->>'entity_type'),''),'provider'));
  v_ids uuid[];
  v_count integer:=0;
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'catalogue reader role required' using errcode='42501'; end if;
  if v_type not in ('provider','course') then raise exception 'invalid comparison entity type' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_args->'ids','[]'::jsonb))<>'array' then raise exception 'ids must be an array' using errcode='22023'; end if;

  begin
    select coalesce(array_agg(value::uuid order by ordinality),'{}'::uuid[])
      into v_ids
    from jsonb_array_elements_text(coalesce(p_args->'ids','[]'::jsonb)) with ordinality as z(value,ordinality);
  exception when invalid_text_representation then
    raise exception 'invalid comparison id' using errcode='22023';
  end;

  v_count:=coalesce(array_length(v_ids,1),0);
  if v_count>6 then raise exception 'maximum six comparison entities' using errcode='22023'; end if;
  if v_count=0 then
    return jsonb_build_object('entity_type',v_type,'items','[]'::jsonb,'total',0,'max_items',6);
  end if;

  if v_type='provider' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',p.id,
      'name',coalesce(p.display_name,p.canonical_name),
      'country_code',co.iso_alpha2,
      'subdivision',sd.name,
      'city',p.city,
      'contextual_insights',security.admin_contextual_insights_v2('provider',p.id)
    ) order by u.ord),'[]'::jsonb)
    into v_items
    from unnest(v_ids) with ordinality u(id,ord)
    join catalogue.providers p on p.id=u.id
    left join ref.countries co on co.id=p.country_id
    left join ref.subdivisions sd on sd.id=p.subdivision_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',c.id,
      'name',coalesce(c.display_title,c.canonical_title),
      'provider_id',p.id,
      'provider_name',coalesce(p.display_name,p.canonical_name),
      'course_code',c.course_code,
      'study_level',coalesce(sl.name,sl.code),
      'field_of_study',coalesce(f.name,f.code),
      'contextual_insights',security.admin_contextual_insights_v2('course',c.id)
    ) order by u.ord),'[]'::jsonb)
    into v_items
    from unnest(v_ids) with ordinality u(id,ord)
    join catalogue.courses c on c.id=u.id
    join catalogue.providers p on p.id=c.provider_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study f on f.id=c.primary_field_id;
  end if;

  return jsonb_build_object(
    'entity_type',v_type,
    'items',v_items,
    'total',jsonb_array_length(v_items),
    'requested_total',v_count,
    'max_items',6,
    'authority_note','Context only. QILT/PRISMS statistics retain their governed source grain and do not become Course facts.'
  );
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_contextual_insights_v2(p_entity_type text, p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'scholarship', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_provider uuid;
  v_level uuid;
  v_country_code text;
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_base jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'catalogue reader role required' using errcode='42501'; end if;

  v_base:=security.admin_contextual_insights(p_entity_type,p_entity_id);

  if p_entity_type='provider' then
    select p.id,co.iso_alpha2 into v_provider,v_country_code
    from catalogue.providers p left join ref.countries co on co.id=p.country_id
    where p.id=p_entity_id;
  elsif p_entity_type='course' then
    select c.provider_id,c.study_level_id,co.iso_alpha2 into v_provider,v_level,v_country_code
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    left join ref.countries co on co.id=p.country_id
    where c.id=p_entity_id;
  else
    raise exception 'unsupported contextual entity type' using errcode='22023';
  end if;

  if v_provider is null then return v_base; end if;

  select count(*) into v_total
  from catalogue.provider_outcomes po
  where po.provider_id=v_provider
    and coalesce(po.status,'current') in ('active','current')
    and (p_entity_type='provider' or po.study_level_id is null or v_level is null or po.study_level_id=v_level);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.level_match desc,x.collection_year_to desc nulls last,x.metric_name),'[]'::jsonb)
  into v_items
  from (
    select
      po.id,
      coalesce(os.source_family,case when v_country_code='AU' then 'QILT' else 'outcomes' end) source_family,
      coalesce(os.name,os.code,'Student outcomes') source_label,
      os.code survey_code,
      om.name metric_name,
      om.code metric_code,
      om.unit,
      po.metric_value,
      po.national_benchmark,
      po.response_count,
      po.confidence_low,
      po.confidence_high,
      po.audience,
      po.collection_year_from,
      po.collection_year_to,
      po.source_cohort_code,
      esa.name study_area,
      esa.code study_area_code,
      sl.name study_level,
      sl.code study_level_code,
      po.status,
      po.observed_at,
      po.evidence_id,
      case when p_entity_type='course' and po.study_level_id=v_level then true else false end level_match,
      case when p_entity_type='provider' then 'provider' else 'provider_context' end granularity
    from catalogue.provider_outcomes po
    left join ref.outcome_surveys os on os.id=po.survey_id
    left join ref.outcome_metrics om on om.id=po.metric_id
    left join ref.external_study_areas esa on esa.id=po.external_study_area_id
    left join ref.study_levels sl on sl.id=po.study_level_id
    where po.provider_id=v_provider
      and coalesce(po.status,'current') in ('active','current')
      and (p_entity_type='provider' or po.study_level_id is null or v_level is null or po.study_level_id=v_level)
    order by
      case when p_entity_type='course' and po.study_level_id=v_level then 1 else 0 end desc,
      po.collection_year_to desc nulls last,
      po.observed_at desc nulls last,
      om.name
    limit 30
  ) x;

  v_base:=jsonb_set(v_base,'{student_outcomes,items}',v_items,true);
  v_base:=jsonb_set(v_base,'{student_outcomes,total}',to_jsonb(v_total),true);
  v_base:=jsonb_set(v_base,'{student_outcomes,granularity}',to_jsonb(case when p_entity_type='provider' then 'provider' else 'provider_context' end),true);
  return v_base;
end
$function$;

revoke all on function security.admin_contextual_insights_v2(text,uuid) from public,anon,authenticated;
grant execute on function security.admin_contextual_insights_v2(text,uuid) to service_role;
revoke all on function security.admin_contextual_compare(jsonb) from public,anon,authenticated;
grant execute on function security.admin_contextual_compare(jsonb) to service_role;

commit;
