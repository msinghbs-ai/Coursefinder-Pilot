-- CF-247 Users & roles › Links & Email Templates: email delivery provider (Platform Admin 17 Nov 2026 16:24, S1-RM-Design). Invitations and password
-- resets sent from the Admin can go through Resend with the sender name StudySearch PIM Admin instead of Supabase's built-in mail service.
--   * The provider, sender name and from address are one row in pipeline.environment_settings (key admin_email_delivery).
--   * The Resend API key is write-only: it is stored in Supabase Vault (name admin_resend_api_key), is returned only to the service role
--     (admin-user-management), and never to a signed-in user, the control log or the settings row. The row keeps its last four characters as a hint.
--   * Read and save are the Platform Admin's (rank 6); a save needs a reason and writes pipeline.admin_control_events.
-- Nothing here sends email. G1: no job. G2: the values are settings; the only numbers in code are input-safety bounds (marked fixed).
-- G3: no consumer API object is touched.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $$ begin
  if to_regclass('pipeline.environment_settings') is null or to_regclass('pipeline.admin_control_events') is null
     or to_regprocedure('security.current_role_rank()') is null or to_regclass('vault.decrypted_secrets') is null
     or not exists (select 1 from pg_proc p where p.pronamespace = 'vault'::regnamespace and p.proname = 'create_secret')
     or not exists (select 1 from pg_proc p where p.pronamespace = 'vault'::regnamespace and p.proname = 'update_secret') then
    raise exception 'an object this change builds on is missing';
  end if;
end $$;

-- the delivery settings in force (never the key)
create or replace function security.admin_email_delivery_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r record; s jsonb; v_saved boolean;
begin
  select e.setting_value, e.updated_at, e.updated_by into r from pipeline.environment_settings e where e.setting_key = 'admin_email_delivery';
  s := coalesce(r.setting_value, '{}'::jsonb);
  select exists (select 1 from vault.decrypted_secrets d where d.name = 'admin_resend_api_key') into v_saved;
  return jsonb_build_object(
    'email_provider', case when s->>'email_provider' = 'resend' then 'resend' else 'supabase' end,
    'sender_name', coalesce(nullif(s->>'sender_name', ''), 'StudySearch PIM Admin'),
    'from_email', coalesce(s->>'from_email', ''),
    'key_saved', v_saved,
    'key_hint', case when v_saved then s->>'key_hint' end,
    'key_saved_at', case when v_saved then s->>'key_saved_at' end,
    'saved', r.setting_value is not null, 'updated_at', r.updated_at, 'updated_by', r.updated_by);
end $$;
revoke all on function security.admin_email_delivery_v1() from public, anon, authenticated;

create or replace function public.admin_email_delivery_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed for email delivery' using errcode = '42501'; end if;
  return jsonb_build_object('delivery', security.admin_email_delivery_v1(), 'providers', jsonb_build_array('supabase', 'resend'));
end $$;

