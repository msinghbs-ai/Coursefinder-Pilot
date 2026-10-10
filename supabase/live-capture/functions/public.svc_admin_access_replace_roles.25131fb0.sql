CREATE OR REPLACE FUNCTION public.svc_admin_access_replace_roles(p_actor_user_id uuid, p_target_user_id uuid, p_role_codes text[], p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare
  v_roles text[];
  v_before jsonb;
  v_after jsonb;
  v_other_platform_admins integer := 0;
  v_target_is_platform_admin boolean := false;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from security.user_roles ur
    join security.roles r on r.code=ur.role_code
    join auth.users u on u.id=ur.user_id
    where ur.user_id=p_actor_user_id
      and r.code='platform_admin' and r.status='active'
      and (ur.expires_at is null or ur.expires_at>now())
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now())
  ) then
    raise exception 'active platform admin actor required' using errcode='42501';
  end if;

  if not exists (select 1 from auth.users where id=p_target_user_id and deleted_at is null) then
    raise exception 'target user not found' using errcode='22023';
  end if;

  select coalesce(array_agg(distinct btrim(x) order by btrim(x)), '{}'::text[])
  into v_roles
  from unnest(coalesce(p_role_codes,'{}'::text[])) x
  where btrim(coalesce(x,''))<>'';

  if cardinality(v_roles)=0 then
    raise exception 'at least one CourseFinder role is required' using errcode='22023';
  end if;

  if exists (
    select 1 from unnest(v_roles) x
    left join security.roles r on r.code=x and r.status='active'
    where r.code is null
  ) then
    raise exception 'unknown or inactive role code' using errcode='22023';
  end if;

  if p_actor_user_id=p_target_user_id and not ('platform_admin'=any(v_roles)) then
    raise exception 'platform admin cannot remove own platform_admin role' using errcode='42501';
  end if;

  if 'platform_admin'=any(v_roles) and p_expires_at is not null then
    raise exception 'platform_admin assignment cannot expire' using errcode='22023';
  end if;

  select exists (
    select 1 from security.user_roles ur
    where ur.user_id=p_target_user_id and ur.role_code='platform_admin'
      and (ur.expires_at is null or ur.expires_at>now())
  ) into v_target_is_platform_admin;

  if v_target_is_platform_admin and not ('platform_admin'=any(v_roles)) then
    select count(distinct ur.user_id)::integer into v_other_platform_admins
    from security.user_roles ur
    join security.roles r on r.code=ur.role_code
    join auth.users u on u.id=ur.user_id
    where ur.user_id<>p_target_user_id
      and ur.role_code='platform_admin' and r.status='active'
      and (ur.expires_at is null or ur.expires_at>now())
      and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now());
    if v_other_platform_admins=0 then
      raise exception 'cannot remove the last active platform admin' using errcode='42501';
    end if;
  end if;

  select jsonb_build_object(
    'roles',coalesce(jsonb_agg(jsonb_build_object('code',ur.role_code,'expires_at',ur.expires_at) order by r.rank),'[]'::jsonb)
  ) into v_before
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_target_user_id;
  v_before:=coalesce(v_before,jsonb_build_object('roles','[]'::jsonb));

  delete from security.user_roles where user_id=p_target_user_id;

  insert into security.user_roles(user_id,role_code,granted_by,expires_at)
  select p_target_user_id,x,p_actor_user_id,p_expires_at
  from unnest(v_roles) x;

  select jsonb_build_object(
    'roles',coalesce(jsonb_agg(jsonb_build_object('code',ur.role_code,'expires_at',ur.expires_at) order by r.rank),'[]'::jsonb)
  ) into v_after
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_target_user_id;
  v_after:=coalesce(v_after,jsonb_build_object('roles','[]'::jsonb));

  insert into security.user_access_events(actor_user_id,target_user_id,action,before_state,after_state)
  values(p_actor_user_id,p_target_user_id,'roles_replaced',v_before,v_after);

  return v_after;
end
$function$
