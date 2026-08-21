-- CF-CHG-20260821-016 residual security hardening.
-- Keep internal pipeline.sources.metadata intact server-side, but expose only
-- the operational fields required by the rank-4 Pipeline Ops browser.

create or replace function security.admin_pipeline_source_metadata_safe(p_metadata jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = 'pg_catalog'
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'configured_worker_version', p_metadata->'configured_worker_version',
    'worker_version', p_metadata->'worker_version',
    'scope', p_metadata->'scope',
    'coverage_role', p_metadata->'coverage_role',
    'apply_gate', p_metadata->'apply_gate',
    'apply_enabled', p_metadata->'apply_enabled',
    'identity_scheme', p_metadata->'identity_scheme',
    'course_identity_scheme', p_metadata->'course_identity_scheme',
    'transport', p_metadata->'transport',
    'acquisition_method', p_metadata->'acquisition_method',
    'coverage_complete_for_country', p_metadata->'coverage_complete_for_country'
  ));
$$;

create or replace function security.admin_pipeline_ops_sanitise_result(p_operation text, p_result jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog', 'security'
as $$
declare
  v_items jsonb;
begin
  if p_operation='pipeline_sources_page' then
    select coalesce(jsonb_agg(
      jsonb_set(x.item,'{metadata}',security.admin_pipeline_source_metadata_safe(coalesce(x.item->'metadata','{}'::jsonb)),true)
      order by x.ord
    ),'[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(p_result->'items','[]'::jsonb)) with ordinality as x(item,ord);
    return jsonb_set(p_result,'{items}',v_items,true);
  end if;

  if p_operation='pipeline_job_detail' and jsonb_typeof(p_result->'source')='object' then
    return jsonb_set(
      p_result,
      '{source,metadata}',
      security.admin_pipeline_source_metadata_safe(coalesce(p_result#>'{source,metadata}','{}'::jsonb)),
      true
    );
  end if;

  return p_result;
end;
$$;

revoke all on function security.admin_pipeline_source_metadata_safe(jsonb) from public, anon;
revoke all on function security.admin_pipeline_ops_sanitise_result(text,jsonb) from public, anon;
grant execute on function security.admin_pipeline_source_metadata_safe(jsonb) to authenticated;
grant execute on function security.admin_pipeline_ops_sanitise_result(text,jsonb) to authenticated;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'pg_catalog', 'public', 'security'
as $function$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation='dashboard' then
    return security.admin_dashboard_maturity();
  end if;
  if p_operation in ('provider_filters','course_filters') then
    return security.admin_catalogue_filter_options(p_operation,p_args);
  end if;
  if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then
    return security.admin_evidence_read(p_operation,p_args);
  end if;
  if p_operation='courses_page' then
    return security.admin_course_page_fast(p_args);
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  if p_operation='reviews_page' then
    return security.admin_operational_page(p_operation,p_args);
  end if;
  if p_operation in ('reviews','jobs','sources') then
    return security.admin_operations_read(p_operation,p_args);
  end if;
  if p_operation='attributes' then
    return security.admin_pim_governance_read(p_args);
  end if;
  if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then
    v_result:=security.admin_pipeline_ops_read(p_operation,p_args);
    return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);
  end if;
  if p_operation='publication_overview' then
    return security.admin_publication_overview();
  end if;
  if p_operation='provider_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return security.admin_provider_detail(v_id);
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
      || jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));
  end if;
  if p_operation='scholarship_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result || jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));
  end if;
  return v_result;
end;
$function$;

revoke all on function public.admin_read(text,jsonb) from public, anon;
grant execute on function public.admin_read(text,jsonb) to authenticated;
