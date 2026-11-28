// Guards: Platform Admin 28 Nov 2026 13:05 AEDT (private DOT intake connector over the deployed dot-intake function; credentials outside the conversation and repositories; restricted permissions, expiry, revocation and audit); SS-Programme-Control PC-20261128-DOT-AUTH-REVIEW; CLAUDE.md one key per (consumer, API version) (s935), public API errors never carry a raw database message
// CF-247 s1350. supabase/migrations/20261201080000_cf247_s1350_dot_intake_connector.sql, supabase/functions/dot-intake-connector/index.ts, .github/edge-functions.json
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201080000_cf247_s1350_dot_intake_connector.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/dot-intake-connector/index.ts', 'utf8')
const edges = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions

test('its own API version and key, registered and not issued; signs in and logs through the public entry points', () => {
  expect(sql).toContain("values ('dot', 'v1', 'dot-intake-connector', 'DOT intake connector v1', 'private.api_keys', 'active', false, 90,")
  expect(sql).toContain("values ('dot_intake_connector_v1', 'dot', 'v1', 'DOT (evidence agent)',")
  expect(sql).toContain("encode(extensions.digest(encode(extensions.gen_random_bytes(32), 'hex'), 'sha256'), 'hex'), true, 60,")
  expect(sql).toContain('[not issued]')
  expect(sql).toContain("raise exception 'post-check: the API usage read path misses a version or key: %'")
  expect(fn).toContain('svc.rpc("api_key_auth_v1", { p_platform: "dot", p_version: "v1",')
  expect(fn).toContain('svc.rpc("api_request_log_v1", { p_platform: "dot", p_version: "v1",')
  expect(fn).not.toMatch(/svc\.schema\(/)
  expect(edges['dot-intake-connector']).toBe(false)   // its own key, not a Supabase JWT
})

test('no password anywhere: a short-lived server-side session for the one bounded DOT user, never returned, signed out after the call', () => {
  expect(sql).toContain("ur.expires_at > now() and ur.expires_at <= now() + make_interval(days => v_days)")
  expect(sql).toContain("'held', 'HELD:AMBIGUOUS_DOT_IDENTITY'")
  expect(sql).toContain("revoke all on function public.svc_data_intake_identity_v1(text) from public, anon, authenticated;")
  expect(fn).toContain('svc.auth.admin.generateLink({ type: "magiclink"')
  expect(fn).toContain('pub.auth.verifyOtp({ type: "magiclink"')
  expect(fn).toContain('await svc.auth.admin.signOut(session.access_token, "local")')
  expect(fn).not.toMatch(/signInWithPassword|password\s*[:=]|PASSWORD/)
  expect((fn.match(/session\.access_token/g) || []).length).toBe(2)   // only the intake call and the sign-out use it
  const replies = fn.slice(fn.indexOf('const result = { status: r.status'), fn.indexOf('  } finally {'))
  expect(replies).not.toContain('session')
})

test('only the deployed dot-intake function is called, with the three tools; nothing writes storage or tables itself', () => {
  expect(fn).toContain('fetch(`${url}/functions/v1/dot-intake`')
  for (const t of ['upload_original', 'finalise_package', 'package_status']) expect(fn).toContain(`name: "${t}"`)
  expect(fn).not.toMatch(/\.storage\.|\.from\(\s*"/)
  for (const m of ['"initialize"', '"tools/list"', '"tools/call"', '"ping"']) expect(fn).toContain(m)
})

test('fixed error codes only', () => {
  expect(fn).toContain('const code = e instanceof Refused ? e.code : "request_failed"')
  expect(fn).not.toMatch(/error:\s*\w+Err\.message/)
})
