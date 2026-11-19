create or replace function public.svc_layer1_runtime_uat_grant_admin(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public,security
as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' and current_user <> 'postgres' then raise exception 'service_role required'; end if;
  insert into security.user_roles(user_id,role_code) values(p_user_id,'platform_admin') on conflict do nothing;
end $$;

create or replace function public.svc_layer1_runtime_uat_revoke_admin(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public,security
as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' and current_user <> 'postgres' then raise exception 'service_role required'; end if;
  delete from security.user_roles where user_id=p_user_id and role_code='platform_admin';
end $$;

create or replace function public.svc_layer1_runtime_uat_stats()
returns jsonb
language sql
security definer
set search_path=public,catalogue,search,pipeline,workflow
as $$
select jsonb_build_object(
  'providers',(select count(*) from catalogue.providers),
  'courses',(select count(*) from catalogue.courses),
  'providerRegistrations',(select count(*) from catalogue.provider_registrations),
  'courseRegistrations',(select count(*) from catalogue.course_registrations),
  'searchDocuments',(select count(*) from search.course_documents),
  'pipelineJobs',(select count(*) from pipeline.jobs),
  'evidenceMetadata',(select count(*) from pipeline.evidence_artifacts),
  'reviewQueue',(select count(*) from workflow.review_queue),
  'seedSnapshots',(select count(*) from pipeline.layer1_seed_snapshots),
  'searchGeneration',(select generation from search.projection_state where projection_code='courses'),
  'searchProjectionRows',(select row_count from search.projection_state where projection_code='courses')
);
$$;

revoke all on function public.svc_layer1_runtime_uat_grant_admin(uuid) from public,anon,authenticated;
revoke all on function public.svc_layer1_runtime_uat_revoke_admin(uuid) from public,anon,authenticated;
revoke all on function public.svc_layer1_runtime_uat_stats() from public,anon,authenticated;
grant execute on function public.svc_layer1_runtime_uat_grant_admin(uuid) to service_role;
grant execute on function public.svc_layer1_runtime_uat_revoke_admin(uuid) to service_role;
grant execute on function public.svc_layer1_runtime_uat_stats() to service_role;
