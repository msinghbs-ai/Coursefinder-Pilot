-- CF-247 (16 Oct 2026): Users & roles can delete a user. Platform Admin 16 Oct 2026 15:25: "Platform Users - can't be deleted, only disabled
-- (only Platform admin should be able to delete the user from UI, Platform admins roles user can't be deleted form the UI".
-- Rules (checked in the database, not only on screen): the person deleting is an active Platform Admin; nobody deletes their own account;
-- a user who holds the Platform Admin role (current or expired) cannot be deleted from the screen; the system automation account
-- (an address ending .invalid) cannot be deleted.
-- A user with no recorded work is removed completely. A user whose id is on recorded work (jobs, roles they granted, reviews) is
-- soft-deleted by Supabase Auth: they can no longer sign in and leave the user list, and the work keeps its history. Either way the
-- user's roles end at once and the deletion is recorded in security.user_deletions (email, roles, how, who, when).
-- Replaces: nothing (disable stays as it was)
-- Retires: nothing
-- Nothing dropped or deleted.

create table if not exists security.user_deletions (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor_user_id uuid not null,
  target_user_id uuid not null,
  email text,
  roles jsonb not null default '[]'::jsonb,
  mode text not null check (mode in ('removed', 'soft_deleted')),
  note text);
comment on table security.user_deletions is 'CF-247 16 Oct 2026: users deleted from Users & roles by a Platform Admin: who, when, the email and roles the user had, and whether Supabase Auth removed the user or soft-deleted them (kept because recorded work names them). No password or token is kept.';
alter table security.user_deletions enable row level security;
revoke all on security.user_deletions from public, anon, authenticated;

create or replace function public.svc_admin_access_guard_delete(p_actor_user_id uuid, p_target_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = 'pg_catalog', 'security', 'auth', 'pipeline', 'workflow' as $function$
declare v_email text; v_refs bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if not exists (
    select 1 from security.user_roles ur join security.roles r on r.code = ur.role_code join auth.users u on u.id = ur.user_id
     where ur.user_id = p_actor_user_id and r.code = 'platform_admin' and r.status = 'active' and (ur.expires_at is null or ur.expires_at > now())
       and u.deleted_at is null and (u.banned_until is null or u.banned_until <= now())) then
    raise exception 'active platform admin actor required' using errcode = '42501';
  end if;
  if p_actor_user_id = p_target_user_id then raise exception 'you cannot delete your own account' using errcode = '42501'; end if;
  select email into v_email from auth.users where id = p_target_user_id and deleted_at is null;
  if not found then raise exception 'target user not found' using errcode = '22023'; end if;
  if exists (select 1 from security.user_roles ur where ur.user_id = p_target_user_id and ur.role_code = 'platform_admin') then
    raise exception 'a platform admin cannot be deleted from the screen' using errcode = '42501';
  end if;
  if coalesce(v_email, '') like '%.invalid' then raise exception 'the system automation account cannot be deleted' using errcode = '42501'; end if;
  -- recorded work that names the user: then Supabase Auth soft-deletes them so the history keeps its link
  select (select count(*) from pipeline.jobs where requested_by = p_target_user_id)
       + (select count(*) from security.user_roles where granted_by = p_target_user_id)
       + (select count(*) from workflow.review_queue where assigned_to = p_target_user_id)
       + (select count(*) from workflow.review_actions where actor_id = p_target_user_id)
       + (select count(*) from workflow.suggestions where submitted_by = p_target_user_id)
       + (select count(*) from workflow.import_jobs where requested_by = p_target_user_id)
       + (select count(*) from workflow.export_jobs where requested_by = p_target_user_id)
       + (select count(*) from workflow.handover_events where recorded_by = p_target_user_id)
    into v_refs;
  return jsonb_build_object('allowed', true, 'target_user_id', p_target_user_id, 'email', v_email, 'soft', v_refs > 0, 'references', v_refs,
    'roles', (select coalesce(jsonb_agg(jsonb_build_object('role_code', ur.role_code, 'expires_at', ur.expires_at)), '[]'::jsonb) from security.user_roles ur where ur.user_id = p_target_user_id));
end $function$;

create or replace function public.svc_admin_access_record_delete(p_actor_user_id uuid, p_target_user_id uuid, p_email text, p_roles jsonb, p_mode text)
returns jsonb language plpgsql security definer set search_path = 'pg_catalog', 'security', 'auth' as $function$
declare v_id bigint; v_ended int := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if p_mode not in ('removed', 'soft_deleted') then raise exception 'unsupported deletion mode' using errcode = '22023'; end if;
  -- a soft-deleted user keeps role rows (history) but every role ends now; a removed user's roles went with the account
  update security.user_roles set expires_at = now() where user_id = p_target_user_id and (expires_at is null or expires_at > now());
  get diagnostics v_ended = row_count;
  insert into security.user_deletions(actor_user_id, target_user_id, email, roles, mode)
  values (p_actor_user_id, p_target_user_id, p_email, coalesce(p_roles, '[]'::jsonb), p_mode) returning id into v_id;
  return jsonb_build_object('id', v_id, 'roles_ended', v_ended);
end $function$;

create or replace function public.svc_admin_access_deleted()
returns jsonb language plpgsql stable security definer set search_path = 'pg_catalog', 'security', 'auth' as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'ids', (select coalesce(jsonb_agg(distinct d.target_user_id), '[]'::jsonb) from security.user_deletions d),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', d.at, 'email', d.email, 'mode', d.mode, 'roles', d.roles,
                  'actor_email', (select u.email from auth.users u where u.id = d.actor_user_id)) order by d.at desc), '[]'::jsonb)
               from (select * from security.user_deletions order by at desc limit 20) d));  -- fixed: the screen's latest deletions
end $function$;

revoke execute on function public.svc_admin_access_guard_delete(uuid, uuid), public.svc_admin_access_record_delete(uuid, uuid, text, jsonb, text),
  public.svc_admin_access_deleted() from public, anon, authenticated;
grant execute on function public.svc_admin_access_guard_delete(uuid, uuid), public.svc_admin_access_record_delete(uuid, uuid, text, jsonb, text),
  public.svc_admin_access_deleted() to service_role;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'security.user_deletions', 'Access', 'Users deleted from Users & roles (who, when, email, roles, removed or soft-deleted)', 'active', '20261016080000')
on conflict (kind, name) do nothing;
