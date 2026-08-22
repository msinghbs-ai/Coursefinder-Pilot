create table if not exists security.user_access_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('user_created','user_invited','roles_replaced','user_disabled','user_enabled')),
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists user_access_events_target_created_idx
  on security.user_access_events(target_user_id, created_at desc);
create index if not exists user_access_events_actor_created_idx
  on security.user_access_events(actor_user_id, created_at desc);

alter table security.user_access_events enable row level security;
revoke all on security.user_access_events from public, anon, authenticated;
grant select, insert on security.user_access_events to service_role;

create or replace function public.svc_admin_access_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_result jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service role required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'roles', coalesce((select jsonb_agg(jsonb_build_object('code',r.code,'name',r.name,'rank',r.rank,'description',r.description,'status',r.status) order by r.rank) from security.roles r where r.status='active'),'[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object('user_id',ur.user_id,'role_code',ur.role_code,'role_name',r.name,'rank',r.rank,'granted_at',ur.granted_at,'granted_by',ur.granted_by,'expires_at',ur.expires_at) order by ur.user_id,r.rank) from security.user_roles ur join security.roles r on r.code=ur.role_code),'[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from (select id,actor_user_id,target_user_id,action,before_state,after_state,metadata,created_at from security.user_access_events order by created_at desc limit 100)e),'[]'::jsonb)
  ) into v_result;
  return v_result;
end
$$;

create or replace function public.svc_admin_access_replace_roles(p_actor_user_id uuid,p_target_user_id uuid,p_role_codes text[],p_expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_roles text[];v_before jsonb;v_after jsonb;v_other_platform_admins integer:=0;v_target_is_platform_admin boolean:=false;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if not exists (select 1 from security.user_roles ur join security.roles r on r.code=ur.role_code join auth.users u on u.id=ur.user_id where ur.user_id=p_actor_user_id and r.code='platform_admin' and r.status='active' and (ur.expires_at is null or ur.expires_at>now()) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'active platform admin actor required' using errcode='42501'; end if;
  if not exists (select 1 from auth.users where id=p_target_user_id and deleted_at is null) then raise exception 'target user not found' using errcode='22023'; end if;
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)),'{}'::text[]) into v_roles from unnest(coalesce(p_role_codes,'{}'::text[]))x where btrim(coalesce(x,''))<>'';
  if cardinality(v_roles)=0 then raise exception 'at least one CourseFinder role is required' using errcode='22023'; end if;
  if exists (select 1 from unnest(v_roles)x left join security.roles r on r.code=x and r.status='active' where r.code is null) then raise exception 'unknown or inactive role code' using errcode='22023'; end if;
  if p_actor_user_id=p_target_user_id and not ('platform_admin'=any(v_roles)) then raise exception 'platform admin cannot remove own platform_admin role' using errcode='42501'; end if;
  if 'platform_admin'=any(v_roles) and p_expires_at is not null then raise exception 'platform_admin assignment cannot expire' using errcode='22023'; end if;
  select exists(select 1 from security.user_roles ur where ur.user_id=p_target_user_id and ur.role_code='platform_admin' and (ur.expires_at is null or ur.expires_at>now())) into v_target_is_platform_admin;
  if v_target_is_platform_admin and not ('platform_admin'=any(v_roles)) then
    select count(distinct ur.user_id)::integer into v_other_platform_admins from security.user_roles ur join security.roles r on r.code=ur.role_code join auth.users u on u.id=ur.user_id where ur.user_id<>p_target_user_id and ur.role_code='platform_admin' and r.status='active' and (ur.expires_at is null or ur.expires_at>now()) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
    if v_other_platform_admins=0 then raise exception 'cannot remove the last active platform admin' using errcode='42501'; end if;
  end if;
  select jsonb_build_object('roles',coalesce(jsonb_agg(jsonb_build_object('code',ur.role_code,'expires_at',ur.expires_at) order by r.rank),'[]'::jsonb)) into v_before from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_target_user_id;
  v_before:=coalesce(v_before,jsonb_build_object('roles','[]'::jsonb));
  delete from security.user_roles where user_id=p_target_user_id;
  insert into security.user_roles(user_id,role_code,granted_by,expires_at) select p_target_user_id,x,p_actor_user_id,p_expires_at from unnest(v_roles)x;
  select jsonb_build_object('roles',coalesce(jsonb_agg(jsonb_build_object('code',ur.role_code,'expires_at',ur.expires_at) order by r.rank),'[]'::jsonb)) into v_after from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_target_user_id;
  v_after:=coalesce(v_after,jsonb_build_object('roles','[]'::jsonb));
  insert into security.user_access_events(actor_user_id,target_user_id,action,before_state,after_state) values(p_actor_user_id,p_target_user_id,'roles_replaced',v_before,v_after);
  return v_after;
