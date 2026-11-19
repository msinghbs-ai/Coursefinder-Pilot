-- CF-CHG-20260820-005 — restore accepted QILT/PRISMS Admin visibility behind the governed read boundary.
-- Canonical QILT/PRISMS observations and their source-grain projections are not modified.

create or replace function security.admin_insights_read(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, security, auth
as $$
declare
  v_rank integer := 0;
  v_limit integer := least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer := greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_provider_id uuid;
  v_year integer;
  v_suppressed boolean;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;

  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  v_provider_id := nullif(p_args->>'provider_id','')::uuid;
  v_year := nullif(p_args->>'year','')::integer;
  v_suppressed := case
    when nullif(p_args->>'suppressed','') is null then null
    else (p_args->>'suppressed')::boolean
  end;

  if p_operation='qilt_outcomes' then
    return public.ui_qilt_outcomes_page(
      v_limit,
      v_offset,
      nullif(p_args->>'query',''),
      nullif(p_args->>'survey_code',''),
      nullif(p_args->>'metric_code',''),
      v_provider_id,
      nullif(p_args->>'status',''),
      v_year,
      coalesce(nullif(p_args->>'sort',''),'provider'),
      coalesce(nullif(p_args->>'direction',''),'asc')
    );
  elsif p_operation='qilt_filters' then
    return public.ui_qilt_filter_options(nullif(p_args->>'survey_code',''));
  elsif p_operation='prisms_student_flow' then
    return public.ui_prisms_student_flow_page(
      v_limit,
      v_offset,
      nullif(p_args->>'query',''),
      nullif(p_args->>'subdivision_code',''),
      nullif(p_args->>'study_area_code',''),
      nullif(p_args->>'sector_code',''),
      nullif(p_args->>'remoteness_area',''),
      v_suppressed,
      coalesce(nullif(p_args->>'sort',''),'geography'),
      coalesce(nullif(p_args->>'direction',''),'asc')
    );
  elsif p_operation='prisms_filters' then
    return public.ui_prisms_filter_options();
  else
    raise exception 'unsupported insights read operation: %',p_operation using errcode='22023';
  end if;
end
$$;

revoke all on function security.admin_insights_read(text,jsonb) from public,anon;
grant execute on function security.admin_insights_read(text,jsonb) to authenticated,service_role;
comment on function security.admin_insights_read(text,jsonb) is
  'CF-CHG-20260820-005 private role-checked dispatcher for accepted QILT Provider outcomes and PRISMS source-grain Student Flow Admin reads.';

create or replace function public.admin_read(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;

  v_result := security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id := nullif(p_args->>'id','')::uuid;
    return v_result || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id));
  end if;
  return v_result;
end
$$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
comment on function public.admin_read(text,jsonb) is
  'Governed browser read contract. Routes QILT/PRISMS Insights through a private role-checked dispatcher and retains CF-CHG-20260820-001 Course fee-summary enrichment.';

revoke all on function public.ui_qilt_outcomes_page(integer,integer,text,text,text,uuid,text,integer,text,text) from public,anon,authenticated;
revoke all on function public.ui_qilt_filter_options(text) from public,anon,authenticated;
revoke all on function public.ui_prisms_student_flow_page(integer,integer,text,text,text,text,text,boolean,text,text) from public,anon,authenticated;
revoke all on function public.ui_prisms_filter_options() from public,anon,authenticated;

grant execute on function public.ui_qilt_outcomes_page(integer,integer,text,text,text,uuid,text,integer,text,text) to service_role;
grant execute on function public.ui_qilt_filter_options(text) to service_role;
grant execute on function public.ui_prisms_student_flow_page(integer,integer,text,text,text,text,text,boolean,text,text) to service_role;
grant execute on function public.ui_prisms_filter_options() to service_role;
