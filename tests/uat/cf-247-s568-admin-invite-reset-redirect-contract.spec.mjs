// Guards: Admin invite and password reset links (Platform Admin 16 Nov 2026 22:12, Feature 1): a Platform Admin can send a password reset to a non-Admin account (never a Platform Admin, their own account, the system account, a disabled account or an open invitation; checked on screen and again by the server); every invitation and reset passes redirectTo = the admin sign-in on the Cloudflare Worker (never a supabase.co address) and an invitation carries data { role, guide_url, full_name } for the Supabase template; the link lands on a set-password screen
// CF-247 S568. Edge function admin-user-management, src/access-roles-api.js, src/access-roles-entry.jsx, src/mature-main.jsx, src/lib/supabase.js. No migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const EDGE = fs.readFileSync('supabase/functions/admin-user-management/index.ts', 'utf8')
const API = fs.readFileSync('src/access-roles-api.js', 'utf8')
const SCREEN = fs.readFileSync('src/access-roles-entry.jsx', 'utf8')
const SHELL = fs.readFileSync('src/mature-main.jsx', 'utf8')
const CLIENT = fs.readFileSync('src/lib/supabase.js', 'utf8')
const code = (s) => s.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n')

// the edge function's own address rule, run with a stand-in environment
const loginUrlOf = (env) => {
  const src = /function adminLoginUrl\(\): string \{[\s\S]*?\n\}/.exec(EDGE)[0].replace('(): string', '()')
  const origin = /const WORKER_ORIGIN = "([^"]+)";/.exec(EDGE)[1]
  return new Function('Deno', 'WORKER_ORIGIN', `${src}; return adminLoginUrl()`)({ env: { get: (k) => env[k] } }, origin)
}

test('the admin sign-in address is the Cloudflare Worker, and a supabase.co or non-https override is refused', () => {
  expect(loginUrlOf({})).toBe('https://coursefinder-pilot.techm.workers.dev/')
  expect(loginUrlOf({ ADMIN_LOGIN_URL: 'https://admin.studysearch.example/' })).toBe('https://admin.studysearch.example/')
  expect(loginUrlOf({ ADMIN_LOGIN_URL: 'https://fxcwkweaxjtknorudmwp.supabase.co/auth/v1' })).toBe('https://coursefinder-pilot.techm.workers.dev/')
  expect(loginUrlOf({ ADMIN_LOGIN_URL: 'http://insecure.example/' })).toBe('https://coursefinder-pilot.techm.workers.dev/')
  expect(EDGE).toContain('const guideUrl = (login: string) => login + "#platform-guide";')
})

test('an invitation passes redirectTo and the template data role, guide_url and full_name', () => {
  const c = code(EDGE)
  const invite = c.slice(c.indexOf('inviteUserByEmail(email, {'), c.indexOf('});', c.indexOf('inviteUserByEmail(email, {')))
  expect(invite).toContain('redirectTo: login,')
  for (const k of ['role:', 'role_code:', 'guide_url: guideUrl(login),', 'full_name: fullName || null,']) expect(invite).toContain(k)
  expect(c).toContain('const login = adminLoginUrl();')
  expect(API).toContain("full_name: mode === 'invite' ? fullName : undefined")
  expect(SCREEN).toContain("fullName:fullName.trim()")
})

test('reset_password: Platform Admin only, never a Platform Admin, self, system, disabled or open-invitation account; redirectTo is the admin sign-in', () => {
  const c = code(EDGE)
  expect(c).toContain('if (Number(context?.role_rank || 0) < 6) return reply(req, 403, { error: "platform_admin_role_required" });')
  const reset = c.slice(c.indexOf('if (action === "reset_password") {'), c.indexOf('if (action === "delete") {'))
  for (const e of ['reset_own_password_from_sign_in', 'system_account_has_no_reset', 'account_disabled_enable_first', 'invitation_not_yet_accepted', 'platform_admin_resets_own_password']) expect(reset).toContain(`"${e}"`)
  expect(reset).toContain('a.role_code === "platform_admin"')
  expect(reset).toContain('await serviceClient.auth.resetPasswordForEmail(email, { redirectTo: login });')
  expect(API).toContain("resetPassword: (userId) => invoke({ action: 'reset_password', user_id: userId }),")
  for (const why of ['Reset your own password from the sign-in screen', 'A Platform Admin resets their own password', 'Enable the account first', 'Invitation not accepted yet']) expect(SCREEN).toContain(why)
  expect(SCREEN).toContain('data-reset-password={user.id}')
})

test('no redirect anywhere points at a supabase.co address', () => {
  for (const src of [EDGE, API, SCREEN, SHELL]) {
    for (const m of code(src).matchAll(/redirectTo\s*:\s*([^,}\n]+)/g)) expect(m[1]).not.toMatch(/supabase\.co/i)
  }
  expect(SHELL).toContain('resetPasswordForEmail(email,{redirectTo:`${location.origin}/`})')
})

test('the link lands on a set-password screen (invite or recovery) before the workspace', () => {
  expect(CLIENT).toMatch(/export const AUTH_LINK_TYPE = \(\(\) => \{[\s\S]*type=\(invite\|recovery\)/)
  expect(CLIENT.indexOf('export const AUTH_LINK_TYPE')).toBeLessThan(CLIENT.indexOf('export const supabase = createClient('))
  expect(SHELL).toContain("if(event==='PASSWORD_RECOVERY')setPasswordSetup('recovery')")
  expect(SHELL).toContain('if(passwordSetup)return <SetPassword kind={passwordSetup} user={session.user} onDone={()=>setPasswordSetup(null)}/>')
  expect(SHELL).toContain('await supabase.auth.updateUser({password:pw})')
  expect(SHELL).toContain("if(pw.length<12){setErr('Use at least 12 characters.');return}")
})
