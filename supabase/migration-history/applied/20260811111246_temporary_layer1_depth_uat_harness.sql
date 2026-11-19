create extension if not exists pg_net with schema extensions;

create table if not exists public._layer1_depth_uat_control(
  id boolean primary key default true check (id),
  token text not null,
  created_at timestamptz not null default now()
);
revoke all on public._layer1_depth_uat_control from public,anon,authenticated;
grant select on public._layer1_depth_uat_control to service_role;
insert into public._layer1_depth_uat_control(id,token) values(true,encode(gen_random_bytes(32),'hex')) on conflict(id) do update set token=excluded.token,created_at=now();

create or replace function public._layer1_depth_uat_token() returns text language sql security definer set search_path=public as $$ select token from public._layer1_depth_uat_control where id=true $$;
revoke all on function public._layer1_depth_uat_token() from public,anon,authenticated;
grant execute on function public._layer1_depth_uat_token() to service_role;

create or replace function public._layer1_depth_uat_grant_admin(p_user_id uuid) returns void language plpgsql security definer set search_path=public,security as $$ begin if coalesce(auth.role(),'') <> 'service_role' and current_user <> 'postgres' then raise exception 'service_role required'; end if; insert into security.user_roles(user_id,role_code,granted_by) values(p_user_id,'platform_admin',null) on conflict(user_id,role_code) do update set expires_at=null; end $$;
revoke all on function public._layer1_depth_uat_grant_admin(uuid) from public,anon,authenticated;
grant execute on function public._layer1_depth_uat_grant_admin(uuid) to service_role;

create or replace function public._layer1_depth_uat_state() returns jsonb language sql security definer set search_path=public,catalogue,pipeline,search,workflow as $$
select jsonb_build_object(
 'providers',(select count(*) from catalogue.providers),
 'courses',(select count(*) from catalogue.courses),
 'campuses',(select count(*) from catalogue.campuses),
 'course_campus_links',(select count(*) from catalogue.course_campuses),
 'provider_registrations',(select count(*) from catalogue.provider_registrations),
 'course_registrations',(select count(*) from catalogue.course_registrations),
 'search_documents',(select count(*) from search.course_documents),
 'pipeline_jobs',(select count(*) from pipeline.jobs),
 'evidence_metadata',(select count(*) from pipeline.evidence_artifacts),
 'seed_snapshots',(select count(*) from pipeline.layer1_seed_snapshots),
 'review_queue',(select count(*) from workflow.review_queue)
) $$;
revoke all on function public._layer1_depth_uat_state() from public,anon,authenticated;
grant execute on function public._layer1_depth_uat_state() to service_role;
