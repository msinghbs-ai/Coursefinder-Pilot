#!/usr/bin/env bash
# Guards: Users & roles › Links & Email Templates (Platform Admin 17 Nov 2026 14:40) and G4 database-backed tests: migration 20261117152700 runs on an
# isolated PostgreSQL 16 (fixtures only, never a Supabase project). It proves: the migration applies twice; reading and saving are the Platform Admin's;
# a save needs a reason and is written to the control log; a template must keep {{link}}, use only the five tokens and carry no script; the defaults
# stay in force for anything not saved; the service functions are the service role's only.
# Needs a scratch PostgreSQL 16: PGHOST/PGPORT/PGUSER point at it. Drops its database at the end (AET_KEEP=1 keeps it).
set -euo pipefail
cd "$(dirname "$0")/../../.."
DB=${AET_DB:-g_admin_auth_email_templates}
case "$DB" in g_*) ;; *) echo "database name must begin g_" >&2; exit 1;; esac
P="psql -v ON_ERROR_STOP=1 -q -X -d $DB"
M=supabase/migrations/20261117152700_cf247_admin_auth_email_templates.sql
trap '[ -n "${AET_KEEP:-}" ] || dropdb --if-exists '$DB' >/dev/null 2>&1' EXIT
dropdb --if-exists $DB >/dev/null 2>&1; createdb $DB
psql -X -q -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if; if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if; if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if; end \$\$"
$P <<'SQL'
create schema pipeline; create schema security; create schema auth;
create table pipeline.environment_settings (setting_key text primary key, category text not null, display_name text not null, setting_value jsonb, management_mode text not null,
  environment_scope text not null, required_for_production boolean not null, status text not null, description text, updated_by uuid, updated_at timestamptz not null default now());
