// Decision 210: an approved fee schedule settles flagged fees it answers; the rest show the schedule's fee.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: same fee or a per-year fee within 15% settles the flag; approval runs it; hand locks left alone', () => {
  const m = read('supabase/migrations/20261001180200_cf247_fee_schedule_settles_flags.sql')
  expect(m).toContain("if r.amount = r.sched_amount then")
  expect(m).toContain("elsif r.amount > 0 and r.sched_amount / r.amount between 0.85 and 1.15 then")
  expect(m).toContain("where s.decision = 'approved' and fr.current and fr.basis = 'annual'")
  expect(m).toContain("exception when others then null; -- a value locked by hand is left for a person")
  expect(m).toContain("jsonb_build_object(''flags'', security.fee_schedule_settle_flags_v1(p_source_id))")
  expect(m).toContain("if v is distinct from '664ed3249f3c07678db0797dc18c4c8d' then raise exception")
  expect(m).toContain("if v is distinct from 'badaca6600ca02c5195491306d82440e' then raise exception")
  expect(m.toLowerCase()).not.toContain('delete from')
})

test('browser: the schedule fee is shown beside a flagged fee and can be used', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept())
  await page.goto('/#layer-4-review?tab=flags')
  const row = page.locator('tr', { has: page.locator('[data-schedule-fee]') })
  await expect(row.locator('[data-schedule-fee]')).toContainText('a year (2027)')
  await row.getByRole('button', { name: 'Use schedule fee' }).click()
  await expect.poll(() => page.l3calls.find(c => c.p_action === 'correct')).toMatchObject({ p_flag_id: 'f2', p_action: 'correct', p_args: { amount: 34900, basis: 'annual' } })
})
