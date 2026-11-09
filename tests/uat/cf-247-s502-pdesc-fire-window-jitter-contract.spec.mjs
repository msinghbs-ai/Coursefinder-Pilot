// Guards: F-PDESC (Platform Admin Directive 3, 9 Nov 2026, Blocker D throughput): the reader's dispatch guard tolerates fire jitter so a fire exactly one pdesc.every_minutes window after the last dispatch is sent; the edit is one guarded line (live body md5 before and after), changes no setting, job or schedule, drops nothing and touches no consumer API (G3).
// Source contract over migration 20261109110000.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const body = fs.readFileSync('supabase/migrations/20261109110000_cf247_pdesc_fire_window_jitter.sql', 'utf8')
const code = body.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('the edit is guarded by the live body md5 before and after and applies exactly once', () => {
  expect(body).toContain('fc835699c88759e4a0b12c6d95e47965')
  expect(body).toContain('21662da5fc9c4e15facbaef47b63a50f')
  expect(code).toContain('must apply exactly once')
  expect(code).toContain('already applied')
})

test('the only change is the 30-second tolerance on the dispatch window, marked fixed', () => {
  expect(code).toMatch(/\+ interval '30 seconds'; -- fixed: fire jitter/)
  expect(code).not.toMatch(/cron\.(schedule|alter_job)/i)
  expect(code).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/i)
})

test('governance: replaces and retires lines, nothing dropped, no consumer API object', () => {
  expect(body).toMatch(/^-- Replaces: /m)
  expect(body).toMatch(/^-- Retires: nothing/m)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1/)
})
