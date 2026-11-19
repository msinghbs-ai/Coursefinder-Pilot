// Guards: Platform Admin 19 Nov 2026 15:38 AEDT (chat S1-Build, s778): in the Users & roles modals (Create user steps Person, Role, Sign-in, Review, and the role and edit modals) each form field is one vertical stack: the label on its own line, a full-width control of uniform 40 px height and 14 px text with right-side room for browser and password-manager icons, and the helper text underneath; no label, input and helper squeezed on one line. Checked at 1280 px (desktop) and 375 px (@responsive, phone project only).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const css = fs.readFileSync(new URL('../../src/access-roles.css', import.meta.url), 'utf8')

async function openCreateUser(page) {
  await mockAdmin(page)
  await page.route('https://example.supabase.co/functions/v1/admin-user-management', (r) => r.fulfill({ contentType: 'application/json', body: JSON.stringify({ users: [],
    roles: [{ code: 'viewer', name: 'Viewer', rank: 1, description: 'Read' }, { code: 'curator', name: 'Curator', rank: 3, description: 'Curate' }, { code: 'platform_admin', name: 'Platform Admin', rank: 6, description: 'All' }], events: [] }) }))
  await page.goto('/#users')
  await page.getByRole('button', { name: 'Create user' }).click()
  return page.locator('.cuw')
}

// every direct field of the step: label text above, control full width, helper below
async function checkFields(m) {
  return m.locator('.cuw-body > label').evaluateAll((labels) => labels.map((l) => {
    const c = l.querySelector('input:not([type=radio]):not([type=checkbox]), select'); const h = l.querySelector(':scope > small')
    const lr = l.getBoundingClientRect(); const cr = c.getBoundingClientRect(); const cs = getComputedStyle(c)
    const text = document.createRange(); text.setStart(l.firstChild, 0); text.setEnd(l.firstChild, l.firstChild.textContent.length); const tr = text.getBoundingClientRect()
    return { label: l.firstChild.textContent.trim(), direction: getComputedStyle(l).flexDirection, labelAbove: tr.bottom <= cr.top + 1, fullWidth: Math.abs(cr.width - lr.width) <= 2,
      height: Math.round(cr.height), font: cs.fontSize, padRight: parseFloat(cs.paddingRight), helperBelow: h ? h.getBoundingClientRect().top >= cr.bottom - 1 : true, wrap: c.closest('.cuw-pw') ? 'pw' : '' }
  }))
}
const expectStack = (fields) => {
  expect(fields.length).toBeGreaterThan(0)
  for (const f of fields) {
    expect(f, f.label).toMatchObject({ direction: 'column', labelAbove: true, helperBelow: true, height: 40, font: '14px' })
    if (!f.wrap) expect(f.fullWidth, `${f.label} is full width`).toBe(true)
    expect(f.padRight, `${f.label} leaves room for autofill icons`).toBeGreaterThanOrEqual(40)
  }
}

test('the field rules: vertical stack, full-width 40 px controls with right clearance, helper text below', () => {
  expect(css).toContain('.ar-modal>label,.cuw-body>label{display:flex;flex-direction:column;align-items:stretch;gap:6px;')
  expect(css).toContain('.ar-modal :is(input:not([type]),input[type=text],input[type=email],input[type=password],input[type=datetime-local],input[type=search],input[type=url],input[type=tel],input[type=number],select){box-sizing:border-box;width:100%;min-width:0;height:40px;padding:0 40px 0 12px;')
  expect(css).toContain('.ar-modal label>small{font-size:12px;line-height:1.4;color:var(--cf-slate-500);font-weight:400}')
  expect(css).toContain('.cuw-body{display:grid;gap:20px}')
})

test('Create user at 1280 px: every step stacks its fields', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  const m = await openCreateUser(page)
  await m.locator('[data-cuw-email]').fill('bdm.np@studysquare.com')
  expectStack(await checkFields(m))
  // the whole address shows (no truncation mid-domain)
  expect(await m.locator('[data-cuw-email]').evaluate((e) => e.scrollWidth <= e.clientWidth)).toBe(true)
  await m.locator('[data-cuw-name]').fill('Business Development Manager')
  await m.locator('[data-cuw-next]').click()
  await expect(m).toHaveAttribute('data-cuw-step', 'role')
  expectStack(await checkFields(m))
  await m.locator('[data-cuw-next]').click()
  await m.locator('[data-cuw-mode="password"]').check()
  expectStack(await checkFields(m))
  await m.locator('[data-cuw-password]').fill('Uat-password-2026')
  await m.locator('[data-cuw-next]').click()
  await expect(m.locator('[data-cuw-review]')).toContainText('bdm.np@studysquare.com')
})

test('Create user at phone width: fields stack and nothing overflows @responsive', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
  const m = await openCreateUser(page)
  await m.locator('[data-cuw-email]').fill('bdm.np@studysquare.com')
  expectStack(await checkFields(m))
  expect(await m.evaluate((e) => e.scrollWidth - e.clientWidth)).toBeLessThanOrEqual(1)
  await m.locator('[data-cuw-next]').click()
  expectStack(await checkFields(m))
  await m.locator('[data-cuw-next]').click()
  await m.locator('[data-cuw-mode="password"]').check()
  expectStack(await checkFields(m))
})
