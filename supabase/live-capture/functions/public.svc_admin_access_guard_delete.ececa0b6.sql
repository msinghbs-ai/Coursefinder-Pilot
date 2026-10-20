CREATE OR REPLACE FUNCTION public.svc_admin_access_guard_delete(p_actor_user_id uuid, p_target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth', 'pipeline', 'workflow'
AS $function$
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
end $function$