end
$$;

create or replace function public.svc_admin_access_guard_disable(p_actor_user_id uuid,p_target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_other_platform_admins integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if not exists (select 1 from security.user_roles ur join security.roles r on r.code=ur.role_code join auth.users u on u.id=ur.user_id where ur.user_id=p_actor_user_id and r.code='platform_admin' and r.status='active' and (ur.expires_at is null or ur.expires_at>now()) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'active platform admin actor required' using errcode='42501'; end if;
  if p_actor_user_id=p_target_user_id then raise exception 'platform admin cannot disable own account' using errcode='42501'; end if;
  if not exists (select 1 from auth.users where id=p_target_user_id and deleted_at is null) then raise exception 'target user not found' using errcode='22023'; end if;
  if exists (select 1 from security.user_roles ur where ur.user_id=p_target_user_id and ur.role_code='platform_admin' and (ur.expires_at is null or ur.expires_at>now())) then
    select count(distinct ur.user_id)::integer into v_other_platform_admins from security.user_roles ur join security.roles r on r.code=ur.role_code join auth.users u on u.id=ur.user_id where ur.user_id<>p_target_user_id and ur.role_code='platform_admin' and r.status='active' and (ur.expires_at is null or ur.expires_at>now()) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
    if v_other_platform_admins=0 then raise exception 'cannot disable the last active platform admin' using errcode='42501'; end if;
  end if;
  return jsonb_build_object('allowed',true,'target_user_id',p_target_user_id);
end
$$;

create or replace function public.svc_admin_access_log_event(p_actor_user_id uuid,p_target_user_id uuid,p_action text,p_before_state jsonb default '{}'::jsonb,p_after_state jsonb default '{}'::jsonb,p_metadata jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_id uuid;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  if not exists (select 1 from security.user_roles ur join security.roles r on r.code=ur.role_code join auth.users u on u.id=ur.user_id where ur.user_id=p_actor_user_id and r.code='platform_admin' and r.status='active' and (ur.expires_at is null or ur.expires_at>now()) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'active platform admin actor required' using errcode='42501'; end if;
  if p_action not in ('user_created','user_invited','roles_replaced','user_disabled','user_enabled') then raise exception 'unsupported access audit action' using errcode='22023'; end if;
  insert into security.user_access_events(actor_user_id,target_user_id,action,before_state,after_state,metadata) values(p_actor_user_id,p_target_user_id,p_action,coalesce(p_before_state,'{}'::jsonb),coalesce(p_after_state,'{}'::jsonb),(coalesce(p_metadata,'{}'::jsonb)-'password'-'token'-'access_token'-'refresh_token')) returning id into v_id;
  return v_id;
end
$$;

revoke all on function public.svc_admin_access_snapshot() from public,anon,authenticated;
revoke all on function public.svc_admin_access_replace_roles(uuid,uuid,text[],timestamptz) from public,anon,authenticated;
revoke all on function public.svc_admin_access_guard_disable(uuid,uuid) from public,anon,authenticated;
revoke all on function public.svc_admin_access_log_event(uuid,uuid,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.svc_admin_access_snapshot() to service_role;
grant execute on function public.svc_admin_access_replace_roles(uuid,uuid,text[],timestamptz) to service_role;
grant execute on function public.svc_admin_access_guard_disable(uuid,uuid) to service_role;
grant execute on function public.svc_admin_access_log_event(uuid,uuid,text,jsonb,jsonb,jsonb) to service_role;
