-- CF-247 / R22: the Layer 1 run summary counted retired registrations as current (26,787 CRICOS course
-- registrations while 25,978 are active). The summary now reports active counts under the existing
-- names, with retired counts alongside. Checksum-guarded.
do $guard$
begin
  if md5(pg_get_functiondef('public.svc_layer1_finalize_catalogue()'::regprocedure))<>'ea36f0a43e1577873fa623c6ec580bd1' then
    raise exception 'svc_layer1_finalize_catalogue changed since review; not replaced'; end if;
end $guard$;

create or replace function public.svc_layer1_finalize_catalogue()
returns jsonb language plpgsql security definer set search_path to 'public','catalogue','search','pipeline' as $function$
declare v_generation bigint; v_docs bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into search.refresh_requests(requested_by) values ('svc_layer1_finalize_catalogue');
  select coalesce(max(generation),0) into v_generation from search.projection_state;
  select count(*) into v_docs from search.course_documents;
  return jsonb_build_object(
    'providers', (select count(*) from catalogue.providers where lifecycle_status='active'),
    'courses', (select count(*) from catalogue.courses where lifecycle_status='active'),
    'cricos_provider_registrations', (select count(*) from catalogue.provider_registrations where lower(registration_scheme)='cricos' and status='active'),
    'cricos_course_registrations', (select count(*) from catalogue.course_registrations where lower(scheme)='cricos' and status='active'),
    'retired', jsonb_build_object(
      'providers', (select count(*) from catalogue.providers where lifecycle_status<>'active'),
      'courses', (select count(*) from catalogue.courses where lifecycle_status<>'active'),
      'cricos_course_registrations', (select count(*) from catalogue.course_registrations where lower(scheme)='cricos' and status<>'active')),
    'counts_basis', 'active records; retired records are kept and counted separately',
    'search_documents', v_docs, 'search_generation', v_generation,
    'search_refresh', 'requested (applied by the search-refresh job within minutes)');
end $function$;
revoke all on function public.svc_layer1_finalize_catalogue() from public, anon, authenticated;
grant execute on function public.svc_layer1_finalize_catalogue() to service_role;
