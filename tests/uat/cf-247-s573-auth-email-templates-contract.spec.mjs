// Guards: Users & roles › Links & Email Templates (Platform Admin 17 Nov 2026 14:40): the Admin site URL, guide link and the Invite User and Reset Password emails are edited by a Platform Admin only, a save needs a reason and is logged, Supabase Auth is changed only through the edge function when a management token is set, the preview cannot run scripts, and the consumer API is not touched. Follow-up (Platform Admin 17 Nov 2026 15:45): an open invitation can be sent again from the user row, and while no management token is set the screen warns that Supabase Auth keeps the previous emails and offers the HTML to paste. Decisions (Platform Admin 17 Nov 2026 16:13): no account token is kept in the edge function (Auth is synced by the admin workflow), a missing name leaves no stray comma, and custom SMTP (Resend) is a Go-live checklist item. Email delivery provider (Platform Admin 17 Nov 2026 16:24): invitations and resets can go through Resend; the API key is write-only, kept in Vault, read by the service role only and never returned, logged or echoed.
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/admin-auth-email-templates/run.sh (workflow admin-auth-email-templates-test); these checks keep the rules in the migration, the edge function and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261117152700_cf247_admin_auth_email_templates.sql')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const edge = read('supabase/functions/admin-user-management/index.ts')
const nav = read('src/nav-map.js'), main = read('src/mature-main.jsx'), screen = read('src/AuthEmailTemplates.jsx'), apiSrc = read('src/access-roles-api.js')

test('the migration stores the settings in the existing settings table, drops nothing and passes the deploy gate', () => {
  expect(m).toContain('-- Replaces: nothing.'); expect(m).toContain('-- Retires: nothing.')
  expect(code).not.toMatch(/create table/i)
  expect(code).toContain('insert into pipeline.environment_settings(')
  for (const l of m.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /i)
  expect(code).not.toMatch(/website_v2_|website_v3_|zoho_v2_|zoho_v3_|website_edge_|zoho_edge_|\bapi\./)
})

test('read and save are the Platform Admin\'s; a save needs a reason and writes the control log', () => {
  for (const fn of ['admin_auth_template_settings_read()', 'admin_auth_template_settings_save(p_payload jsonb, p_reason text)']) expect(code).toContain(`function public.${fn}`)
  expect(code.match(/security\.current_role_rank\(\), 0\) < 6/g).length).toBe(2)
  expect(code).toContain("raise exception 'a reason is required'")
  expect(code).toContain("values ('access', 'auth_templates_save', 'admin_auth_email_templates'")
  expect(code).toContain("revoke all on function public.admin_auth_template_settings_save(jsonb, text) from public, anon;")
  expect(code).toContain("revoke all on function public.svc_admin_auth_template_settings() from public, anon, authenticated;")
})

test('a template keeps {{link}}, uses only the five variables and no script; the default is the branded template', () => {
  expect(code).toContain("position('{{link}}' in v_body) = 0")
  expect(code).toContain("v_tok not in ('link', 'guide_link', 'user_email', 'user_name', 'role')")
  expect(code).toContain("v_body ~* '<\\s*script'")
  expect(m).toContain('background:#0b6e5f'); expect(m).toContain('StudySearch PIM Admin')
})

