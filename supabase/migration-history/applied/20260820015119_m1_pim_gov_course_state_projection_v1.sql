-- CF-CHG-20260820-008 — expose Search projection state explicitly without changing publication/lifecycle/Search data.

create or replace function security.admin_course_page_search_state(
  p_page jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, security, search, auth
as $$
declare
  v_rank integer:=0;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select coalesce(jsonb_agg(
    i.item || jsonb_build_object(
      'search_projected', d.course_id is not null,
      'search_projection_status', d.status,
      'search_projection_updated_at', d.updated_at,
      'search_has_fee', d.has_fee,
      'search_has_intake', d.has_intake,
      'search_has_english', d.has_english
    ) order by i.ord
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(p_page->'items','[]'::jsonb)) with ordinality as i(item,ord)
  left join search.course_documents d on d.course_id=nullif(i.item->>'id','')::uuid;

  return jsonb_set(coalesce(p_page,'{}'::jsonb),'{items}',v_items,true);
end
$$;

revoke all on function security.admin_course_page_search_state(jsonb) from public,anon;
grant execute on function security.admin_course_page_search_state(jsonb) to authenticated,service_role;
comment on function security.admin_course_page_search_state(jsonb) is
  'CF-CHG-20260820-008 role-checked additive Search projection decoration for Course Admin pages. Projection existence/status is not publication approval.';

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
  if p_operation='courses_page' then
    return security.admin_course_page_search_state(security.admin_catalogue_page(p_operation,p_args));
  end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then
    return security.admin_catalogue_page(p_operation,p_args);
  end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then
    return security.admin_insights_read(p_operation,p_args);
  end if;
  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id));
  end if;
  return v_result;
end
$$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
comment on function public.admin_read(text,jsonb) is
  'Governed browser read contract. Course pages expose Search projection state separately from canonical lifecycle/publication/readiness.';
