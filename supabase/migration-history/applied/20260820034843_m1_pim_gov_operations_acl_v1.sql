create or replace function security.admin_operations_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, public, workflow, pipeline, ref, integration, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,1000),1),5000);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;

  if p_operation='reviews' then
    if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.priority desc,x.created_at desc),'[]'::jsonb)
      into v_result from public.ui_review_queue(v_limit) x;
    return v_result;
  elsif p_operation='jobs' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
      into v_result from public.ui_jobs_list(v_limit) x;
    return v_result;
  elsif p_operation='sources' then
    if v_rank<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.country_code,x.source_label),'[]'::jsonb)
      into v_result from public.ui_regulatory_sources_list() x;
    return v_result;
  end if;

  raise exception 'unsupported operations read: %',p_operation using errcode='22023';
end
$$;

revoke execute on function security.admin_operations_read(text,jsonb) from public, anon;
grant execute on function security.admin_operations_read(text,jsonb) to authenticated, service_role;

create or replace function public.admin_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation='courses_page' then
    return security.admin_course_page_search_state(security.admin_catalogue_page(p_operation,p_args));
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  if p_operation in ('reviews','jobs','sources') then
    return security.admin_operations_read(p_operation,p_args);
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
$$;

revoke execute on function public.ui_review_queue(integer) from public, anon, authenticated;
revoke execute on function public.ui_jobs_list(integer) from public, anon, authenticated;
revoke execute on function public.ui_regulatory_sources_list() from public, anon, authenticated;
grant execute on function public.ui_review_queue(integer) to service_role;
grant execute on function public.ui_jobs_list(integer) to service_role;
grant execute on function public.ui_regulatory_sources_list() to service_role;
