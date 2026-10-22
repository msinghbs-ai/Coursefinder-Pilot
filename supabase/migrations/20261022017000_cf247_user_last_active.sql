-- CF-247 (22 Oct 2026). Platform Admin 11:57: "bug/fix Sujata last login was yesterday".
-- Users & roles showed auth.users.last_sign_in_at, which changes only when a person types their password. A person who stays signed in
-- keeps working on a refreshed session, so the date looked weeks old (Sujata: signed in 7 Oct, last active 21 Oct 2026).
-- public.svc_admin_access_last_active returns each user's last activity: the latest of the sign-in and their sessions' refresh times.
-- The admin-user-management function adds it to the list (last_active_at); the screen shows Last active, with the sign-in date under it.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create or replace function public.svc_admin_access_last_active()
 returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_object_agg(u.id::text, greatest(u.last_sign_in_at,
           (select max(greatest(s.updated_at, s.refreshed_at::timestamptz)) from auth.sessions s where s.user_id = u.id))), '{}'::jsonb)
    from auth.users u
$$;
comment on function public.svc_admin_access_last_active() is 'CF-247 22 Oct 2026: each user''s last activity (latest of sign-in and session refresh), for Users & roles. Service role only.';
revoke all on function public.svc_admin_access_last_active() from public, anon, authenticated;
grant execute on function public.svc_admin_access_last_active() to service_role;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.svc_admin_access_last_active', 'Administration', 'Last activity per user for Users & roles', 'active', '{}', '20261022017000')
on conflict (kind, name) do nothing;