create or replace function public.admin_email_delivery_save(p_payload jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); p jsonb := coalesce(p_payload, '{}'::jsonb); v_old jsonb := security.admin_email_delivery_v1();
        v_provider text; v_sender text; v_from text; v_key text; v_id uuid; v_value jsonb; v_changed text[] := '{}'; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed for email delivery' using errcode = '42501'; end if; -- fixed: who sends sign-in email is the Platform Admin's
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'the settings must be an object' using errcode = '22023'; end if;
  v_provider := coalesce(nullif(btrim(p->>'email_provider'), ''), v_old->>'email_provider');
  v_sender := btrim(coalesce(p->>'sender_name', v_old->>'sender_name'));
  v_from := lower(btrim(coalesce(p->>'from_email', v_old->>'from_email')));
  v_key := nullif(btrim(coalesce(p->>'resend_api_key', '')), '');
  if v_provider not in ('supabase', 'resend') then raise exception 'the provider is supabase or resend' using errcode = '22023'; end if;
  if v_sender = '' or length(v_sender) > 80 or v_sender ~ '[<>"\r\n]' then raise exception 'the sender name is 1 to 80 characters, without < > or quotes' using errcode = '22023'; end if; -- fixed: a display name
  if v_from <> '' and (length(v_from) > 254 or v_from !~ '^[^\s@<>"]+@[a-z0-9.-]+\.[a-z]{2,}$') then raise exception 'the from email is not an email address' using errcode = '22023'; end if; -- fixed: an address
  if v_provider = 'resend' and v_from = '' then raise exception 'Resend needs a from email on a domain verified in Resend' using errcode = '22023'; end if;
  -- the key is never echoed, in an error or anywhere else
  if v_key is not null and v_key !~ '^re_[A-Za-z0-9_-]{8,200}$' then raise exception 'the Resend API key must begin re_ and hold only letters, digits, _ and -' using errcode = '22023'; end if; -- fixed: the shape of a key
  if v_key is not null then
    select d.id into v_id from vault.decrypted_secrets d where d.name = 'admin_resend_api_key' limit 1;
    if v_id is null then
      perform vault.create_secret(v_key, 'admin_resend_api_key', 'Resend API key for Admin invitation and reset emails (Users & roles, Links & Email Templates)');
    else
      perform vault.update_secret(v_id, v_key);
    end if;
  end if;
  v_value := jsonb_build_object('email_provider', v_provider, 'sender_name', v_sender, 'from_email', v_from,
    'key_hint', case when v_key is not null then right(v_key, 4) else v_old->>'key_hint' end,
    'key_saved_at', case when v_key is not null then to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') else v_old->>'key_saved_at' end);
  select coalesce(array_agg(x), '{}') into v_changed from unnest(array['email_provider', 'sender_name', 'from_email']) x where v_value->>x is distinct from v_old->>x;
  if v_key is not null then v_changed := array_append(v_changed, 'resend_api_key'); end if;
  insert into pipeline.environment_settings(setting_key, category, display_name, setting_value, management_mode, environment_scope, required_for_production, status, description, updated_by, updated_at)
  values ('admin_email_delivery', 'auth', 'Admin email delivery provider', v_value, 'read_only', 'current', false, 'configured',
          'Who sends Admin invitations and password resets (Supabase built-in or Resend), the sender name and from address. Changed only on Users & roles › Links & Email Templates. The Resend API key is in Vault, never here.', auth.uid(), now())
  on conflict (setting_key) do update set setting_value = excluded.setting_value, status = 'configured', updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('access', 'email_delivery_save', 'admin_email_delivery', jsonb_build_object('reason', v_reason, 'changed', to_jsonb(v_changed),
          'email_provider', v_provider, 'sender_name', v_sender, 'from_email', v_from, 'key_replaced', v_key is not null), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'changed', to_jsonb(v_changed), 'key_replaced', v_key is not null, 'event_id', v_ev, 'delivery', security.admin_email_delivery_v1());
end $$;

-- for admin-user-management (service role) only: the settings and the key
create or replace function public.svc_admin_email_delivery() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  return security.admin_email_delivery_v1()
    || jsonb_build_object('resend_api_key', (select d.decrypted_secret from vault.decrypted_secrets d where d.name = 'admin_resend_api_key' limit 1));
end $$;

revoke all on function public.admin_email_delivery_read() from public, anon;
revoke all on function public.admin_email_delivery_save(jsonb, text) from public, anon;
revoke all on function public.svc_admin_email_delivery() from public, anon, authenticated;
grant execute on function public.admin_email_delivery_read() to authenticated, service_role;
grant execute on function public.admin_email_delivery_save(jsonb, text) to authenticated, service_role;
grant execute on function public.svc_admin_email_delivery() to service_role;

-- Post-check
do $$ declare d jsonb := security.admin_email_delivery_v1(); begin
  if d->>'sender_name' is null or d ? 'resend_api_key' or has_function_privilege('authenticated', 'public.svc_admin_email_delivery()', 'execute') then
    raise exception 'post-check: email delivery';
  end if;
end $$;
