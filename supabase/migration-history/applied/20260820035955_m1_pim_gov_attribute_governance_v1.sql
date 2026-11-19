create or replace function security.admin_pim_governance_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pim, auth
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,2000),1),5000);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'families',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pim.attribute_families order by code limit v_limit) x),'[]'::jsonb),
    'groups',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pim.attribute_groups order by code limit v_limit) x),'[]'::jsonb),
    'attributes',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pim.attributes order by code limit v_limit) x),'[]'::jsonb),
    'options',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pim.attribute_options order by attribute_id,sort_order nulls last,code limit v_limit) x),'[]'::jsonb),
    'completeness_profiles',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pim.completeness_profiles order by code limit v_limit) x),'[]'::jsonb),
    'completeness_profile_rules',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from pim.completeness_profile_rules order by profile_id,sort_order nulls last,attribute_code limit v_limit) x),'[]'::jsonb)
  ) into v_result;

  return v_result;
end
$$;

revoke execute on function security.admin_pim_governance_read(jsonb) from public, anon;
grant execute on function security.admin_pim_governance_read(jsonb) to authenticated, service_role;

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
  if p_operation='attributes' then
    return security.admin_pim_governance_read(p_args);
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

revoke execute on function public.ui_attribute_families_list() from public, anon, authenticated;
revoke execute on function public.ui_attribute_groups_list() from public, anon, authenticated;
revoke execute on function public.ui_attributes_list() from public, anon, authenticated;
revoke execute on function public.ui_attribute_options_list(integer) from public, anon, authenticated;
revoke execute on function public.ui_completeness_profiles_list() from public, anon, authenticated;
grant execute on function public.ui_attribute_families_list() to service_role;
grant execute on function public.ui_attribute_groups_list() to service_role;
grant execute on function public.ui_attributes_list() to service_role;
grant execute on function public.ui_attribute_options_list(integer) to service_role;
grant execute on function public.ui_completeness_profiles_list() to service_role;
