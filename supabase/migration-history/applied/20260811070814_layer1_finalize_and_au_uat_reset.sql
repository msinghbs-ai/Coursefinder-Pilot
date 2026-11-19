create or replace function public.svc_layer1_finalize_catalogue()
returns jsonb
language plpgsql
security definer
set search_path = public, catalogue, search, pipeline
as $$
declare
  v_docs bigint;
  v_generation bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  perform search.rebuild_course_documents();
  select coalesce(max(generation),0) into v_generation from search.projection_state;
  select count(*) into v_docs from search.course_documents;

  return jsonb_build_object(
    'providers', (select count(*) from catalogue.providers),
    'courses', (select count(*) from catalogue.courses),
    'cricos_provider_registrations', (select count(*) from catalogue.provider_registrations where lower(registration_scheme)='cricos'),
    'cricos_course_registrations', (select count(*) from catalogue.course_registrations where lower(scheme)='cricos'),
    'search_documents', v_docs,
    'search_generation', v_generation
  );
end;
$$;

revoke all on function public.svc_layer1_finalize_catalogue() from public, anon, authenticated;
grant execute on function public.svc_layer1_finalize_catalogue() to service_role;

create or replace function public.svc_layer1_reset_au_uat()
returns jsonb
language plpgsql
security definer
set search_path = public, catalogue, pim, search
as $$
declare
  v_cricos_courses bigint;
  v_cricos_providers bigint;
  v_docs bigint;
  v_generation bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select count(*) into v_cricos_courses from catalogue.courses where stable_key like 'course:cricos:%';
  select count(*) into v_cricos_providers from catalogue.providers where stable_key like 'provider:cricos:%';

  delete from catalogue.course_registrations where lower(scheme)='cricos';
  delete from catalogue.provider_registrations where lower(registration_scheme)='cricos';

  update catalogue.courses
     set canonical_source_id=null, last_verified_at=null, updated_at=now()
   where stable_key like 'course:demo:%';
  update catalogue.providers
     set canonical_source_id=null, last_verified_at=null, updated_at=now()
   where stable_key like 'provider:demo:%';

  delete from pim.entity_registry where entity_type='course' and stable_key like 'course:cricos:%';
  delete from pim.entity_registry where entity_type='provider' and stable_key like 'provider:cricos:%';

  perform search.rebuild_course_documents();
  select count(*) into v_docs from search.course_documents;
  select coalesce(max(generation),0) into v_generation from search.projection_state;

  return jsonb_build_object(
    'status','reset',
    'deleted_cricos_courses',v_cricos_courses,
    'deleted_cricos_providers',v_cricos_providers,
    'providers',(select count(*) from catalogue.providers),
    'courses',(select count(*) from catalogue.courses),
    'cricos_provider_registrations',(select count(*) from catalogue.provider_registrations where lower(registration_scheme)='cricos'),
    'cricos_course_registrations',(select count(*) from catalogue.course_registrations where lower(scheme)='cricos'),
    'search_documents',v_docs,
    'search_generation',v_generation
  );
end;
$$;

revoke all on function public.svc_layer1_reset_au_uat() from public, anon, authenticated;
grant execute on function public.svc_layer1_reset_au_uat() to service_role;
