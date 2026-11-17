-- CF-247 Users & roles › Links & Email Templates (Platform Admin 17 Nov 2026 14:40, S1-RM-Design): the Admin site address, the guide link and the
-- Invite user and Reset password email templates are settings a Platform Admin edits in the Admin, saved with a reason. They are stored in the
-- existing pipeline.environment_settings table (one row, key admin_auth_email_templates) and read by admin-user-management, which copies them to
-- Supabase Auth when a management token is configured. Tokens a template may use: {{link}}, {{guide_link}}, {{user_email}}, {{user_name}},
-- {{role}}. Nothing here sends email; no Auth setting is changed by this migration.
-- G1: no job. G2: the values are settings; the only numbers in code are input-safety bounds on a subject and a body (marked fixed).
-- G3: no consumer API object is touched.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $$ begin
  if to_regclass('pipeline.environment_settings') is null or to_regclass('pipeline.admin_control_events') is null
     or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $$;

-- the defaults: the branded StudySearch PIM Admin emails (accent #0b6e5f)
create or replace function security.admin_auth_template_defaults_v1() returns jsonb
language sql immutable set search_path = '' as $fn$
  select jsonb_build_object(
    'site_url', 'https://coursefinder-pilot.techm.workers.dev',
    'guide_link', 'https://coursefinder-pilot.techm.workers.dev/#platform-guide',
    'templates', jsonb_build_object(
      'invite', jsonb_build_object(
        'subject', 'You''re invited to StudySearch PIM Admin',
        'body', $html$<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#18211d">
  <div style="background:#0b6e5f;color:#ffffff;padding:18px 24px;border-radius:8px 8px 0 0">
    <strong style="font-size:18px">StudySearch PIM Admin</strong>
  </div>
  <div style="border:1px solid #d6ddd9;border-top:0;padding:24px;border-radius:0 0 8px 8px">
    <h2 style="margin:0 0 4px;color:#0b6e5f">Welcome, {{user_name}}</h2>
    <p style="margin:0 0 16px;color:#5d6b64">{{user_email}}</p>
    <p>You have been given access to StudySearch PIM Admin as <strong>{{role}}</strong>.</p>
    <p style="margin:24px 0"><a href="{{link}}" style="background:#0b6e5f;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:6px;font-weight:bold">Accept the invitation</a></p>
    <p style="font-size:13px;color:#5d6b64">The button opens the Admin sign-in, where you choose a password of 12 characters or more. If the button does not work, copy this address into your browser:<br>{{link}}</p>
    <p>New to the platform? Read the <a href="{{guide_link}}" style="color:#0b6e5f">Platform guide</a> after you sign in.</p>
    <p style="font-size:12px;color:#5d6b64;margin-top:24px">If you were not expecting this invitation, you can ignore this email.</p>
  </div>
</div>$html$),
      'recovery', jsonb_build_object(
        'subject', 'Reset your StudySearch PIM Admin password',
        'body', $html$<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#18211d">
  <div style="background:#0b6e5f;color:#ffffff;padding:18px 24px;border-radius:8px 8px 0 0">
    <strong style="font-size:18px">StudySearch PIM Admin</strong>
  </div>
  <div style="border:1px solid #d6ddd9;border-top:0;padding:24px;border-radius:0 0 8px 8px">
    <h2 style="margin:0 0 4px;color:#0b6e5f">Reset your password</h2>
    <p style="margin:0 0 16px;color:#5d6b64">{{user_email}}</p>
    <p>Hello {{user_name}}, a password reset was requested for your StudySearch PIM Admin account ({{role}}).</p>
    <p style="margin:24px 0"><a href="{{link}}" style="background:#0b6e5f;color:#ffffff;text-decoration:none;padding:12px 20px;border-radius:6px;font-weight:bold">Choose a new password</a></p>
    <p style="font-size:13px;color:#5d6b64">Your current password keeps working until you choose a new one. If the button does not work, copy this address into your browser:<br>{{link}}</p>
    <p>The <a href="{{guide_link}}" style="color:#0b6e5f">Platform guide</a> explains each screen.</p>
    <p style="font-size:12px;color:#5d6b64;margin-top:24px">If you did not ask for this, you can ignore this email; nothing changes.</p>
  </div>
</div>$html$)))
$fn$;
revoke all on function security.admin_auth_template_defaults_v1() from public, anon, authenticated;

-- the settings in force: what is saved, over the defaults
create or replace function security.admin_auth_template_settings_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare d jsonb := security.admin_auth_template_defaults_v1(); s jsonb; r record;
begin
  select e.setting_value, e.updated_at, e.updated_by into r from pipeline.environment_settings e where e.setting_key = 'admin_auth_email_templates';
  s := coalesce(r.setting_value, '{}'::jsonb);
  return jsonb_build_object(
    'site_url', coalesce(nullif(s->>'site_url', ''), d->>'site_url'),
    'guide_link', coalesce(nullif(s->>'guide_link', ''), d->>'guide_link'),
    'templates', jsonb_build_object(
      'invite', jsonb_build_object('subject', coalesce(nullif(s#>>'{templates,invite,subject}', ''), d#>>'{templates,invite,subject}'),
                                   'body', coalesce(nullif(s#>>'{templates,invite,body}', ''), d#>>'{templates,invite,body}')),
      'recovery', jsonb_build_object('subject', coalesce(nullif(s#>>'{templates,recovery,subject}', ''), d#>>'{templates,recovery,subject}'),
                                     'body', coalesce(nullif(s#>>'{templates,recovery,body}', ''), d#>>'{templates,recovery,body}'))),
    'saved', r.setting_value is not null, 'updated_at', r.updated_at, 'updated_by', r.updated_by);
end $$;
revoke all on function security.admin_auth_template_settings_v1() from public, anon, authenticated;

create or replace function public.admin_auth_template_settings_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed for the email templates' using errcode = '42501'; end if;
  return jsonb_build_object('settings', security.admin_auth_template_settings_v1(), 'defaults', security.admin_auth_template_defaults_v1(),
    'tokens', jsonb_build_array('link', 'guide_link', 'user_email', 'user_name', 'role'),
    'last_events', coalesce((select jsonb_agg(jsonb_build_object('at', x.created_at, 'action', x.action, 'reason', x.detail->>'reason', 'synced', x.detail->'synced', 'note', x.detail->>'note') order by x.created_at desc)
                               from (select * from pipeline.admin_control_events e where e.area = 'access' and e.action in ('auth_templates_save', 'auth_templates_sync', 'auth_template_test')
                                      order by e.created_at desc limit 5) x), '[]'::jsonb));  -- fixed: the last five events are shown
end $$;

create or replace function public.admin_auth_template_settings_save(p_payload jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); p jsonb := coalesce(p_payload, '{}'::jsonb); v_old jsonb := security.admin_auth_template_settings_v1();
        v_new jsonb; k text; v_subject text; v_body text; v_tok text; v_changed text[] := '{}'; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed for the email templates' using errcode = '42501'; end if; -- fixed: who may sign in is the Platform Admin's
  if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;
  if jsonb_typeof(p) <> 'object' then raise exception 'the settings must be an object' using errcode = '22023'; end if;
  v_new := jsonb_build_object('site_url', regexp_replace(btrim(coalesce(p->>'site_url', v_old->>'site_url')), '/+$', ''),
                              'guide_link', btrim(coalesce(p->>'guide_link', v_old->>'guide_link')),
                              'templates', jsonb_build_object('invite', coalesce(p#>'{templates,invite}', v_old#>'{templates,invite}'),
                                                              'recovery', coalesce(p#>'{templates,recovery}', v_old#>'{templates,recovery}')));
  if v_new->>'site_url' !~ '^https://[a-z0-9.-]+(:[0-9]+)?(/[^\s<>"]*)?$' or v_new->>'site_url' ~* 'supabase\.co' then
    raise exception 'the Admin site URL must be an https address of the Admin site (not a supabase.co address)' using errcode = '22023';
  end if;
  if v_new->>'guide_link' !~ '^https://[^\s<>"]+$' then raise exception 'the Admin guide link must be an https address' using errcode = '22023'; end if;
  foreach k in array array['invite', 'recovery'] loop
    v_subject := btrim(coalesce(v_new#>>array['templates', k, 'subject'], '')); v_body := coalesce(v_new#>>array['templates', k, 'body'], '');
    if v_subject = '' or length(v_subject) > 200 or v_subject ~ '[\r\n]' then raise exception 'the % subject must be one line of 1 to 200 characters', k using errcode = '22023'; end if; -- fixed: a subject line
    if btrim(v_body) = '' or length(v_body) > 30000 then raise exception 'the % body must be 1 to 30,000 characters', k using errcode = '22023'; end if; -- fixed: input-safety bound on one email
    if position('{{link}}' in v_body) = 0 then raise exception 'the % body must contain {{link}}, or the person cannot sign in from the email', k using errcode = '22023'; end if;
    if v_body ~* '<\s*script' then raise exception 'the % body may not contain a script', k using errcode = '22023'; end if;
    for v_tok in select distinct m[1] from regexp_matches(v_subject || ' ' || v_body, '\{\{\s*([^{}]*?)\s*\}\}', 'g') m loop
      if v_tok not in ('link', 'guide_link', 'user_email', 'user_name', 'role') then
        raise exception 'unknown token {{%}} in the % template; use link, guide_link, user_email, user_name or role', v_tok, k using errcode = '22023';
      end if;
    end loop;
    v_new := jsonb_set(v_new, array['templates', k], jsonb_build_object('subject', v_subject, 'body', v_body));
  end loop;
  select array_agg(x) into v_changed from unnest(array['site_url', 'guide_link']) x where v_new->>x is distinct from v_old->>x;
  v_changed := coalesce(v_changed, '{}') || array(select t || '.' || f from unnest(array['invite', 'recovery']) t, unnest(array['subject', 'body']) f
                                                  where v_new#>>array['templates', t, f] is distinct from v_old#>>array['templates', t, f]);
  insert into pipeline.environment_settings(setting_key, category, display_name, setting_value, management_mode, environment_scope, required_for_production, status, description, updated_by, updated_at)
  values ('admin_auth_email_templates', 'auth', 'Admin links and email templates', v_new, 'read_only', 'current', false, 'configured',
          'Admin site URL, guide link and the Invite user and Reset password emails. Changed only on Users & roles › Links & Email Templates (read only on the Go-live checklist).', auth.uid(), now())
  on conflict (setting_key) do update set setting_value = excluded.setting_value, status = 'configured', updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('access', 'auth_templates_save', 'admin_auth_email_templates', jsonb_build_object('reason', v_reason, 'changed', to_jsonb(v_changed),
          'site_url', v_new->>'site_url', 'guide_link', v_new->>'guide_link',
          'invite_body_md5', md5(v_new#>>'{templates,invite,body}'), 'recovery_body_md5', md5(v_new#>>'{templates,recovery,body}')), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'changed', to_jsonb(v_changed), 'event_id', v_ev, 'settings', security.admin_auth_template_settings_v1());
end $$;

-- for admin-user-management (service role): the settings in force, and one line in the control log for a sync or a test
create or replace function public.svc_admin_auth_template_settings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  return security.admin_auth_template_settings_v1();
end $$;

create or replace function public.svc_admin_auth_template_log(p_actor uuid, p_action text, p_detail jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_ev bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if p_action not in ('auth_templates_sync', 'auth_template_test') then raise exception 'unsupported action' using errcode = '22023'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('access', p_action, 'admin_auth_email_templates', coalesce(p_detail, '{}'::jsonb) - 'token' - 'access_token' - 'password', p_actor) returning id into v_ev;
  return v_ev;
end $$;

revoke all on function public.admin_auth_template_settings_read() from public, anon;
revoke all on function public.admin_auth_template_settings_save(jsonb, text) from public, anon;
revoke all on function public.svc_admin_auth_template_settings() from public, anon, authenticated;
revoke all on function public.svc_admin_auth_template_log(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.admin_auth_template_settings_read() to authenticated, service_role;
grant execute on function public.admin_auth_template_settings_save(jsonb, text) to authenticated, service_role;
grant execute on function public.svc_admin_auth_template_settings() to service_role;
grant execute on function public.svc_admin_auth_template_log(uuid, text, jsonb) to service_role;

-- Post-check
do $$ declare d jsonb := security.admin_auth_template_settings_v1(); begin
  if d->>'site_url' !~ '^https://' or position('{{link}}' in d#>>'{templates,invite,body}') = 0 or position('{{link}}' in d#>>'{templates,recovery,body}') = 0
     or position('#0b6e5f' in d#>>'{templates,invite,body}') = 0 then
    raise exception 'post-check: default templates';
  end if;
end $$;
