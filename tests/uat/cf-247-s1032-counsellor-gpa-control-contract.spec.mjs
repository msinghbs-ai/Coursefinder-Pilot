// Guards: REQ-110 (Platform Admin 24 Nov 2026, S1-RM-Design s1024/s1026): the Counsellor Courses screen compares a student's percentage with published percentage entry minimums through the live courses_page arguments only (gpa_country, gpa_percent, gpa_qualification, gpa_meets, sort gpa); nothing is sent until a country is chosen, the helper copy names percentage-only and CBSE Class X, and the percentage is held to 0 to 100.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

async function open(page, calls) {
  await mockAdmin(page, { rank: 2, role: 'counsellor' })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async (route) => {
    const b = route.request().postDataJSON() || {}
    if ((b.p_operation || b.operation) !== 'courses_page') return route.fallback()
    const a = b.p_args || b.args || {}; calls.push(a)
    const items = [{ id: 'c1', display_title: 'Bachelor of Commerce', provider_name: 'Test University', level_name: 'Bachelor', fee_amount: 30000, fee_currency: 'AUD', field_states: {} }, { id: 'c2', display_title: 'Bachelor of Law', provider_name: 'Test University', level_name: 'Bachelor', field_states: {} }]
    return route.fulfill({ json: { total: 2, limit: 50, offset: 0, items, ...(a.gpa_country ? { gpa: { country: a.gpa_country, student_percent: a.gpa_percent, basis: 'percentage minimums only' }, gpa_minimums: { c1: 65 } } : {}) } })
  })
  await page.goto('/#courses')
  await expect(page.locator('[data-gpa-panel]')).toBeVisible()
}

test('no GPA argument is sent until a country is chosen; then the live arguments go through and the minimum column shows', async ({ page }) => {
  const calls = []; await open(page, calls)
  await expect(page.locator('[data-gpa-help]')).toContainText('percentage entry minimum')
  await expect(page.locator('[data-gpa-help]')).toContainText('CBSE Class X')
  expect(calls.every((a) => !('gpa_country' in a) && !('gpa_meets' in a))).toBe(true)
  await expect(page.locator('#uigp')).toBeDisabled()
  const opt = await page.locator('#uigc option').nth(1).getAttribute('value')
  await page.locator('#uigc').selectOption(opt)
  await page.locator('#uigp').fill('72')
  await page.locator('#uigq').fill('CBSE Class XII')
  await page.getByLabel('Only courses whose minimum I meet').check()
  await page.getByLabel('Sort by lowest entry minimum').check()
  await expect(page.locator('[data-gpa-col]')).toBeVisible()
  await expect(page.locator('[data-gpa-min]').first()).toContainText('65% · meets')
  await expect(page.locator('[data-gpa-min]').nth(1)).toContainText('Not published')
  await expect.poll(() => calls[calls.length - 1]).toMatchObject({ gpa_country: opt, gpa_percent: 72, gpa_qualification: 'CBSE Class XII', gpa_meets: true, sort: 'gpa' })
})

test('the percentage is held to 0 to 100', async ({ page }) => {
  const calls = []; await open(page, calls)
  await page.locator('#uigc').selectOption(await page.locator('#uigc option').nth(1).getAttribute('value'))
  await page.locator('#uigp').fill('250')
  await expect(page.locator('#uigp')).toHaveValue('100')
})
