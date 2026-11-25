// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 14:34, S1-API-Frontend-Delivery): sign-in tells a set-up fault from a wrong password, reset links return to this site, the brand panel is shown
// CF-247 S1142. Live evidence: Supabase Auth answered the portal's password sign-ins with 401 (a refused connection key), not 400 (wrong password),
// while the screen said "That email and password did not match". The screen now says which it is, and a secret key is never sent from a browser.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { explainAuthError } from '../../portal/src/lib/authErrors.js'
import { describeKey, cleanEnv } from '../../portal/src/lib/keyInfo.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.name === 'node_modules' || e.name === 'dist' ? [] : e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]))
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url')

test('a refused connection key is a set-up fault and never reads as a wrong password', () => {
  const setup = explainAuthError({ status: 401, message: 'Invalid API key' }, { kind: 'publishable', length: 46 })
  expect(setup.kind).toBe('setup')
  expect(setup.text).toMatch(/connection key was refused/)
  expect(setup.text).toMatch(/Your email and password were not checked/)
  expect(setup.text).toContain('publishable, 46 characters')
  expect(setup.text).not.toMatch(/did not match/)
  expect(explainAuthError({ status: 403, message: 'Forbidden use of secret API key in browser' }).kind).toBe('setup')
})

test('a wrong password, an unconfirmed email, a rate limit and a lost connection each get their own words', () => {
  expect(explainAuthError({ status: 400, code: 'invalid_credentials', message: 'Invalid login credentials' }).kind).toBe('credentials')
  expect(explainAuthError({ status: 400, code: 'invalid_credentials', message: 'Invalid login credentials' }).text).toMatch(/did not match/)
  expect(explainAuthError({ status: 400, code: 'email_not_confirmed', message: 'Email not confirmed' }).kind).toBe('unconfirmed')
  expect(explainAuthError({ status: 429, code: 'over_request_rate_limit', message: 'rate limit' }).kind).toBe('rate')
  expect(explainAuthError({ status: 0, name: 'AuthRetryableFetchError', message: 'Failed to fetch' }).kind).toBe('network')
  expect(explainAuthError({ status: 500, message: 'boom' }).kind).toBe('other')
})

test('the build-time key is cleaned, classified by kind and length only, and a secret key is refused', () => {
  expect(cleanEnv('  "sb_publishable_abc123"\n')).toBe('sb_publishable_abc123')
  expect(describeKey('sb_publishable_abc123')).toEqual({ kind: 'publishable', length: 21 })
  expect(describeKey('sb_secret_abc').kind).toBe('secret')
  const anon = `${b64({ alg: 'HS256' })}.${b64({ role: 'anon' })}.sig`
  const privileged = `${b64({ alg: 'HS256' })}.${b64({ role: 'privileged' })}.sig`
  expect(describeKey(anon).kind).toBe('legacy-anon')
  expect(describeKey(privileged).kind).toBe('secret')
  expect(describeKey('').kind).toBe('missing')
  const client = read('portal/src/lib/supabase.js')
  expect(client).toMatch(/keyInfo\.kind !== 'secret'/)
  expect(client).toContain('VITE_SUPABASE_ANON_KEY')
})

test('the password reset link returns to the address the portal is served from, never to the Admin app', () => {
  const signIn = read('portal/src/screens/SignIn.jsx')
  expect(signIn).toMatch(/resetPasswordForEmail\(address, \{ redirectTo: window\.location\.origin \}\)/)
  for (const f of walk('portal/src').filter((x) => /\.(jsx?|css)$/.test(x))) expect(read(f), f).not.toMatch(/coursefinder-pilot/)
})

test('the sign-in and set-password screens show the brand panel and the stylesheet lays it out beside the form', () => {
  for (const f of ['portal/src/screens/SignIn.jsx', 'portal/src/screens/SetPassword.jsx']) expect(read(f), f).toContain('<BrandPanel />')
  const panel = read('portal/src/screens/BrandPanel.jsx')
  expect(panel).toContain('StudySearch Portal')
  expect(panel).toMatch(/Find the right course for every student/)
  expect(panel, 'wording only: no provider, course or fee figure').not.toMatch(/A\$\s?\d/)
  const css = read('portal/src/styles.css')
  expect(css).toMatch(/\.auth-split\s*\{[^}]*grid-template-columns/)
  expect(css).toMatch(/@media \(max-width:760px\)[\s\S]*\.auth-split/)
})

test('a signed-in role still resolves from the database rank (Viewer 1, Counsellor and above 2)', async () => {
  const { portalAccess } = await import('../../portal/src/lib/roles.js')
  expect(portalAccess({ authenticated: true, role: 'viewer', role_rank: 1 }).kind).toBe('viewer')
  expect(portalAccess({ authenticated: true, role: 'counsellor', role_rank: 2 }).kind).toBe('counsellor')
  expect(portalAccess({ authenticated: true, role: 'platform_admin', role_rank: 6 }).kind).toBe('counsellor')
})
