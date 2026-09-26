-- Decision 150: automated actions run under a dedicated system identity, not a person's account.
-- The account cannot sign in (no password, permanently banned, non-routable address) and holds only
-- Pipeline Operator (rank 4), the minimum the Layer 2 batch service requires. Previously
-- layer2_automation_actor() returned the first Platform Admin (rank 6). There is no fallback to a
-- person: if the system identity is missing or lacks its role, automation does not act.
insert into auth.users(id, instance_id, aud, role, email, encrypted_password, banned_until,
                       raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
values ('c0ffee00-0000-4000-8000-000000000150', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'automation@system.coursefinder.invalid', null, '9999-12-31 00:00:00+00',
        jsonb_build_object('provider','system','providers',jsonb_build_array('system'),'system_identity',true,'purpose','CourseFinder automation (Decision 150)'),
        jsonb_build_object('display_name','CourseFinder Automation'), now(), now(), false, false)
on conflict (id) do nothing;

insert into security.user_roles(user_id, role_code)
select 'c0ffee00-0000-4000-8000-000000000150', 'pipeline_operator'
where not exists (select 1 from security.user_roles where user_id='c0ffee00-0000-4000-8000-000000000150' and role_code='pipeline_operator');

create or replace function security.system_actor_id()
returns uuid language sql stable security definer set search_path to 'pg_catalog','auth','security'
as $$
  select u.id from auth.users u
  where u.id='c0ffee00-0000-4000-8000-000000000150' and (u.raw_app_meta_data->>'system_identity')='true'
    and exists (select 1 from security.user_roles ur join security.roles r on r.code=ur.role_code
                where ur.user_id=u.id and r.status='active' and r.rank>=4 and (ur.expires_at is null or ur.expires_at>now()))
$$;
revoke all on function security.system_actor_id() from public, anon, authenticated;

create or replace function public.layer2_automation_actor()
returns uuid language sql stable security definer set search_path to 'pg_catalog','security'
as $$ select security.system_actor_id() $$;
revoke all on function public.layer2_automation_actor() from public, anon, authenticated;
grant execute on function public.layer2_automation_actor() to service_role;
