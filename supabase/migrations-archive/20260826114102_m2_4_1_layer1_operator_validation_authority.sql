create or replace function public.svc_layer1_authorize_operator(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'security','public'
as $function$
  select exists (
    select 1
    from security.user_roles ur
    join security.roles r on r.code = ur.role_code
    where ur.user_id = p_user_id
      and r.status = 'active'
      and r.rank >= 4
      and (ur.expires_at is null or ur.expires_at > now())
  );
$function$;

revoke all on function public.svc_layer1_authorize_operator(uuid) from public, anon, authenticated;
grant execute on function public.svc_layer1_authorize_operator(uuid) to service_role;
comment on function public.svc_layer1_authorize_operator(uuid) is 'M2.4.1 service-only authority check for non-destructive Layer 1 operator actions such as authoritative source validation. Rank >=4; browser cannot execute directly.';