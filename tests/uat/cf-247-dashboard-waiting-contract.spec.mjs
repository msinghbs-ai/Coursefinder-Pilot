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
  // v2.15.301 (Platform Admin, 20 Oct 2026, "Keep, Waiting = Inbox"): Waiting for you is the Inbox by kind; non-Inbox queues sit under Also
  test('waiting: the Inbox kinds with a count open the Inbox on that kind; other queues are under Also; cleared queues are listed briefly', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#dashboard')
    const w = page.locator('[data-waiting]')
    await expect(w.locator('[data-waiting-inbox] li')).toHaveCount(3)
    await expect(w.locator('[data-inbox-kind="held_scholarship"]')).toContainText('857')
    await expect(w.locator('[data-inbox-kind="held_scholarship"]')).toContainText('790 late')
    await expect(w).toContainText('898 items at 120 universities need a person')
    await expect(w.locator('[data-queue="review"]')).toHaveCount(0) // the old review row is the Inbox now
    await expect(w.locator('[data-waiting-also] li')).toHaveCount(2)
    await expect(w).toContainText('Clear: fee rules waiting for approval · jobs that failed in the last 24 hours')
    await w.getByRole('button', { name: 'Open Held scholarship in the Inbox' }).click()
    await expect(page).toHaveURL(/#layer-4-review\?kind=held_scholarship$/)
    await page.goto('/#dashboard')
    await page.locator('[data-waiting]').getByRole('button', { name: 'Open Flagged values to check' }).click()
    // v2.15.253: Layer 4 › Flagged values retired; v2.15.300: the old address the server still sends opens the Inbox on course links
    await expect(page).toHaveURL(/#layer-4-review\?kind=course_link$/)
  })

})
