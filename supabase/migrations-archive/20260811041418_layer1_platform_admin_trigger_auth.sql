create or replace function public.svc_layer1_authorize_platform_admin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = security, public
as $$
  select exists (
    select 1
    from security.user_roles ur
    join security.roles r on r.code = ur.role_code
    where ur.user_id = p_user_id
      and r.status = 'active'
      and r.rank >= 6
      and (ur.expires_at is null or ur.expires_at > now())
  );
$$;

revoke all on function public.svc_layer1_authorize_platform_admin(uuid) from public, anon, authenticated;
grant execute on function public.svc_layer1_authorize_platform_admin(uuid) to service_role;