test('the edge function copies to Supabase Auth only with a management token, translating the variables', () => {
  expect(edge).toContain('Deno.env.get("SB_MANAGEMENT_TOKEN")')
  expect(edge).toContain('link: "{{ .ConfirmationURL }}", user_email: "{{ .Email }}", user_name: "{{ .Data.full_name }}", role: "{{ .Data.role }}"')
  const sync = edge.slice(edge.indexOf('if (action === "auth_templates_sync")'), edge.indexOf('if (action === "auth_template_test")'))
  expect(sync).toContain('if (token && ref) {')
  for (const k of ['site_url:', 'mailer_subjects_invite:', 'mailer_templates_invite_content:', 'mailer_subjects_recovery:', 'mailer_templates_recovery_content:']) expect(sync).toContain(k)
  expect(sync).toContain('`https://api.supabase.com/v1/projects/${ref}/config/auth`')
  expect(sync).toContain('p_action: "auth_templates_sync"')
  // the three actions sit after the Platform Admin check
  expect(edge.indexOf('platform_admin_role_required')).toBeLessThan(edge.indexOf('if (action === "auth_templates_status")'))
  // the token is never returned or logged
  expect(edge).not.toMatch(/reply\([^)]*managementToken\(\)\s*[,}]/)
  // the translation, run as written
  const src = /function toAuthTemplate\([\s\S]*?\n\}/.exec(edge)[0].replace('(text: string, guideLink: string): string', '(text, guideLink)').replace('(_m, t)', '(_m, t)')
  const toAuth = new Function('TEMPLATE_TOKENS', 'escHtml', `${src}; return toAuthTemplate`)({ link: '{{ .ConfirmationURL }}', user_email: '{{ .Email }}', user_name: '{{ .Data.full_name }}', role: '{{ .Data.role }}' }, (v) => v.replace(/&/g, '&amp;').replace(/"/g, '&quot;'))
  expect(toAuth('<a href="{{link}}">{{ user_name }}</a> {{user_email}} {{role}} {{guide_link}}', 'https://x.example/#g')).toBe('<a href="{{ .ConfirmationURL }}">{{ if .Data.full_name }}{{ .Data.full_name }}{{ end }}</a> {{ .Email }} {{ .Data.role }} https://x.example/#g')
  // v2.16.22 (Platform Admin 17 Nov 2026 16:13): with no name the greeting is "Welcome" or "Hello,", never "Welcome, " or "Hello ,"
  expect(toAuth('<h2>Welcome, {{user_name}}</h2><p>Hello {{user_name}}, a reset</p>', '')).toBe('<h2>Welcome{{ if .Data.full_name }}, {{ .Data.full_name }}{{ end }}</h2><p>Hello{{ if .Data.full_name }} {{ .Data.full_name }}{{ end }}, a reset</p>')
})

test('a test email is the Reset Password email to an existing account; an invitation is not sent as a test', () => {
  const t = edge.slice(edge.indexOf('if (action === "auth_template_test")'), edge.indexOf('if (action === "list")'))
  expect(t).toContain('if (template !== "recovery") return reply(req, 409')
  expect(t).toContain('test_address_has_no_account')
  expect(t).not.toContain('inviteUserByEmail')
})

test('Users & roles has two Platform Admin tabs and the screen offers the controls asked for', () => {
  expect(nav).toContain("{ key: 'directory', label: 'Users & roles', min: 6 },")
  expect(nav).toContain("{ key: 'templates', label: 'Links & Email Templates', min: 6 },")
  expect(main).toContain("case'users':if(tab==='templates')return <AuthEmailTemplates rank={rank} onError={onError}/>")
  expect(screen).toContain("if(rank<6)return <EmptyInline text=\"Links & Email Templates opens for the Platform Admin.\"/>")
  for (const k of ['data-aet-site-url', 'data-aet-guide-link', 'data-aet-kind={k}', 'data-aet-token={k}', 'data-aet-subject', 'data-aet-body', 'data-aet-preview', 'data-aet-reset', 'data-aet-test', 'data-aet-reason', 'data-aet-save']) expect(screen).toContain(k)
  expect(screen).toContain("export const TOKENS=['link','guide_link','user_email','user_name','role']")
  expect(screen).toContain('sandbox=""') // the preview frame runs no script
  expect(screen).toContain("rpc('admin_auth_template_settings_save',{p_payload:form,p_reason:why})")
  expect(screen).toContain('reason.trim().length<4')
  for (const a of ["templatesStatus: () => invoke({ action: 'auth_templates_status' })", "templatesSync: () => invoke({ action: 'auth_templates_sync' })"]) expect(apiSrc).toContain(a)
})

test('Resend invite: an open invitation only, Platform Admin only, recorded in the access history', () => {
  const r = edge.slice(edge.indexOf('if (action === "resend_invite")'), edge.indexOf('// 16 Oct 2026 (Platform Admin: "only Platform admin'))
  expect(edge.indexOf('platform_admin_role_required')).toBeLessThan(edge.indexOf('if (action === "resend_invite")'))
  for (const e of ['system_account_has_no_invitation', 'account_disabled_enable_first', 'invitation_already_accepted_use_reset_password']) expect(r).toContain(`"${e}"`)
  expect(r).toContain('serviceClient.auth.admin.inviteUserByEmail(email, {')
  expect(r).toContain('redirectTo: login,')
  expect(r).toContain('p_action: "user_invited",'); expect(r).toContain('resent: true')
  const rows = read('src/access-roles-entry.jsx')
  expect(rows).toContain("export const inviteOpen=user=>!user.email_confirmed_at&&!user.disabled&&!String(user.email||'').endsWith('.invalid')")
  expect(rows).toContain('data-resend-invite={user.id}')
  expect(rows).toContain('data-reset-password={user.id}')
  expect(apiSrc).toContain("resendInvite: (userId) => invoke({ action: 'resend_invite', user_id: userId }),")
})

test('with no management token the screen warns and offers the HTML as Supabase Auth reads it', () => {
  expect(screen).toContain('status&&status.management_token_configured===false&&!viaResend&&<div className="aet-banner" role="alert" data-aet-no-token>')
  expect(screen).toContain('Saving here does not change the emails Supabase Auth sends.')
  expect(screen).toContain('supabase-auth-config.yml') // decision 17 Nov 2026 16:13: Auth is synced by the admin workflow; no account token in the edge function
  expect(screen).toContain('data-aet-copy-html>Copy HTML for Supabase Dashboard</Button>')
  const src = /export const toAuthTemplate=[^\n]+/.exec(screen)[0].replace('export const toAuthTemplate=', 'return ')
  const toAuth = new Function('AUTH_TOKENS', 'esc', src)({ link: '{{ .ConfirmationURL }}', user_email: '{{ .Email }}', user_name: '{{ .Data.full_name }}', role: '{{ .Data.role }}' }, (v) => v)
  expect(toAuth('<a href="{{link}}">{{user_name}}</a> {{ role }} {{guide_link}}', 'https://x.example/#g')).toBe('<a href="{{ .ConfirmationURL }}">{{ if .Data.full_name }}{{ .Data.full_name }}{{ end }}</a> {{ .Data.role }} https://x.example/#g')
  expect(toAuth('Welcome, {{user_name}}', '')).toBe('Welcome{{ if .Data.full_name }}, {{ .Data.full_name }}{{ end }}')
})

test('custom SMTP (Resend) is on the Go-live checklist as a deployment step; the migration adds one row and changes nothing else', () => {
  const g = read('supabase/migrations/20261117163000_cf247_golive_auth_custom_smtp.sql')
  const c = g.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(g).toContain('-- Replaces: nothing.'); expect(g).toContain('-- Retires: nothing.')
  expect(c).toContain("'auth_custom_smtp', 'auth', 'Auth custom SMTP (Resend)'"); expect(c).toContain("'deployment_managed', 'production', true, 'pending'")
  expect(c).toContain('on conflict (setting_key) do nothing')
  expect(c).not.toMatch(/create (or replace )?(function|table)|\bupdate\b|smtp_pass\s*=|re_[A-Za-z0-9]{8,}/i)
  for (const l of g.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /i)
})

test('email delivery: the Resend key is write-only, in Vault, and only the service role reads it', () => {
  const d = read('supabase/migrations/20261117170000_cf247_admin_email_delivery_resend.sql')
  const c = d.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(d).toContain('-- Replaces: nothing.'); expect(d).toContain('-- Retires: nothing.')
  expect(c).not.toMatch(/create table/i)
  for (const l of d.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /i)
  expect(c).not.toMatch(/website_v2_|website_v3_|zoho_v2_|zoho_v3_|website_edge_|zoho_edge_|\bapi\./)
  expect(c.match(/security\.current_role_rank\(\), 0\) < 6/g).length).toBe(2)
  expect(c).toContain("perform vault.create_secret(v_key, 'admin_resend_api_key'"); expect(c).toContain('perform vault.update_secret(v_id, v_key);')
  // the only place the key is read out is the service function; the read for the screen and the settings row never carry it
  expect(c.match(/decrypted_secret\b/g).length).toBe(1)
  expect(c).toContain("if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required'")
  expect(c).toContain('revoke all on function public.svc_admin_email_delivery() from public, anon, authenticated;')
  const save = c.slice(c.indexOf('function public.admin_email_delivery_save'), c.indexOf('function public.svc_admin_email_delivery'))
  expect(save).toContain("'key_replaced', v_key is not null"); expect(save).toContain("right(v_key, 4)")
  expect(save).not.toMatch(/raise exception[^;]*%[^;]*v_key/) // no error message carries the key
  expect(save).not.toMatch(/jsonb_build_object\([^;]*'resend_api_key', v_key/)
})

test('email delivery: with Resend in use the edge function makes the link without sending and sends the saved template through Resend', () => {
  expect(edge).toContain('serviceClient.rpc("svc_admin_email_delivery")'); expect(edge).toContain('Deno.env.get("RESEND_API_KEY")')
  expect(edge).toContain('effective: configured === "resend" && key && ')
  expect(edge).toContain('fetch("https://api.resend.com/emails", {')
  expect(edge).toContain('from: `${d.senderName} <${d.fromEmail}>`')
  expect(edge.match(/generateLink\(\{ type: "invite", email, options: \{ redirectTo: login, data: /g).length).toBe(2) // Create user and Resend invite
  expect(edge).toContain('generateLink({ type: "recovery", email, options: { redirectTo: login } })')
  expect(edge.match(/if \(delivery\.effective === "resend"\)/g).length).toBe(4)
  expect(edge).toContain('await serviceClient.auth.admin.deleteUser(data.user.id).catch(() => undefined); // nothing was sent, so no account is left behind')
  // the key leaves only as the Resend bearer; the status answer names its source, never the key
  expect(edge.match(/d\.key\b/g).length).toBe(1)
  expect(edge).toContain('delivery: { configured: d.configured, effective: d.effective, key_source: d.keySource, sender_name: d.senderName, from_email: d.fromEmail } });')
  expect(edge).not.toMatch(/console\.(log|warn|error)\([^)]*\bkey\b/)
  // a person's values are HTML-escaped and a missing name takes its comma with it
  const src = /function renderEmail\([\s\S]*?\n\}/.exec(edge)[0].replace('(text: string, v: Record<string, string>, html: boolean): string', '(text, v, html)').replace('(x: string)', '(x)')
  const render = new Function('escHtml', `${src}; return renderEmail`)((v) => v.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'))
  expect(render('<h2>Welcome, {{user_name}}</h2><a href="{{link}}">{{role}}</a>', { user_name: '', link: 'https://x.example/v?a=1&b=2', role: 'Curator' }, true)).toBe('<h2>Welcome</h2><a href="https://x.example/v?a=1&amp;b=2">Curator</a>')
  expect(render('Welcome, {{ user_name }}', { user_name: '<b>Al</b>' }, true)).toBe('Welcome, &lt;b&gt;Al&lt;/b&gt;')
})

test('email delivery: the screen has the provider toggle, sender, from email and a masked key that is sent only when typed', () => {
  for (const k of ['data-aet-delivery', 'data-aet-provider={k}', 'data-aet-sender-name', 'data-aet-from-email', 'data-aet-resend-key', 'data-aet-delivery-status']) expect(screen).toContain(k)
  expect(screen).toContain("[['supabase','Supabase Built-in'],['resend','Resend API']]")
  expect(screen).toContain('<input type="password" autoComplete="new-password" spellCheck={false} value={newKey}')
  expect(screen).toContain("label={dv?.key_saved?`Saved (re_••••${dv.key_hint||''})`:'No key saved'}")
  expect(screen).toContain("const payload={...dform,...(newKey.trim()?{resend_api_key:newKey.trim()}:{})}")
  expect(screen).toContain("rpc('admin_email_delivery_save',{p_payload:payload,p_reason:why})")
  expect(screen).toContain("setNewKey('');said.push(") // the typed key is cleared from the screen once saved
  expect(screen.indexOf('data-aet-delivery>')).toBeLessThan(screen.indexOf('data-aet-templates>')) // above the template editor
})
