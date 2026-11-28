// Guards: SS-Programme-Control 28 Nov 2026 PC-20261128-1130-DOT-STORAGE-S1-Build ("Prepare smallest endpoint off/guarded … narrow identity/expiry … kill switch"); CLAUDE.md "A passing qualification never switches anything on by itself", Layer 4 human decisions, public API errors never carry a raw database message
// CF-247 s1344. supabase/migrations/20261201040000_cf247_s1344_dot_intake_gateway_off.sql, supabase/functions/dot-intake/index.ts, .github/edge-functions.json
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201040000_cf247_s1344_dot_intake_gateway_off.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/dot-intake/index.ts', 'utf8')
const edges = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions

test('the endpoint ships switched off, grants no one and is callable only by the service role', () => {
  expect(sql).toContain("'dot_intake.on', 'DOT intake endpoint: on'")
  expect(sql).toMatch(/'dot_intake\.on'[\s\S]*?to_jsonb\(0\), 0, 1, 'switch'/)
  expect(sql).toContain("if security.pipeline_num_v1('dot_intake.on', 0) < 1 then return jsonb_build_object('ok', false, 'held', 'HELD:SWITCHED_OFF')")
  expect(sql).toContain("raise exception 'post-check: the DOT intake endpoint must ship off'")
  expect(sql).toContain("raise exception 'post-check: a role was assigned'")          // the role is created, never assigned here
  expect(sql).not.toMatch(/insert into security\.user_roles/i)
  expect(sql).toContain('revoke all on function public.svc_dot_intake_v1(text, jsonb) from public, anon, authenticated;')
  expect(sql).toContain('grant execute on function public.svc_dot_intake_v1(text, jsonb) to service_role;')
  expect(sql).toContain("('dot_submitter', 'DOT evidence submitter', 0,")
})

test('identity is narrow and expires: an active, unexpired dot_submitter assignment, decided by the database before the file is read', () => {
  expect(sql).toContain("ur.role_code = 'dot_submitter' and r.status = 'active'")
  expect(sql).toContain('(ur.expires_at is null or ur.expires_at > now())')
  expect(sql).toContain("'held', 'HELD:NOT_DOT_SUBMITTER'")
  const gate = fn.indexOf('p_action: "gate"'), form = fn.indexOf('req.formData()')
  expect(gate).toBeGreaterThan(0)
  expect(form).toBeGreaterThan(gate)
  expect(edges['dot-intake']).toBe(true)   // verify_jwt on: a signed-in caller only
  expect(fn).toContain('.auth.getUser()')
})

test('the file is checked, stored once without overwrite and submitted only through the existing structured intake writer', () => {
  expect(fn).toContain('if (sha !== stated) return json(422, { error: "sha256_mismatch"')
  expect(fn).toContain('file.size > Number(gate.max_bytes || 0)')
  expect(fn).toContain('new TextDecoder("utf-8", { fatal: true })')
  expect(fn).toContain('const path = `dot/${pkg}/${sha}.jsonl`')
  expect(fn).toContain('upsert: false')
  expect(fn).not.toMatch(/staging-boost"\)\.upload\(`?(inbound|outbound)/)
  expect(sql).toContain("public.svc_structured_intake_v1('submit', jsonb_build_object('submitter', 'dot'")
  expect(sql).toContain("'dot_intake_submit'")
  // nothing canonical, no evidence and no activation in either file
  for (const s of [sql, fn]) expect(s).not.toMatch(/insert into (catalogue|evidence)\.|admission_rules|publication_status\s*=/i)
  expect(fn).not.toMatch(/from\("(courses|course_entry_requirements|scholarships)"\)/)
})

test('errors carry fixed codes; only the platform INVALID_INPUT text is passed on', () => {
  expect(fn).toContain('m.startsWith("INVALID_INPUT:")')
  expect(fn).toContain('"submit_failed"')
  expect(fn).not.toMatch(/gateErr\.message|up\.error\.message\s*}/)
})
