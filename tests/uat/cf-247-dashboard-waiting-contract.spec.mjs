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
  test('waiting rows with a count come first and open the right tab; cleared queues are listed briefly', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#dashboard')
    const w = page.locator('[data-waiting]')
    await expect(w.locator('li')).toHaveCount(3)
    await expect(w.locator('[data-queue="review"]')).toContainText('1,803')
    await expect(w).toContainText('Clear: fee rules waiting for approval · jobs that failed in the last 24 hours')
    await w.getByRole('button', { name: 'Open Flagged values to check' }).click()
    await expect(page).toHaveURL(/#layer-4-review\?tab=flags$/)
  })
})
