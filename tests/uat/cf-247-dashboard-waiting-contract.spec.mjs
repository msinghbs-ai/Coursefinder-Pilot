// Guards: CF-247 dashboard waiting: v2.15.125 Dashboard "Today": what is waiting for a person comes first, each row opens the place to act.
// v2.15.125 Dashboard "Today": what is waiting for a person comes first, each row opens the place to act.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('database: the waiting list is read-only, role-filtered and never fails as a whole', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261001130000_cf247_dashboard_waiting.sql', 'utf8')
  expect(m).toContain("where (r->>'min')::int <= v_rank")
  expect((m.match(/exception when others then null; end;/g) || []).length).toBe(9)
  expect(m).toContain('revoke all on function public.admin_waiting_read() from public, anon;')
  expect(m).not.toMatch(/\b(insert|update|delete)\s/i)
})

test.describe('mocked browser', () => {
  // v2.15.301 (Platform Admin, 20 Oct 2026, "Keep, Waiting = Inbox"): Waiting for you is the Inbox; non-Inbox queues sit under Also.
  // v2.15.343 (UI audit Phase 3, 24 Oct 2026): the per-kind rows live on Layer 4 Review › By kind (one source); the Dashboard states the total and opens it

})
