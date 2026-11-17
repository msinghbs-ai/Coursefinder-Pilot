-- CF-247 Go-live checklist: custom SMTP for Supabase Auth (Platform Admin 17 Nov 2026 16:13, S1-RM-Design). Supabase's built-in mail service sends
-- as "Supabase Auth" and is for testing only. Production sends the invitation and reset emails through Resend with the sender name
-- StudySearch PIM Admin. This adds the step to the Go-live checklist (pipeline.environment_settings); it configures nothing and holds no secret.
-- Scope and steps: admin repo docs/platform/SUPABASE-AUTH-CUSTOM-SMTP-RESEND-SCOPE.md.
-- G1: no job. G2: no operational value in code. G3: no consumer API object is touched.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $$ begin
  if to_regclass('pipeline.environment_settings') is null then raise exception 'pipeline.environment_settings is missing'; end if;
end $$;

insert into pipeline.environment_settings(setting_key, category, display_name, setting_value, management_mode, environment_scope, required_for_production, status, description)
values ('auth_custom_smtp', 'auth', 'Auth custom SMTP (Resend)', null, 'deployment_managed', 'production', true, 'pending',
        'Send Supabase Auth emails through Resend (smtp.resend.com, port 465, user resend) from a verified sending domain, sender name StudySearch PIM Admin. DNS records first, then SMTP in Supabase Auth, then a test invitation and reset. The API key is a secret: never stored here.')
on conflict (setting_key) do nothing;

do $$ begin
  if (select count(*) from pipeline.environment_settings where setting_key = 'auth_custom_smtp' and required_for_production) <> 1 then
    raise exception 'post-check: auth_custom_smtp';
  end if;
end $$;