create table pipeline.admin_control_events (id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}', actor uuid, created_at timestamptz not null default now());
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fixture.uid', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('fixture.role', true), '') $$;
create schema vault;
create table vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, description text, secret text);
create view vault.decrypted_secrets as select id, name, description, secret, secret as decrypted_secret from vault.secrets;
create function vault.create_secret(new_secret text, new_name text default null, new_description text default '', new_key_id uuid default null) returns uuid language sql as $$ insert into vault.secrets(name, description, secret) values (new_name, new_description, new_secret) returning id $$;
create function vault.update_secret(secret_id uuid, new_secret text default null, new_name text default null, new_description text default null, new_key_id uuid default null) returns void language sql as $$ update vault.secrets set secret = coalesce(new_secret, secret) where id = secret_id $$;
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fixture.rank', true), '')::int $$;
SQL
$P -1 -f $M >/dev/null; $P -1 -f $M >/dev/null
G=supabase/migrations/20261117163000_cf247_golive_auth_custom_smtp.sql
$P -1 -f $G >/dev/null; $P -1 -f $G >/dev/null
D=supabase/migrations/20261117170000_cf247_admin_email_delivery_resend.sql
$P -1 -f $D >/dev/null; $P -1 -f $D >/dev/null
echo "migrations: each applied twice without error (post-checks included)"
$P <<'SQL'
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return null; exception when others then return sqlerrm; end $$;
do $t$ declare r jsonb; m text; b text; begin
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_read()$$) = 'authentication required', 'no session: refused');
  perform set_config('fixture.uid', '33333333-3333-3333-3333-333333333333', true); perform set_config('fixture.rank', '5', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_read()$$) like 'Platform Admin (rank 6)%' and pg_temp.err($$select public.admin_auth_template_settings_save('{}', 'x')$$) like 'Platform Admin (rank 6)%', 'a Pipeline Operator can neither read nor save');
  perform set_config('fixture.rank', '6', true);
  r := public.admin_auth_template_settings_read();
  perform pg_temp.ok(r->'settings'->>'site_url' = 'https://coursefinder-pilot.techm.workers.dev' and not (r->'settings'->>'saved')::boolean and r->'tokens' = '["link","guide_link","user_email","user_name","role"]'::jsonb
    and r#>>'{settings,templates,invite,body}' like '%#0b6e5f%' and r#>>'{settings,templates,recovery,subject}' = 'Reset your StudySearch PIM Admin password', 'before any save the branded defaults are in force, with the five tokens');
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_save('{"site_url":"https://admin.example.org"}', '  ')$$) = 'a reason is required', 'a save needs a reason');
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_save('{"site_url":"http://admin.example.org"}', 'x')$$) like 'the Admin site URL must be an https address%'
    and pg_temp.err($$select public.admin_auth_template_settings_save('{"site_url":"https://abc.supabase.co"}', 'x')$$) like 'the Admin site URL must be an https address%', 'the site URL is https and never a supabase.co address');
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_save('{"templates":{"invite":{"subject":"Hi","body":"<p>no link</p>"}}}', 'x')$$) like 'the invite body must contain {{link}}%', 'a body without {{link}} is refused');
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_save('{"templates":{"recovery":{"subject":"Hi","body":"<a href=\"{{link}}\">x</a> {{ .Token }}"}}}', 'x')$$) like 'unknown token {{.Token}} in the recovery template%', 'a token outside the five is refused');
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_save('{"templates":{"invite":{"subject":"Hi","body":"{{link}}<script>x</script>"}}}', 'x')$$) like 'the invite body may not contain a script', 'a script is refused');
  perform pg_temp.ok(pg_temp.err($$select public.admin_auth_template_settings_save('{"templates":{"invite":{"subject":"two\nlines","body":"{{link}}"}}}', 'x')$$) like 'the invite subject must be one line%', 'a subject is one line');
  r := public.admin_auth_template_settings_save('{"site_url":"https://admin.studysearch.example/","templates":{"invite":{"subject":"Welcome {{ user_name }}","body":"<p>{{user_name}}, <a href=\"{{link}}\">join</a> as {{role}}. {{guide_link}} {{user_email}}</p>"}}}', 'new domain');
  perform pg_temp.ok((r->>'ok')::boolean and r->'changed' @> '["site_url","invite.subject","invite.body"]'::jsonb and not r->'changed' @> '["recovery.body"]'::jsonb
    and r#>>'{settings,site_url}' = 'https://admin.studysearch.example' and r#>>'{settings,templates,recovery,body}' like '%#0b6e5f%' and (r#>>'{settings,saved}')::boolean,
    'a save keeps what was sent, trims the trailing slash, names what changed, and leaves the other template on its default');
  perform pg_temp.ok((select count(*) from pipeline.admin_control_events where area = 'access' and action = 'auth_templates_save' and detail->>'reason' = 'new domain' and actor = '33333333-3333-3333-3333-333333333333'
    and detail ? 'invite_body_md5' and not detail::text like '%join%') = 1, 'the save is in the control log with its reason and a checksum, not the email body');
  perform pg_temp.ok((select count(*) from pipeline.environment_settings where setting_key = 'admin_auth_email_templates' and category = 'auth' and management_mode = 'read_only') = 1, 'one row in the existing settings table');
  r := public.admin_auth_template_settings_save(public.admin_auth_template_settings_read()->'defaults', 'back to default');
  perform pg_temp.ok(r#>>'{settings,site_url}' = 'https://coursefinder-pilot.techm.workers.dev' and jsonb_array_length(public.admin_auth_template_settings_read()->'last_events') = 2, 'saving the defaults resets everything; the last events are listed');
  perform pg_temp.ok((select count(*) from pipeline.environment_settings where setting_key = 'auth_custom_smtp' and category = 'auth' and management_mode = 'deployment_managed' and environment_scope = 'production' and required_for_production and status = 'pending' and setting_value is null) = 1, 'Go-live checklist: custom SMTP (Resend) is one pending deployment step with no value stored');
  perform pg_temp.ok(pg_temp.err($$select public.svc_admin_auth_template_settings()$$) = 'service role required', 'the service read is refused to a signed-in user');
  perform set_config('fixture.role', 'service_role', true);
  perform public.svc_admin_auth_template_log('33333333-3333-3333-3333-333333333333', 'auth_templates_sync', '{"synced":true,"token":"secret"}');
  perform pg_temp.ok(public.svc_admin_auth_template_settings() ? 'templates'
    and (select not detail ? 'token' and (detail->>'synced')::boolean from pipeline.admin_control_events where action = 'auth_templates_sync') and pg_temp.err($$select public.svc_admin_auth_template_log(null, 'other', '{}')$$) = 'unsupported action',
    'the service role reads the settings and logs a sync; a token never reaches the log');
  -- email delivery provider (migration 20261117170000)
  perform set_config('fixture.role', '', true); perform set_config('fixture.rank', '5', true);
  perform pg_temp.ok(pg_temp.err($$select public.admin_email_delivery_read()$$) like 'Platform Admin (rank 6)%' and pg_temp.err($$select public.admin_email_delivery_save('{}', 'x')$$) like 'Platform Admin (rank 6)%', 'email delivery: a Pipeline Operator can neither read nor save');
  perform set_config('fixture.rank', '6', true);
  r := public.admin_email_delivery_read();
  perform pg_temp.ok(r#>>'{delivery,email_provider}' = 'supabase' and r#>>'{delivery,sender_name}' = 'StudySearch PIM Admin' and not (r#>>'{delivery,key_saved}')::boolean and r#>>'{delivery,key_hint}' is null, 'email delivery: built-in by default, sender name StudySearch PIM Admin, no key');
  perform pg_temp.ok(pg_temp.err($$select public.admin_email_delivery_save('{"email_provider":"resend","from_email":"noreply@example.org"}', ' ')$$) = 'a reason is required'
    and pg_temp.err($$select public.admin_email_delivery_save('{"email_provider":"resend"}', 'x')$$) like 'Resend needs a from email%'
    and pg_temp.err($$select public.admin_email_delivery_save('{"email_provider":"smtp"}', 'x')$$) = 'the provider is supabase or resend'
    and pg_temp.err($$select public.admin_email_delivery_save('{"from_email":"not an address"}', 'x')$$) = 'the from email is not an email address'
    and pg_temp.err($$select public.admin_email_delivery_save('{"sender_name":"A <b>"}', 'x')$$) like 'the sender name is 1 to 80 characters%', 'email delivery: a save needs a reason, a known provider, a from email for Resend and a plain sender name');
  m := pg_temp.err($$select public.admin_email_delivery_save('{"resend_api_key":"sk_wrongshape_SECRETVALUE"}', 'x')$$);
  perform pg_temp.ok(m like 'the Resend API key must begin re_%' and m not like '%SECRETVALUE%', 'email delivery: a key of the wrong shape is refused and not echoed');
  r := public.admin_email_delivery_save('{"email_provider":"resend","from_email":" NoReply@Example.org ","resend_api_key":"re_FixtureKey_1234abcd"}', 'route through Resend');
  perform pg_temp.ok((r->>'key_replaced')::boolean and r->'changed' @> '["email_provider","from_email","resend_api_key"]'::jsonb and r#>>'{delivery,from_email}' = 'noreply@example.org'
    and (r#>>'{delivery,key_saved}')::boolean and r#>>'{delivery,key_hint}' = 'abcd' and r::text not like '%re_FixtureKey%', 'email delivery: the save stores the key and returns only its last four characters');
  perform pg_temp.ok((select count(*) from vault.secrets where name = 'admin_resend_api_key' and secret = 're_FixtureKey_1234abcd') = 1
    and (select setting_value::text not like '%FixtureKey%' and management_mode = 'read_only' from pipeline.environment_settings where setting_key = 'admin_email_delivery')
    and (select count(*) from pipeline.admin_control_events where action = 'email_delivery_save' and detail->>'reason' = 'route through Resend' and (detail->>'key_replaced')::boolean and detail::text not like '%FixtureKey%') = 1
    and public.admin_email_delivery_read()::text not like '%FixtureKey%', 'email delivery: the key is in Vault only; not in the settings row, the control log or the read');
  r := public.admin_email_delivery_save('{"sender_name":"StudySearch Team","resend_api_key":"  "}', 'rename sender');
  perform pg_temp.ok(not (r->>'key_replaced')::boolean and r->'changed' = '["sender_name"]'::jsonb and r#>>'{delivery,key_hint}' = 'abcd' and r#>>'{delivery,email_provider}' = 'resend'
    and (select secret from vault.secrets where name = 'admin_resend_api_key') = 're_FixtureKey_1234abcd', 'email delivery: an empty key field keeps the stored key; other fields change alone');
  r := public.admin_email_delivery_save('{"resend_api_key":"re_SecondKey_9876wxyz"}', 'rotate key');
  perform pg_temp.ok((select count(*) from vault.secrets where name = 'admin_resend_api_key') = 1 and (select secret from vault.secrets where name = 'admin_resend_api_key') = 're_SecondKey_9876wxyz' and r#>>'{delivery,key_hint}' = 'wxyz', 'email delivery: a new key replaces the stored one');
  perform pg_temp.ok(pg_temp.err($$select public.svc_admin_email_delivery()$$) = 'service role required', 'email delivery: the key read is refused to a signed-in Platform Admin');
  perform set_config('fixture.role', 'service_role', true);
  perform pg_temp.ok(public.svc_admin_email_delivery()->>'resend_api_key' = 're_SecondKey_9876wxyz' and public.svc_admin_email_delivery()->>'email_provider' = 'resend', 'email delivery: the service role reads the settings and the key');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_email_delivery_save(jsonb, text)', 'execute') and not has_function_privilege('authenticated', 'public.svc_admin_email_delivery()', 'execute') and not has_function_privilege('anon', 'public.admin_email_delivery_read()', 'execute'), 'email delivery: anon reaches nothing; the key read is not callable from the browser');
  perform pg_temp.ok(not has_function_privilege('anon', 'public.admin_auth_template_settings_save(jsonb, text)', 'execute') and not has_function_privilege('authenticated', 'public.svc_admin_auth_template_settings()', 'execute'), 'anon reaches nothing; the service functions are not callable from the browser');
end $t$;
SQL
echo "admin auth email templates: all checks passed"
