// Guards: CF-247 s1093 (S2-AER overnight brief 24 Nov 2026): only runs that failed for the exact unqualified-route message and have no newer run are read again, through the existing governed
// re-read, stored copy, capped; nothing is admitted or dropped; G3 75/48 and manual locks are checked after.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261126001000_cf247_s1093_entry_matrix_requeue_unqualified_route_failures.sql', 'utf8')
const code = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('scope is the exact unqualified-route failure with no newer run, capped', () => {
  expect(code).toContain('no deterministic reader proved this table, and the entry_matrices route has no qualified model')
  expect(code).toContain('r2.created_at > r.created_at')
  expect(code).toContain('v_cap constant int := 40')
})
test('uses the governed re-read, no Firecrawl, nothing admitted or dropped', () => {
  expect(code).toContain('public.admin_entry_matrix_reread')
  expect(code).toContain('lock_not_available')
  expect(code).not.toMatch(/firecrawl/i)
  expect(code.replace(/on commit drop/g, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/insert into|update catalogue/i)
  expect(sql).toMatch(/-- Replaces: nothing/)
  expect(sql).toMatch(/-- Retires: nothing/)
})
test('G3 75/48 and manual locks are checked after', () => {
  expect(code).toContain('<> 75')
  expect(code).toContain('<> 48')
  expect(code).toContain('manual locks changed')
})
